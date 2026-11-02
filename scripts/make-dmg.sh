#!/usr/bin/env bash
# build/Hanasu.app から配布用のディスクイメージ build/Hanasu-<バージョン>.dmg を作る。
#   ./scripts/build-app.sh && ./scripts/make-dmg.sh
# 開くと Hanasu.app と「アプリケーション」フォルダへのリンクが並び、ドラッグでインストールできる。
# SIGN_IDENTITY があれば dmg にも署名する（改ざんの検出用。Gatekeeper の扱いは変わらない）。
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Hanasu.app"
VERSION="$(tr -d '[:space:]' < VERSION)"
DMG="build/Hanasu-${VERSION}.dmg"

[[ -d "$APP" ]] || { echo "error: $APP がありません。先に ./scripts/build-app.sh を実行してください" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Hanasu.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
# ULFO（LZFSE 圧縮）は macOS 10.11 以降で開ける。Hanasu は macOS 26 以降なので問題ない
hdiutil create -volname "Hanasu ${VERSION}" -srcfolder "$STAGE" -fs HFS+ -format ULFO -ov "$DMG" > /dev/null

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" "$DMG"
fi
hdiutil verify -quiet "$DMG"
echo "built: $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
