#!/bin/bash
# 一次性：生成本机专用的自签名代码签名证书，build.sh 以后都用它签名。
#
# 为什么：ad-hoc 签名没有身份，系统按二进制哈希认人，每次重新编译都要重新授权辅助功能。
# 用固定证书签名后，指定要求变成「identifier + 证书叶子哈希」，重编译不变，授权一次永久有效。
#
# 证书放在独立钥匙串 ~/.quickinput-signing/（不进搜索列表、不碰登录钥匙串），
# 钥匙串密码随机生成存在同目录，build.sh 用它非交互解锁。证书不需要被信任，codesign 照样能签。
set -euo pipefail

DIR="$HOME/.quickinput-signing"
KC="$DIR/signing.keychain-db"
NAME="QuickInput Local Signing"

if [ -f "$KC" ]; then
	echo "已存在：${KC}（要重建先删掉整个 ${DIR}；重建后需重新授权一次辅助功能）"
	exit 0
fi

mkdir -p "$DIR"
chmod 700 "$DIR"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/req.cnf" <<EOF
[req]
distinguished_name=dn
x509_extensions=v3
prompt=no
[dn]
CN=$NAME
[v3]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
EOF
# 用系统自带的 LibreSSL；PEM 分开导入，避开新版 OpenSSL 的 p12 加密算法 security 不认的问题
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 7300 \
	-keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/req.cnf" 2>/dev/null

PW=$(/usr/bin/openssl rand -hex 24)
printf '%s' "$PW" > "$DIR/password"
chmod 600 "$DIR/password"

security create-keychain -p "$PW" "$KC"
security set-keychain-settings "$KC"   # 不自动上锁
security unlock-keychain -p "$PW" "$KC"
security import "$TMP/key.pem" -k "$KC" -T /usr/bin/codesign >/dev/null
security import "$TMP/cert.pem" -k "$KC" >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$PW" "$KC" >/dev/null

echo "已生成签名证书「${NAME}」：${KC}"
echo "接下来 ./build.sh install；从 ad-hoc 换到证书签名后需要最后再授权一次辅助功能"
