#!/bin/bash
# 编译并拼装 速填.app（产物在 build/）
#   ./build.sh           只打包
#   ./build.sh install   打包后装到 ~/Applications 并重启（自启开着就保持开着）
# 跑过 sign-setup.sh 就用本机证书签名（重编译不用重新授权辅助功能），否则退回 ad-hoc。
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="速填.app"
EXE="QuickInput"
LABEL="com.jiezaichan.quickinput"   # = Info.plist 的 CFBundleIdentifier = LoginItem.label
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

autostart=0
if [ -f "$AGENTS/$LABEL.plist" ] || [ -f "$AGENTS/$OLD_LABEL.plist" ]; then autostart=1; fi

launchctl bootout "$DOMAIN/$OLD_LABEL" 2>/dev/null || true
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
rm -f "$AGENTS/$OLD_LABEL.plist"
pkill -x "$OLD_EXE" 2>/dev/null || true
pkill -x "$EXE" 2>/dev/null || true
sleep 0.5

mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
echo "已安装到 $DEST"

if [ "$autostart" = 1 ]; then
	# 与 LoginItem.set(true) 写出的内容一致
	mkdir -p "$AGENTS"
	cat > "$AGENTS/$LABEL.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>KeepAlive</key>
	<false/>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProcessType</key>
	<string>Interactive</string>
	<key>ProgramArguments</key>
	<array>
		<string>$DEST/Contents/MacOS/$EXE</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
EOF
	launchctl bootstrap "$DOMAIN" "$AGENTS/$LABEL.plist"
	echo "开机自启：已开启（${LABEL}）"
else
	open "$DEST"
fi
