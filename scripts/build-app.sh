#!/usr/bin/env bash
# swift build → build/Hanasu.app を組み立てて署名する。
#   ./scripts/build-app.sh            リリースビルド
#   ./scripts/build-app.sh debug      デバッグビルド
#   SIGN_IDENTITY="Apple Development: ..." ./scripts/build-app.sh   証明書を指定して署名
# バージョンは VERSION（tagpr が更新する）から Info.plist に書き込む。
# 設計判断: DEC-COM-015, DEC-REL-007, DEC-COM-051
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
# 要件: REQ-REL-005
cp LICENSE NOTICE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
# 要件: REQ-COM-030
# 設計判断: DEC-COM-061
# ローカルの LLM を動かす llama-server（llama.cpp）。SHA-256 を確かめてから入れる（ライセンスは llama/LICENSE）
./scripts/fetch-llama-cpp.sh
mkdir -p "$APP/Contents/Resources/llama"
cp -P build/llama-cpp/macos-arm64/* "$APP/Contents/Resources/llama/"

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
# 設計判断: DEC-COM-061
# 同梱した llama-server と dylib を、本体と同じ証明書で署名し直す（ライブラリから順に。シンボリックリンクは飛ばす）
sign_llama() {
  local llama="$APP/Contents/Resources/llama"
  for file in "$llama"/*.dylib "$llama/llama-server"; do
    [[ -L "$file" ]] && continue
    codesign --force "$@" "$file"
  done
}
if [[ "$IDENTITY" == *"Apple Development"* || "$IDENTITY" == *"Developer ID"* ]]; then
  sign_llama --options runtime --sign "$IDENTITY"
elif [[ -n "$IDENTITY" ]]; then
  # 自己署名には Team ID がないので、Hardened Runtime のライブラリの検証で同梱の dylib を読めない。llama-server だけ検証を外す
  sign_llama --options runtime --sign "$IDENTITY"
  codesign --force --options runtime --entitlements Resources/llama-server.entitlements --sign "$IDENTITY" \
    "$APP/Contents/Resources/llama/llama-server"
else
  sign_llama --sign -
fi
if [[ "$IDENTITY" == *"Apple Development"* || "$IDENTITY" == *"Developer ID"* ]]; then
  # Apple の証明書なら Hardened Runtime を付ける（公証に必要）
  codesign --force --options runtime --entitlements Resources/Hanasu.entitlements --sign "$IDENTITY" "$APP"
elif [[ -n "$IDENTITY" ]]; then
  # 要件: REQ-COM-022
  # 設計判断: DEC-COM-051
  # 自己署名でも Hardened Runtime を付ける。ほかのプログラムが DYLD_INSERT_LIBRARIES などで Hanasu にコードを差し込み、
  # Hanasu として（キーチェーンの確認なしに）API キーを読むのを防ぐため。entitlements はマイクとリマインダーだけ
  codesign --force --options runtime --entitlements Resources/Hanasu.entitlements --sign "$IDENTITY" "$APP"
else
  echo "note: 署名用の証明書がないためアドホック署名します（再ビルドするとアクセシビリティ権限の付け直しが必要です）"
  echo "      ./scripts/create-signing-cert.sh を一度実行すると、再ビルドしても権限が保たれます"
  codesign --force --sign - "$APP"
fi

echo "built: $APP ($VERSION, build $BUILD_NUMBER, ${IDENTITY:-ad-hoc})"
