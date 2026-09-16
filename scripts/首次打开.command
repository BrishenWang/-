#!/bin/bash
# 采购管家（ProcurementTracker）首次打开辅助脚本
# 作用：云端编译的 App 没有 Mac App Store 签名，本脚本解除下载隔离标记、
#       拷贝到“应用程序”文件夹并启动。以后可直接从启动台打开。

cd "$(dirname "$0")"
DIR="$(pwd)"
APP="$DIR/ProcurementTracker.app"

echo "-----------------------------------------------"
echo "  采购管家 · 首次打开"
echo "-----------------------------------------------"

if [ ! -d "$APP" ]; then
  echo ""
  echo "未在同一文件夹找到 ProcurementTracker.app。"
  echo "请先把 ProcurementTracker-App.zip 解压，并确保本脚本与 ProcurementTracker.app 放在同一个文件夹后再运行。"
  echo ""
  read -n 1 -s -r -p "按任意键关闭窗口..."
  exit 1
fi

echo "正在解除 macOS 安全隔离标记..."
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

if [ ! -d "/Applications/ProcurementTracker.app" ]; then
  echo "正在复制到“应用程序”文件夹..."
  cp -R "$APP" /Applications/
else
  echo "“应用程序”中已存在，将替换为本次下载的版本..."
  rm -rf /Applications/ProcurementTracker.app
  cp -R "$APP" /Applications/
fi

xattr -dr com.apple.quarantine /Applications/ProcurementTracker.app 2>/dev/null || true

echo "正在启动采购管家..."
open /Applications/ProcurementTracker.app

sleep 2
echo "完成。以后可以从启动台（Launchpad）或“应用程序”文件夹打开“采购管家”。"
sleep 1
exit 0
