#!/usr/bin/env bash
# swift build → build/Hanasu.app を組み立てて署名する。
#   ./scripts/build-app.sh            リリースビルド
#   ./scripts/build-app.sh debug      デバッグビルド
#   SIGN_IDENTITY="Apple Development: ..." ./scripts/build-app.sh   証明書を指定して署名
# バージョンは VERSION（tagpr が更新する）から Info.plist に書き込む。
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
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

# 署名: 指定 → キーチェーンの Apple の開発用証明書 → ローカル用の自己署名証明書 → アドホック
IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')"
fi
if [[ -z "$IDENTITY" ]] && security find-identity -p codesigning 2>/dev/null | grep -q '"Hanasu Local Signing"'; then
  # scripts/create-signing-cert.sh で作った自己署名証明書。署名が毎回同じになり、権限が保たれる
  IDENTITY="Hanasu Local Signing"
fi
if [[ "$IDENTITY" == *"Apple Development"* || "$IDENTITY" == *"Developer ID"* ]]; then
  # Apple の証明書なら Hardened Runtime を付ける（公証に必要）
  codesign --force --options runtime --entitlements Resources/Hanasu.entitlements --sign "$IDENTITY" "$APP"
elif [[ -n "$IDENTITY" ]]; then
  codesign --force --entitlements Resources/Hanasu.entitlements --sign "$IDENTITY" "$APP"
else
  echo "note: 署名用の証明書がないためアドホック署名します（再ビルドするとアクセシビリティ権限の付け直しが必要です）"
  echo "      ./scripts/create-signing-cert.sh を一度実行すると、再ビルドしても権限が保たれます"
  codesign --force --sign - "$APP"
fi

echo "built: $APP ($VERSION, build $BUILD_NUMBER, ${IDENTITY:-ad-hoc})"
