#!/bin/bash
# 编译并拼装 速填.app（产物在 build/）
#   ./build.sh           只打包
#   ./build.sh install   打包后装到 ~/Applications 并重启（开机自启走系统登录项，重装不受影响）
# 跑过 sign-setup.sh 就用本机证书签名（重编译不用重新授权辅助功能），否则退回 ad-hoc。
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="速填.app"
EXE="QuickInput"
LABEL="com.jiezaichan.quickinput"   # = Info.plist 的 CFBundleIdentifier；1.1 的 LaunchAgent 也用它，安装时迁走
OLD_LABEL="com.jiezaichan.sutian"   # 1.0 的标识，安装时迁走
OLD_EXE="sutian"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/$EXE"

APP="build/$APP_NAME"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/$EXE"
SIGN_DIR="$HOME/.quickinput-signing"
if [ -f "$SIGN_DIR/signing.keychain-db" ]; then
	security unlock-keychain -p "$(cat "$SIGN_DIR/password")" "$SIGN_DIR/signing.keychain-db"
	codesign --force --keychain "$SIGN_DIR/signing.keychain-db" --sign "QuickInput Local Signing" "$APP"
	echo "已生成 ${APP}（证书签名）"
else
	codesign --force --sign - "$APP"
	echo "已生成 ${APP}（ad-hoc 签名：每次重装都要重新授权辅助功能，跑一次 ./sign-setup.sh 可免）"
fi

[ "${1:-}" = "install" ] || exit 0

DEST="$HOME/Applications/$APP_NAME"
AGENTS="$HOME/Library/LaunchAgents"
DOMAIN="gui/$(id -u)"

# 旧版靠 LaunchAgent plist 自启：删掉 plist，启动时让 App 自己注册成系统登录项
migrate=0
if [ -f "$AGENTS/$LABEL.plist" ] || [ -f "$AGENTS/$OLD_LABEL.plist" ]; then migrate=1; fi

launchctl bootout "$DOMAIN/$OLD_LABEL" 2>/dev/null || true
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
rm -f "$AGENTS/$OLD_LABEL.plist" "$AGENTS/$LABEL.plist"
pkill -x "$OLD_EXE" 2>/dev/null || true
pkill -x "$EXE" 2>/dev/null || true
sleep 0.5

mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
echo "已安装到 $DEST"

if [ "$migrate" = 1 ]; then
	open "$DEST" --args --register-login-item
	echo "开机自启：已从 LaunchAgent 迁到系统登录项"
else
	open "$DEST"
fi
