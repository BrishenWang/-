# 采购管家（ProcurementTracker）

面向采购人的原生 App，**同一个 Xcode 工程可同时构建 iPhone 版（iOS 17+）和 Mac 版（macOS 14+）**。

## 功能一览

- **新增 / 管理采购需求**：物品名称、供应商、联系人、数量、单价、币种、下单日期、预计 / 实际大货到货日期、到货 / 发票 / 付款状态、备注。
- **自动提醒（三类内置规则 + 自定义）**：
  - 大货到货**提前 N 天预告**（默认 3 天）；
  - **到货当天**提醒验收；
  - 到货后 **N 天自动催开发票**（默认 7 天，已开票后自动取消）；
  - 可再加一条自定义跟进提醒。
- **三个提醒渠道，可按每条采购单独开关**：
  1. **飞书日历**：OAuth 授权后自动在你的飞书主日历创建带提前 30 分钟提醒的日程，飞书客户端 / 手机 / 电脑全设备推送；
  2. **系统日历**：写入 iPhone / Mac 自带“日历”App，登录同一 Apple ID 并开启 iCloud 日历后自动跨设备同步；
  3. **本机通知**：离线也能弹通知，无需任何配置。
- **待办概览**：逾期 / 今日待办、未来 7 天日程、进行中采购数、待到货、待收票、本月采购额。
- **数据备份**：一键导出 / 导入 JSON，方便在 Mac 与 iPhone 之间迁移。
- 数据默认使用 SwiftData 保存在本机，无需注册任何账号即可使用（飞书同步为可选功能）。

---

## 一、环境要求

- 一台 **Mac**，系统 **macOS 14（Sonoma）或更高**；
- **Xcode 16 或更高**（Mac App Store 免费下载）；
- 手机端要求 **iOS 17 或更高**。

> 本工程为 SwiftUI 原生项目，不能在 Windows 上编译；也不需要 CocoaPods 等第三方依赖，解压后直接用 Xcode 打开即可。

## 二、在 Mac 上运行

1. 解压本压缩包，双击打开 `ProcurementTracker/ProcurementTracker.xcodeproj`。
2. 在 Xcode 左侧文件导航器选中最顶部的 **ProcurementTracker** 工程 → 中间选择 **ProcurementTracker** target → **Signing & Capabilities** 标签页：
   - 将 **Bundle Identifier** 从 `com.yourname.procurementtracker` 改成你自己的，例如 `com.你的名字.procurementtracker`；
   - 在 **Team** 下拉框选择你的 Apple ID（没有就点 `Add an Account…`，用普通 Apple ID 免费登录即可）。
3. Xcode 顶部的运行目标选择 **My Mac**，按 `Cmd + R`（或左上角运行按钮），即可在 Mac 上编译启动。
4. 首次启动若提示允许通知 / 访问日历，请点允许；也可以稍后在 App 的“设置”页里逐项授权。

## 三、在 iPhone 上运行

1. 用数据线把 iPhone 连接到 Mac（首次连接在手机上点“信任此电脑”）。
2. Xcode 顶部运行目标选择你的 **iPhone**，按 `Cmd + R`。
3. 首次运行会因“开发者不受信任”无法打开：在 iPhone 上进入 **设置 → 通用 → VPN与设备管理**，选中你的 Apple ID，点“信任”，再回到桌面打开 App。
4. **免费 Apple ID 的限制**：装到 iPhone 上的签名 **7 天后失效**，到期后重新连电脑用 Xcode 再运行一次即可；Mac 端没有此限制。若加入付费的 Apple Developer Program（688 元/年）则无此限制，也才能使用下文的 iCloud(CloudKit) 同步与 TestFlight 分发。

> Mac 版与 iPhone 版是同一个工程、同一份代码，Xcode 会根据所选目标自动编译对应平台版本。

---

## 四、配置飞书自建应用（仅“飞书日历同步”需要）

飞书日历同步走官方开放平台 OAuth 授权，需要你（或企业管理员）创建一个**企业自建应用**。用**电脑浏览器**操作：

1. 打开飞书开放平台 **open.feishu.cn/app**（国际版 Lark 用 **open.larksuite.com**），登录企业账号，点击 **创建企业自建应用**，填写名称（如“采购管家”）。
2. 进入应用的 **权限管理**，搜索并开通以下权限：
   - **更新日历及日程信息**（权限标识 `calendar:calendar`，包含读写日程）；
   - **离线访问已授权数据**（权限标识 `offline_access`，用于授权过期后自动续期，不用反复登录）。
3. 进入 **安全设置 → 重定向 URL**，添加下面这个地址并保存：

   ```
   procurement-tracker://oauth/callback
   ```

   - 该地址对应 App 已注册的回调协议，授权完成后浏览器会自动跳回 App，页面本身无需真实存在。
   - **如果飞书后台不接受自定义协议地址**（个别企业限制为 http/https）：改成一个你自己的 HTTPS 网址（例如你公司官网任意页面地址，甚至 `https://example.com/callback` 都可以，App 会在跳转瞬间拦截，页面不需要真的存在），然后在 App 的 **设置 → 重定向地址 Redirect URI** 中填写**完全相同**的网址即可。
4. 进入 **版本管理与发布 → 创建版本**，填写版本号后提交发布；企业自建应用通常需要**企业管理员审核通过**后才能授权。
5. 在应用的 **凭证与基础信息** 页，复制 **App ID**（`cli_` 开头）和 **App Secret**。

## 五、在 App 中登录飞书

1. 打开 App → **设置** 页：
   - 飞书站点选“飞书（国内版）”或“Lark（国际版）”；
   - 填入 **App ID**、**App Secret**；重定向地址默认 `procurement-tracker://oauth/callback`（若上一步用了 HTTPS 兜底地址，在此改成同一个）。
