#!/bin/sh
# Packages the extension for Chrome (and other Chromium browsers) as
# build/release/utubmp3-chrome.zip, to install with "Load unpacked".
# It uses the same scripts as the Safari extension and the same background
# helper, so the utubmp3 Mac app must be installed and opened once.
# The Chrome Web Store doesn't allow YouTube downloaders, so this is sideloaded.
set -eu

cd "$(dirname "$0")/.."
SRC="utubmp3 Extension/Resources"
OUT="build/release"
STAGE="build/chrome/utubmp3"
rm -rf "$STAGE"
mkdir -p "$STAGE" "$OUT"

cp -R "$SRC/" "$STAGE/"
rm -f "$STAGE/images/toolbar-icon.svg"  # Chrome can't use SVG toolbar icons

# Chrome MV3: a service-worker background, and PNG toolbar icons.
python3 - "$SRC/manifest.json" "$STAGE/manifest.json" <<'EOF'
import json, sys
m = json.load(open(sys.argv[1]))
m["background"] = {"service_worker": "background.js", "type": "module"}
m["action"]["default_icon"] = {"48": "images/icon-48.png", "96": "images/icon-96.png", "128": "images/icon-128.png"}
json.dump(m, open(sys.argv[2], "w"), indent=4)
EOF
ZIP="$OUT/utubmp3-chrome.zip"
rm -f "$ZIP"
(cd "$(dirname "$STAGE")" && zip -qr -X "$OLDPWD/$ZIP" "$(basename "$STAGE")" -x '*.DS_Store')
echo "Chrome extension: $ZIP"
