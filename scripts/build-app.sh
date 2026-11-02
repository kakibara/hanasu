#!/usr/bin/env bash
# swift build → build/Hanasu.app を組み立てて署名する。
#   ./scripts/build-app.sh            リリースビルド
#   ./scripts/build-app.sh debug      デバッグビルド
#   SIGN_IDENTITY="Apple Development: ..." ./scripts/build-app.sh   証明書で署名
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="build/Hanasu.app"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Hanasu"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Hanasu"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# 署名: 指定がなければキーチェーンの開発用証明書、それもなければアドホック
IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')"
fi
if [[ -n "$IDENTITY" ]]; then
  codesign --force --options runtime --entitlements Resources/Hanasu.entitlements --sign "$IDENTITY" "$APP"
elif security find-identity -p codesigning 2>/dev/null | grep -q '"Hanasu Local Signing"'; then
  # scripts/create-signing-cert.sh で作った自己署名証明書。署名が毎回同じになり、権限が保たれる
  codesign --force --entitlements Resources/Hanasu.entitlements --sign "Hanasu Local Signing" "$APP"
else
  echo "note: 署名用の証明書がないためアドホック署名します（再ビルドするとアクセシビリティ権限の付け直しが必要です）"
  echo "      ./scripts/create-signing-cert.sh を一度実行すると、再ビルドしても権限が保たれます"
  codesign --force --sign - "$APP"
fi

echo "built: $APP"