2. 点 **登录飞书并授权日历**，在弹出的飞书授权页同意授权。
3. 登录成功后，现有采购需求的提醒会自动同步到飞书日历；以后每次新增 / 修改采购也会自动创建、更新或删除对应日程。
4. App Secret 与登录令牌保存在系统**钥匙串（Keychain）**中，不会上传到除飞书官方之外的任何服务器。

---

## 六、日常使用

1. 点右上角 **“+ 新增采购”**，填写物品、供应商、预计大货到货日期等；在“提醒规则”里调整提前几天预告、到货后几天催票；在“提醒渠道”里勾选飞书日历 / 系统日历 / 本机通知，保存即可。
2. **待办概览**页集中看到期与逾期事项；左滑（iPhone）或使用详情页快捷按钮可**标记已到货 / 已开票 / 归档 / 删除**。
3. 标记已到货后，到货类提醒自动取消、催票提醒自动按“到货后 N 天”排期；标记已开票后催票提醒自动消失；删除采购时三个渠道的提醒 / 日程会一并撤销。
4. 若某条提醒同步失败（例如当时没网），详情页对应渠道图标会显示红色叉号和原因，点 **重新同步提醒** 即可补建。
5. 默认提醒时刻、提前天数、默认渠道可在 **设置 → 新建采购的默认设置** 中统一调整。

## 七、Mac 与 iPhone 之间数据如何互通

- **提醒层面（推荐，零配置）**：飞书日历是云端的，两端登录同一飞书账号即可看到同一批日程；系统日历登录同一 Apple ID 并开启 iCloud 日历也会自动同步。
- **采购数据层面**：App 内的采购清单默认只存本机。两种互通方式：
  - **手动迁移**：设置 → 导出 JSON（可 AirDrop / 微信 / iCloud 盘传到另一台设备）→ 在另一台设备导入；
  - **iCloud 自动同步（可选，需付费开发者账号）**：见下文第九节。

## 八、常见问题

- **授权时报“重定向地址不匹配 / error=redirect_uri_mismatch”**：飞书后台配置的重定向 URL 与 App 设置里的 Redirect URI 必须**逐字符一致**（含 `://`、路径、大小写）；自建应用记得已**发布版本并审核通过**。
- **接口返回权限错误（如 99991679 / 1254 等）**：检查权限 `calendar:calendar`、`offline_access` 是否已开通，且开通后**重新发布了版本**；之后在 App 里退出登录重新授权一次。
- **系统日历写不进去**：Mac 在 **系统设置 → 隐私与安全性 → 日历**、iPhone 在 **设置 → … → 日历** 中确认 App 有权限；且系统“日历”App 中至少有一个可写入的默认日历。
- **收不到本机通知**：Mac 在 **系统设置 → 通知**、iPhone 在 **设置 → 通知** 中允许 App 通知；注意勿扰 / 专注模式会拦截。
- **免费账号安装的 iPhone 版过几天打不开**：签名 7 天过期，重新连电脑在 Xcode 运行一次即可。

## 九、可选：开启 iCloud（CloudKit）自动多设备同步

默认未开启，以保证免费 Apple ID 也能直接编译。需要 Mac 与 iPhone 的采购数据实时自动同步时：

1. 需付费 Apple Developer Program 账号，在 Xcode **Signing & Capabilities** 中确认 Bundle Identifier 唯一。
2. 点 **+ Capability → iCloud**，勾选 **CloudKit**，点 “+” 新建容器，如 `iCloud.com.你的名字.procurementtracker`。
3. 再点 **+ Capability → Background Modes**，勾选 **Remote notifications**。
4. 打开 `ProcurementTracker/ProcurementTrackerApp.swift`，将

   ```swift
   let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
   ```

   替换为

   ```swift
   let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
   ```

5. 重新编译运行；两端登录同一 Apple ID、iCloud 空间充足时数据会自动同步（首条数据同步可能有几分钟延迟）。

## 十、安全说明与项目结构

- 本 App 为**内部工具形态**：飞书 App Secret 保存在本机钥匙串，由客户端直接向飞书换取令牌。个人 / 小团队内部使用可以接受；若将来上架公开分发，应增加一个自己的后端服务保管 Secret、由后端代理令牌交换。
- 工程为纯原生 SwiftUI + SwiftData，无第三方依赖：

  ```
  ProcurementTracker/
  ├── ProcurementTracker.xcodeproj/     # Xcode 工程（iOS + macOS 多平台单 target）
  └── ProcurementTracker/
      ├── ProcurementTrackerApp.swift   # App 入口、数据容器装配
      ├── Info.plist / .entitlements    # 回调协议、日历用途说明、沙盒与网络权限
      ├── Assets.xcassets/              # App 图标、主题色
      ├── Models/                       # PurchaseItem、ReminderEvent 数据模型与枚举
      ├── Services/                     # 飞书 OAuth/日历 API、通知、系统日历、
      │                                 #   提醒调度引擎、设置与 JSON 备份
      └── Views/                        # 概览 / 列表 / 编辑 / 详情 / 设置界面
  ```

## 关于编译验证的说明

本工程的 19 个 Swift 源文件、工程文件、Info.plist、entitlements 与资源目录均已通过逐文件跨平台人工审查和工程结构完整性校验（对象引用、括号配平、配置键齐全）。由于交付环境为 Linux、无法运行 Xcode，**尚未在 Xcode 中做实际编译**。首次在 Xcode 构建时如出现任何报错，把报错信息（Issue Navigator 里的红色条目，可截图或复制文字）发回，即可快速修正。
