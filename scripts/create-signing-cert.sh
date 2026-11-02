#!/usr/bin/env bash
# ローカル署名用の自己署名証明書「Hanasu Local Signing」をログインキーチェーンに作る（初回だけ実行）。
# アドホック署名はビルドごとに署名が変わり、アクセシビリティ等の許可が外れてしまう。
# 同じ証明書で署名し続ければ、再ビルドしても許可が保たれる。
# 証明書を信頼済みにする必要はない（システムの信頼設定は変えない）。
set -euo pipefail

NAME="Hanasu Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
  echo "既にあります: $NAME"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem"
PASS="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$NAME" -out "$WORK/identity.p12" -passout "pass:$PASS"

# codesign だけが鍵を使えるようにする
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign

echo "作成しました: $NAME"
