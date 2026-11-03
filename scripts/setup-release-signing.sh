#!/usr/bin/env bash
# リリース用の自己署名証明書「Hanasu Release Signing」を作り、GitHub Actions の Secrets に登録する（初回だけ）。
# すべてのリリースを同じ証明書で署名するので、利用者がアップデートしても
# アクセシビリティなどの許可が外れない。鍵はこの Mac のキーチェーンには入れず、Secrets にだけ置く。
#   必要なもの: gh（対象リポジトリへの書き込み権限）
# 要件: REQ-REL-002
set -euo pipefail

REPO="${1:-kakibara/hanasu}"
NAME="Hanasu Release Signing"

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
  -name "$NAME" -out "$WORK/signing.p12" -passout "pass:$PASS"

base64 -i "$WORK/signing.p12" | gh secret set MACOS_SIGNING_CERT_P12 --repo "$REPO"
printf '%s' "$PASS" | gh secret set MACOS_SIGNING_CERT_PASSWORD --repo "$REPO"

echo "登録しました: $REPO の MACOS_SIGNING_CERT_P12 / MACOS_SIGNING_CERT_PASSWORD（$NAME）"
