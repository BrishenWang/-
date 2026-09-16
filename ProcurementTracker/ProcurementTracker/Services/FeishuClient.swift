import Foundation
import Observation
import AuthenticationServices
import CryptoKit
import Security
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - 错误定义

enum FeishuError: LocalizedError {
    case notConfigured
    case invalidRedirect
    case loginCancelled
    case stateMismatch
    case loginFailed(String)
    case networkError
    case httpError(Int)
    case api(Int, String)
    case noCalendar
    case tokenExpired

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "请先在设置中填写飞书自建应用的 App ID 与 App Secret。"
        case .invalidRedirect:
            return "重定向地址格式不正确，请检查设置中的 Redirect URI。"
        case .loginCancelled:
            return "已取消飞书授权。"
        case .stateMismatch:
            return "授权校验失败（state 不匹配），请重试。"
        case .loginFailed(let message):
            return "飞书授权失败：\(message)"
        case .networkError:
            return "网络请求失败，请检查网络后重试。"
        case .httpError(let code):
            return "飞书服务器返回异常（HTTP \(code)）。"
        case .api(let code, let message):
            return "飞书接口错误（\(code)）：\(message)"
        case .noCalendar:
            return "未获取到飞书主日历，请确认应用已开通日历权限。"
        case .tokenExpired:
            return "飞书登录已过期，请重新授权。"
        }
    }
}

// MARK: - 飞书客户端

/// 飞书 OAuth 授权与日历 API 客户端（授权码 + PKCE，user_access_token）
@MainActor
@Observable
final class FeishuClient {
    let settings: AppSettings

    private(set) var isLoggedIn = false
    private(set) var isAuthenticating = false
    private(set) var lastError: String?

    private var token: FeishuToken?
    private var authSession: ASWebAuthenticationSession?
    private var refreshTask: Task<String, Error>?
    private let presentationProvider = WebAuthPresentationProvider()

    /// 申请的用户授权：日历读写 + 离线访问（用于刷新令牌）
    private static let scope = "calendar:calendar offline_access"

    init(settings: AppSettings) {
        self.settings = settings
        self.token = KeychainHelper.getCodable(FeishuToken.self, for: KeychainHelper.Key.feishuToken)
        self.isLoggedIn = self.token != nil
    }

    var displayName: String {
        settings.feishuUserName.isEmpty ? "飞书账号" : settings.feishuUserName
    }

    // MARK: - 登录 / 登出

    /// 发起飞书授权登录
    func login() async throws {
        guard !settings.feishuAppID.isEmpty, !settings.feishuAppSecret.isEmpty else {
            throw FeishuError.notConfigured
        }
        guard let redirectURL = URL(string: settings.redirectURI),
              let callbackScheme = redirectURL.scheme, !callbackScheme.isEmpty else {
            throw FeishuError.invalidRedirect
        }

        isAuthenticating = true
        lastError = nil
        defer { isAuthenticating = false }

        let verifier = Self.generateCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let state = UUID().uuidString

        var components = URLComponents(string: settings.domain.accountsHost + "/open-apis/authen/v1/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: settings.feishuAppID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: settings.redirectURI),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let authURL = components.url else { throw FeishuError.invalidRedirect }

        let callbackURL = try await startAuthSession(url: authURL, callbackScheme: callbackScheme)

        guard let queryItems = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems else {
            throw FeishuError.loginFailed("回调地址无法解析")
        }
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            if error == "access_denied" { throw FeishuError.loginCancelled }
            throw FeishuError.loginFailed(error)
        }
        guard queryItems.first(where: { $0.name == "state" })?.value == state else {
            throw FeishuError.stateMismatch
        }
        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            throw FeishuError.loginFailed("未获取到授权码")
        }

        let token = try await exchangeCode(code, verifier: verifier)
        self.token = token
        saveToken(token)
        isLoggedIn = true

