#!/bin/sh
# Builds the Windows installer, build/release/utubmp3-setup.exe, from macOS:
#   - the Go helper (windows/helper) as a windowless utubmp3.exe with icon and version info
#   - a minimal ffmpeg.exe (scripts/build-ffmpeg.sh) and QuickJS-NG's qjs.exe
#   - the Chrome extension folder (scripts/build-chrome.sh), for "Load unpacked"
# yt-dlp.exe is not bundled: the helper downloads it on first use and keeps it updated.
#
# Needs: brew install go mingw-w64 makensis
# Usage: ./windows/build.sh
set -eu

QJS_VERSION="v0.17.0"
CROSS="x86_64-w64-mingw32"

cd "$(dirname "$0")/.."
VERSION="$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' utubmp3.xcodeproj/project.pbxproj | head -1)"
BIN="windows/bin"
STAGE="build/windows"
OUT="build/release"
mkdir -p "$BIN" "$OUT"
rm -rf "$STAGE" && mkdir -p "$STAGE"

[ -f "$BIN/ffmpeg.exe" ] || TARGET=windows ./scripts/build-ffmpeg.sh
[ -f "$BIN/qjs.exe" ] || curl -fsSL \
    "https://github.com/quickjs-ng/quickjs/releases/download/$QJS_VERSION/qjs-windows-x86_64.exe" -o "$BIN/qjs.exe"

# Helper: icon + version resource, then a GUI-subsystem build so no console window appears.
major="${VERSION%%.*}"; minor="${VERSION#*.}"; minor="${minor%%.*}"
"$CROSS-windres" -I windows/helper \
    -DVERSION_COMMA="$major,$minor,0,0" -DVERSION_STR="\\\"$VERSION\\\"" \
    -O coff -o windows/helper/rsrc_windows_amd64.syso windows/helper/resource.rc
(cd windows/helper && GOOS=windows GOARCH=amd64 CGO_ENABLED=0 \
    go build -trimpath -ldflags "-s -w -H windowsgui" -o "../../$STAGE/utubmp3.exe" .)
rm -f windows/helper/rsrc_windows_amd64.syso

cp "$BIN/ffmpeg.exe" "$BIN/qjs.exe" "$STAGE/"
./scripts/build-chrome.sh >/dev/null
cp -R build/chrome/utubmp3 "$STAGE/extension"

makensis -V2 -INPUTCHARSET UTF8 -DVERSION="$VERSION" -DSTAGE="$(pwd)/$STAGE" \
    -DOUTFILE="$(pwd)/$OUT/utubmp3-setup.exe" windows/installer.nsi
ls -lh "$OUT/utubmp3-setup.exe"
