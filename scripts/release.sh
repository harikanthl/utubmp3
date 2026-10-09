#!/bin/sh
# Builds a Developer ID–signed, notarized, stapled utubmp3 for direct distribution
# (GitHub Releases):  build/release/utubmp3.dmg, .zip and utubmp3-chrome.zip, plus the
# source of the bundled FFmpeg (ffmpeg-<version>.tar.xz) to attach for the GPL.
# Adapted from the Operator / Kekasatori notarization scripts.
#
# Notarization credentials, either:
#   - a gitignored scripts/notarize-env.sh (or NOTARIZE_ENV=/path/to/file) exporting
#     APPLE_ID, APP_PW (app-specific password) and TEAM_ID; or
#   - an existing keychain profile: NOTARY_PROFILE=<name>
#
# Usage: ./scripts/release.sh                    # build, sign, notarize, staple, package
#        SKIP_NOTARIZE=1 ./scripts/release.sh    # build and sign only
set -eu

TEAM_ID="2F5YSX6AK6"
IDENTITY="Developer ID Application: Harikanth Lingutla ($TEAM_ID)"
PROFILE="${NOTARY_PROFILE:-utubmp3-notary}"

cd "$(dirname "$0")/.."
NOTARIZE_ENV="${NOTARIZE_ENV:-scripts/notarize-env.sh}"
# shellcheck disable=SC1090
[ -f "$NOTARIZE_ENV" ] && . "$NOTARIZE_ENV"
OUT="build/release"
rm -rf "$OUT"
mkdir -p "$OUT"

# 1. Bundled tools: Developer ID + hardened runtime + secure timestamp, as notarization requires.
[ -x utubmp3/Resources/bin/ffmpeg ] && [ -x utubmp3/Resources/bin/qjs ] || ./scripts/fetch-tools.sh
codesign --force --options runtime --timestamp --sign "$IDENTITY" \
    utubmp3/Resources/bin/ffmpeg utubmp3/Resources/bin/qjs

# FFmpeg is GPL: each release ships the exact source of the bundled version.
FFMPEG_VERSION="$(utubmp3/Resources/bin/ffmpeg -version | head -1 | sed -E 's/^ffmpeg version ([0-9.]+).*/\1/')"
FFMPEG_SRC="$OUT/ffmpeg-$FFMPEG_VERSION.tar.xz"
curl -fsSL "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" -o "$FFMPEG_SRC"

# 2. Archive and export with Developer ID signing.
xcodebuild -project utubmp3.xcodeproj -scheme utubmp3 -configuration Release \
    -archivePath "$OUT/utubmp3.xcarchive" -allowProvisioningUpdates archive | tail -1
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$OUT/utubmp3.xcarchive" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT" -allowProvisioningUpdates | tail -1

APP="$OUT/utubmp3.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
codesign --verify --deep --strict "$APP"
echo "Signed: $(codesign -dv --verbose=2 "$APP" 2>&1 | grep '^Authority=Developer ID Application')"

if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
    echo "Skipping notarization. App: $APP"
    exit 0
fi

# 3. DMG. hdiutil hits TCC "Operation not permitted" reading from ~/Desktop and
#    other protected folders, so stage the app in /tmp first.
DMG="$OUT/utubmp3.dmg"  # fixed names, so releases/latest/download/... links keep working
STAGE="$(mktemp -d /tmp/utubmp3-dmg.XXXXXX)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
# hdiutil underestimates the image size for -srcfolder and fails with "No space
# left on device" inside the image, so size it explicitly: app size + 50%.
SIZE_MB=$(( $(du -sm "$APP" | cut -f1) * 3 / 2 + 20 ))
hdiutil create -volname "utubmp3" -srcfolder "$STAGE" -size "${SIZE_MB}m" -fs HFS+ \
    -ov -format UDZO "$STAGE/out.dmg" >/dev/null
mv "$STAGE/out.dmg" "$DMG"
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

# 4. Notarize the DMG (covers the app inside), then staple both.
if [ -n "${APPLE_ID:-}" ] && [ -n "${APP_PW:-}" ]; then
    xcrun notarytool store-credentials "$PROFILE" \
        --apple-id "$APPLE_ID" --team-id "${TEAM_ID:-2F5YSX6AK6}" --password "$APP_PW" >/dev/null
fi
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose "$APP"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

ZIP="$OUT/utubmp3.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
./scripts/build-chrome.sh
echo "Release ready:"
echo "  $DMG"
echo "  $ZIP"
echo "  $OUT/utubmp3-chrome.zip"
echo "  $FFMPEG_SRC   (attach to the release: FFmpeg's GPL source)"
