#!/usr/bin/env bash
# 同梱する llama.cpp（llama-server）を取ってきて、SHA-256 を確かめてから必要なファイルだけを並べる。
#   ./scripts/fetch-llama-cpp.sh            → build/llama-cpp/macos-arm64/（llama-server と、それが読む dylib・LICENSE）
# 版とハッシュは scripts/llama-cpp.lock。取ったものは build/llama-cpp/cache に置き、ハッシュが合えば取り直さない。
# Windows の分は .github/workflows（tagpr.yml・windows.yml）の publish で、同じ lock を読んで入れる。
# 設計判断: DEC-COM-061
set -euo pipefail

cd "$(dirname "$0")/.."
lock_value() { grep "^$1=" scripts/llama-cpp.lock | cut -d= -f2-; }
VERSION="$(lock_value version)"
ASSET="$(lock_value macos_asset)"
SHA256="$(lock_value macos_sha256)"
CACHE="build/llama-cpp/cache"
OUT="build/llama-cpp/macos-arm64"
mkdir -p "$CACHE"

ARCHIVE="$CACHE/$ASSET"
if [[ ! -f "$ARCHIVE" ]] || [[ "$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')" != "$SHA256" ]]; then
  echo "llama.cpp $VERSION を取ってきます: $ASSET"
  curl -fsSL --proto '=https' --tlsv1.2 -o "$ARCHIVE.download" \
    "https://github.com/ggml-org/llama.cpp/releases/download/$VERSION/$ASSET"
  mv "$ARCHIVE.download" "$ARCHIVE"
fi
ACTUAL="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [[ "$ACTUAL" != "$SHA256" ]]; then
  rm -f "$ARCHIVE"
  echo "error: $ASSET の SHA-256 が想定と違います（$ACTUAL）" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
tar -xzf "$ARCHIVE" -C "$TMP"
SRC="$TMP/llama-$VERSION"
rm -rf "$OUT"
mkdir -p "$OUT"
# llama-server と、@loader_path で読むライブラリ（版の付いた実体と .0 のシンボリックリンク）だけ。ほかの道具は入れない
cp "$SRC/llama-server" "$SRC/libllama-server-impl.dylib" "$SRC/LICENSE" "$OUT/"
for lib in libllama libllama-common libmtmd libggml libggml-base libggml-cpu libggml-metal libggml-blas libggml-rpc; do
  cp -P "$SRC/$lib".0.*dylib "$SRC/$lib".0.dylib "$OUT/"
done
echo "llama.cpp $VERSION: $OUT"
