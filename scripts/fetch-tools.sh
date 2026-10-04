#!/bin/sh
# Downloads the tools bundled inside utubmp3.app into utubmp3/Resources/bin:
#   ffmpeg — universal static build from https://ffmpeg.martin-riedl.de
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

for arch in arm64 amd64; do
    echo "ffmpeg ($arch)…"
    curl -fsSL "https://ffmpeg.martin-riedl.de/redirect/latest/macos/$arch/release/ffmpeg.zip" -o "$TMP/ffmpeg-$arch.zip"
    unzip -q -o "$TMP/ffmpeg-$arch.zip" -d "$TMP/ffmpeg-$arch"
done
lipo -create "$TMP/ffmpeg-arm64/ffmpeg" "$TMP/ffmpeg-amd64/ffmpeg" -output "$OUT/ffmpeg"

for arch in arm64 x86_64; do
    echo "qjs ($arch)…"
    curl -fsSL "https://github.com/quickjs-ng/quickjs/releases/download/$QJS_VERSION/qjs-darwin-$arch" -o "$TMP/qjs-$arch"
done
lipo -create "$TMP/qjs-arm64" "$TMP/qjs-x86_64" -output "$OUT/qjs"

chmod +x "$OUT/ffmpeg" "$OUT/qjs"
codesign --force --sign - "$OUT/ffmpeg" "$OUT/qjs" 2>/dev/null || true
"$OUT/ffmpeg" -version | head -1
echo "qjs: $(lipo -archs "$OUT/qjs")"
