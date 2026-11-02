#!/usr/bin/env bash
# GitHub Actions 用: Secrets の署名証明書（PKCS#12）を一時キーチェーンに読み込む。
#   SIGNING_CERT_P12      base64 にした .p12
#   SIGNING_CERT_PASSWORD .p12 のパスワード
set -euo pipefail

: "${SIGNING_CERT_P12:?}"
: "${SIGNING_CERT_PASSWORD:?}"
TMP="${RUNNER_TEMP:-$(mktemp -d)}"
KEYCHAIN="$TMP/hanasu-signing.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -hex 16)"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

printf '%s' "$SIGNING_CERT_P12" | base64 --decode > "$TMP/signing.p12"
security import "$TMP/signing.p12" -k "$KEYCHAIN" -P "$SIGNING_CERT_PASSWORD" -T /usr/bin/codesign
rm -f "$TMP/signing.p12"
# codesign がパスワードの確認なしで鍵を使えるようにする
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" > /dev/null
# 既存の検索リストの先頭に加える
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')

security find-identity -p codesigning "$KEYCHAIN"