        let user = try await fetchUserInfo()
        settings.feishuUserName = user.name ?? "飞书用户"
        settings.feishuCalendarID = ""
        _ = try await ensureCalendarID()
    }

    func logout() {
        token = nil
        KeychainHelper.delete(KeychainHelper.Key.feishuToken)
        settings.feishuUserName = ""
        settings.feishuCalendarID = ""
        isLoggedIn = false
        lastError = nil
    }

    // MARK: - 授权会话

    private func startAuthSession(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let error = error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionError.errorDomain
                        && nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: FeishuError.loginCancelled)
                    } else {
                        continuation.resume(throwing: FeishuError.loginFailed(error.localizedDescription))
                    }
                    return
                }
                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: FeishuError.loginFailed("未收到回调"))
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = presentationProvider
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }
    }

    // MARK: - 令牌

    private func exchangeCode(_ code: String, verifier: String) async throws -> FeishuToken {
        var body: [String: String] = [
            "grant_type": "authorization_code",
            "client_id": settings.feishuAppID,
            "client_secret": settings.feishuAppSecret,
            "code": code,
            "redirect_uri": settings.redirectURI,
            "code_verifier": verifier
        ]
        // scope 缺省时，令牌继承用户授权时授予的全部权限
        return try await requestToken(body: &body)
    }

    private func performRefresh() async throws -> String {
        guard let refreshTokenValue = token?.refreshToken, !refreshTokenValue.isEmpty else {
            logout()
            throw FeishuError.tokenExpired
        }
        var body: [String: String] = [
            "grant_type": "refresh_token",
            "client_id": settings.feishuAppID,
            "client_secret": settings.feishuAppSecret,
            "refresh_token": refreshTokenValue
        ]
        let refreshed = try await requestToken(body: &body)
        return refreshed.accessToken
    }

    private func requestToken(body: inout [String: String]) async throws -> FeishuToken {
        var request = URLRequest(url: URL(string: settings.domain.openAPIBaseURL + "/authen/v2/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        _ = try Self.ensureHTTPStatus(data, response)

        let result = try JSONDecoder().decode(TokenResponse.self, from: data)
        if let code = result.code, code != 0 {
            let message = result.errorDescription ?? result.msg ?? "错误码 \(code)"
            throw FeishuError.api(code, message)
        }
        guard let accessToken = result.accessToken, let expiresIn = result.expiresIn else {
            throw FeishuError.loginFailed(result.errorDescription ?? "未获取到访问令牌")
        }
        let feishuToken = FeishuToken(
            accessToken: accessToken,
            refreshToken: result.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            scope: result.scope
        )
        saveToken(feishuToken)
        self.token = feishuToken
        return feishuToken
    }

    /// 返回有效的 access token，必要时自动刷新
    private func validAccessToken() async throws -> String {
        guard let token else { throw FeishuError.tokenExpired }
        if token.expiresAt > Date().addingTimeInterval(300) {
            return token.accessToken
        }
        if let refreshTask {
            return try await refreshTask.value
        }
        let task = Task<String, Error> { [weak self] in
            guard let self else { throw FeishuError.tokenExpired }
            return try await self.performRefresh()
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func saveToken(_ token: FeishuToken) {
        KeychainHelper.setCodable(token, for: KeychainHelper.Key.feishuToken)
    }

    // MARK: - 用户信息

    private func fetchUserInfo() async throws -> UserInfo {
        let request = URLRequest(url: URL(string: settings.domain.openAPIBaseURL + "/authen/v1/user_info")!)
        let data = try await authorizedData(for: request)
        let response = try JSONDecoder().decode(FeishuResponse<UserInfo>.self, from: data)
        guard response.code == 0, let user = response.data else {
            throw FeishuError.api(response.code, response.msg ?? "获取用户信息失败")
        }
        return user
    }

    // MARK: - 日历

    /// 获取（并缓存）用户主日历 ID
    func ensureCalendarID() async throws -> String {
        if !settings.feishuCalendarID.isEmpty {
            return settings.feishuCalendarID
        }
        var request = URLRequest(url: URL(string: settings.domain.openAPIBaseURL + "/calendar/v4/calendars/primary")!)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        let data = try await authorizedData(for: &request)
        let response = try JSONDecoder().decode(FeishuResponse<PrimaryCalendarData>.self, from: data)
        guard response.code == 0 else {
            throw FeishuError.api(response.code, response.msg ?? "查询主日历失败")
        }
        guard let id = response.data?.calendars.first(where: { $0.type == "primary" })?.calendarID
            ?? response.data?.calendars.first?.calendarID else {
            throw FeishuError.noCalendar
        }
        settings.feishuCalendarID = id
        return id
    }

    /// 在飞书主日历上创建提醒日程，返回日程 ID
    func createReminderEvent(title: String, description: String, date: Date, idempotencyKey: String) async throws -> String {
        let calendarID = try await ensureCalendarID()
        let urlString = settings.domain.openAPIBaseURL
            + "/calendar/v4/calendars/\(Self.pathEscaped(calendarID))/events?idempotency_key=\(Self.queryEscaped(idempotencyKey))"
        guard let url = URL(string: urlString) else { throw FeishuError.invalidRedirect }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let timezone = settings.timezoneIdentifier
        let startTimestamp = String(Int(date.timeIntervalSince1970))
        let endTimestamp = String(Int(date.addingTimeInterval(30 * 60).timeIntervalSince1970))
        let payload = CreateEventBody(
            summary: title,
            description: description,
            startTime: EventTime(timestamp: startTimestamp, timezone: timezone),
            endTime: EventTime(timestamp: endTimestamp, timezone: timezone),
            reminders: [EventReminder(minutes: 30)],
            needNotification: true,
            freeBusyStatus: "free"
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let data = try await authorizedData(for: &request)
        let response = try JSONDecoder().decode(FeishuResponse<EventData>.self, from: data)
        guard response.code == 0, let eventID = response.data?.event.eventID else {
            throw FeishuError.api(response.code, response.msg ?? "创建日程失败")
        }
        return eventID
    }

    /// 删除飞书日程；日程已不存在时视为成功
    func deleteReminderEvent(eventID: String) async throws {
        let calendarID = try await ensureCalendarID()
        let urlString = settings.domain.openAPIBaseURL
            + "/calendar/v4/calendars/\(Self.pathEscaped(calendarID))/events/\(Self.pathEscaped(eventID))?need_notification=false"
        guard let url = URL(string: urlString) else { return }

        let request = URLRequest(url: url)
        var deleteRequest = request
        deleteRequest.httpMethod = "DELETE"

        do {
            _ = try await authorizedData(for: &deleteRequest)
        } catch FeishuError.api(let code, _) where code == 193001 || code == 191000 || code == 191003 {
            // 日程或日历已删除，忽略
        }
    }

    // MARK: - 网络辅助

    /// 带 Bearer 令牌发起请求；401 时强制刷新一次并重试
    private func authorizedData(for request: URLRequest) async throws -> Data {
        var request = request
        let tokenValue = try await validAccessToken()
        request.setValue("Bearer \(tokenValue)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            let refreshedToken = try await forceRefresh()
            var retry = request
            retry.setValue("Bearer \(refreshedToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await URLSession.shared.data(for: retry)
            return try Self.ensureHTTPStatus(retryData, retryResponse)
        }
        return try Self.ensureHTTPStatus(data, response)
    }

    private func forceRefresh() async throws -> String {
        if let refreshTask { return try await refreshTask.value }
        let task = Task<String, Error> { [weak self] in
            guard let self else { throw FeishuError.tokenExpired }
            return try await self.performRefresh()
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private static func ensureHTTPStatus(_ data: Data, _ response: URLResponse) throws -> Data {
        guard let http = response as? HTTPURLResponse else {
            throw FeishuError.networkError
        }
        guard (200...299).contains(http.statusCode) else {
            if let body = try? JSONDecoder().decode(TokenResponse.self, from: data),
               let code = body.code, code != 0 {
                throw FeishuError.api(code, body.errorDescription ?? body.msg ?? "HTTP \(http.statusCode)")
            }
            throw FeishuError.httpError(http.statusCode)
        }
        return data
    }

    private static func pathEscaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func queryEscaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    // MARK: - PKCE

    static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

// MARK: - 授权页面展示锚点

@MainActor
final class WebAuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            #if os(macOS)
            if let window = NSApplication.shared.windows.first(where: { $0.isVisible }) {
                return window
            }
            return NSWindow()
            #else
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let active = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
            if let window = active?.windows.first(where: { $0.isKeyWindow }) ?? active?.windows.first {
                return window
            }
            return UIWindow()
            #endif
        }
    }
}

// MARK: - 数据模型

struct FeishuToken: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
    let scope: String?
}

struct TokenResponse: Decodable {
    let code: Int?
    let msg: String?
    let accessToken: String?
    let expiresIn: Int?
    let refreshToken: String?
    let scope: String?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case code, msg, scope, error
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case errorDescription = "error_description"
    }
}

struct FeishuResponse<T: Decodable>: Decodable {
    let code: Int
    let msg: String?
    let data: T?
}

struct UserInfo: Decodable {
    let name: String?
    let openID: String?

    enum CodingKeys: String, CodingKey {
        case name
        case openID = "open_id"
    }
}

struct PrimaryCalendarData: Decodable {
    let calendars: [CalendarInfo]
}

struct CalendarInfo: Decodable {
    let calendarID: String?
    let type: String?
    let role: String?

    enum CodingKeys: String, CodingKey {
        case calendarID = "calendar_id"
        case type
        case role
    }
}

struct EventData: Decodable {
    let event: EventInfo
}

struct EventInfo: Decodable {
    let eventID: String?

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
    }
}

struct EventTime: Encodable {
    let timestamp: String
    let timezone: String
}

struct EventReminder: Encodable {
    let minutes: Int
}

struct CreateEventBody: Encodable {
    let summary: String
    let description: String
    let startTime: EventTime
    let endTime: EventTime
    let reminders: [EventReminder]
    let needNotification: Bool
    let freeBusyStatus: String

    enum CodingKeys: String, CodingKey {
        case summary
        case description
        case startTime = "start_time"
        case endTime = "end_time"
        case reminders
        case needNotification = "need_notification"
        case freeBusyStatus = "free_busy_status"
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
