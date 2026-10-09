#!/bin/sh
# Downloads the tools bundled inside utubmp3.app into utubmp3/Resources/bin:
#   ffmpeg — minimal universal LGPL build, compiled by scripts/build-ffmpeg.sh
#   qjs    — QuickJS-NG, the JS runtime yt-dlp uses for YouTube's challenges
# yt-dlp itself is not bundled: the app downloads and self-updates it at runtime.
# Run once before building in Xcode.
set -eu

QJS_VERSION="v0.17.0"
cd "$(dirname "$0")/.."
OUT="utubmp3/Resources/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

./scripts/build-ffmpeg.sh

for arch in arm64 x86_64; do
    echo "qjs ($arch)…"
    curl -fsSL "https://github.com/quickjs-ng/quickjs/releases/download/$QJS_VERSION/qjs-darwin-$arch" -o "$TMP/qjs-$arch"
done
lipo -create "$TMP/qjs-arm64" "$TMP/qjs-x86_64" -output "$OUT/qjs"

chmod +x "$OUT/qjs"
codesign --force --sign - "$OUT/qjs" 2>/dev/null || true
echo "qjs: $(lipo -archs "$OUT/qjs")"
