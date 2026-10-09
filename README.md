# utubmp3

A Safari and Chrome extension for macOS and Windows that saves the audio of a YouTube video as an MP3, with built-in tools to clean up or edit the MP3's tags.

Install the app, open it once, turn on the extension, and you're done. No terminal, Homebrew or Python needed.

## Features

- **One-click MP3**: a **⬇ MP3** button next to Like/Share on YouTube videos (it floats in the corner on Shorts), plus a toolbar popup.
- **Best-quality audio** converted to MP3, with the video thumbnail embedded as cover art.
- **Automatic tag cleanup**: every download gets proper tags (title, singers, album/movie, composer, lyricist, label) parsed from the video's description. Hashtags, social links, URLs and the duplicated description are removed, and the file is renamed to `Title - Album.mp3`.
- **Tag editor**: the popup lists recent MP3s in your Downloads folder with **Clean** and **Edit** buttons. Edit lets you change any tag; an empty field removes it. Audio and cover art are never re-encoded.
- **Always up to date**: yt-dlp updates itself daily, so downloads keep working when YouTube changes.
- **Runs locally**: nothing leaves your computer except the download from YouTube.

## Requirements

- macOS 13 Ventura or later, Apple Silicon or Intel: Safari, or Chrome and other Chromium browsers
- Windows 10 or 11 (x64; ARM runs it under emulation): Chrome, Edge or other Chromium browsers

## Install

1. Download [`utubmp3.dmg`](https://github.com/harikanthl/utubmp3/releases/latest/download/utubmp3.dmg) from the latest release, drag `utubmp3.app` to Applications, and open it once. The app is notarized by Apple.
2. Click **Quit and Open Safari Settings…** and turn on the **utubmp3** extension. Allow it on `youtube.com` when Safari asks.
3. Open any YouTube video and click **⬇ MP3**.

MP3s are saved to `~/Downloads`. On the first download, macOS asks whether utubmp3 may access the Downloads folder; click **Allow**.

Opening the app also sets up a small background helper (see [How it works](#how-it-works)). It starts automatically at every login, and macOS may show a "Background Items Added" notification the first time.

### Chrome (on a Mac)

The same extension works in Chrome and other Chromium browsers, using the same app and helper. Google's Chrome Web Store doesn't allow YouTube downloaders, so it's installed by hand:

1. Install and open the utubmp3 app once (steps above), so the helper is running.
2. Download [`utubmp3-chrome.zip`](https://github.com/harikanthl/utubmp3/releases/latest/download/utubmp3-chrome.zip) and unzip it somewhere it can stay.
3. Open `chrome://extensions`, turn on **Developer mode**, click **Load unpacked** and pick the unzipped `utubmp3` folder.

### Windows

On Windows, a small installer sets up the background helper, and the extension is added to Chrome or Edge by hand:

1. Download [`utubmp3-setup.exe`](https://github.com/harikanthl/utubmp3/releases/latest/download/utubmp3-setup.exe) and run it. It installs for your user only, without an admin prompt. The installer isn't code-signed yet, so Windows SmartScreen may say "Windows protected your PC"; click **More info ▸ Run anyway**.
2. On the last page, leave **Open the extension folder** ticked and click **Finish**.
3. Open `chrome://extensions` (or `edge://extensions`), turn on **Developer mode**, click **Load unpacked** and pick that folder (`%LOCALAPPDATA%\Programs\utubmp3\extension`).
4. Open any YouTube video and click **⬇ MP3**. MP3s are saved to your Downloads folder.

The helper starts automatically when you sign in. Opening **utubmp3** from the Start menu starts it if it isn't running.

## Use

| Where | What to do |
|---|---|
| YouTube video page | Click **⬇ MP3**. It changes to ⏳ while converting and ✅ **Saved** when done; click ✅ to show the file in Finder (or File Explorer on Windows). Hover over ⚠️ to see the error. |
| Toolbar popup | **Download MP3** for the current video, with a **Show in Finder** (**Show in folder** on Windows) button when it finishes. |
| Popup ▸ Recent MP3s | **Clean** fixes a file's tags automatically; **Edit** opens a form with every tag. |

## Troubleshooting

| Problem | Fix |
|---|---|
| "Helper not running" in the popup | Open the utubmp3 app once; it restarts the helper. On Windows, open **utubmp3** from the Start menu. |
| "Move utubmp3 to the Applications folder" | The app was opened from the disk image or from Downloads. Drag it to Applications in Finder and open it from there. |
| "Helper is still setting up" | On first run, the helper is downloading yt-dlp (about 35 MB). Wait a moment. |
| Download fails with `HTTP Error 403` | Usually fixed by yt-dlp's daily update; quitting and reopening the app forces an update check. Age-restricted or members-only videos aren't supported. |
| Slow downloads | Without Deno or Node installed, the helper uses the bundled QuickJS to solve YouTube's challenges, which takes about 15–20 seconds per video. Installing [Deno](https://deno.com) or Node 22+ makes it faster; they're used automatically. |
| Anything else | Check the helper log: `~/Library/Logs/utubmp3-helper.log` on a Mac, `%LOCALAPPDATA%\utubmp3\helper.log` on Windows. |

## Uninstall

1. Turn off the extension in Safari Settings ▸ Extensions.
2. Remove the background helper and its files:
   ```sh
   launchctl bootout gui/$(id -u)/com.harikanthlingutla.utubmp3.helper
   rm ~/Library/LaunchAgents/com.harikanthlingutla.utubmp3.helper.plist
   rm -rf ~/Library/Application\ Support/utubmp3 ~/Library/Logs/utubmp3-helper.log
   ```
3. Delete `utubmp3.app`.

On Windows, remove **utubmp3** in **Settings ▸ Apps ▸ Installed apps**, then remove the extension in `chrome://extensions`. Your MP3s stay in Downloads.

## How it works

Safari extensions can't run programs, so the app includes a background helper: the same executable started as `utubmp3 --helper`. Each time you open the app, it registers the helper as a per-user launch agent, so it starts at login, restarts if it exits, and always points at the current copy of the app.

```
YouTube page ──► Safari extension ──HTTP──► helper (127.0.0.1:47321) ──► yt-dlp + ffmpeg ──► ~/Downloads
```

- The helper listens only on `127.0.0.1` and refuses requests that come from web pages.
- It only accepts YouTube video links, and it only reads or changes `.mp3` files directly inside `~/Downloads`.
- **yt-dlp** is downloaded on first run to `~/Library/Application Support/utubmp3/bin/`, and updated at startup and once a day.
- **ffmpeg** is bundled in the app.
- **A JS runtime** for YouTube's challenges: Deno or Node if installed, otherwise the bundled QuickJS.

On Windows the helper is `utubmp3.exe`, a Go port of the Swift helper with the same HTTP API and checks, so the same extension talks to either. The installer puts it in `%LOCALAPPDATA%\Programs\utubmp3` with `ffmpeg.exe` and `qjs.exe`, and starts it at sign-in from the `HKCU\…\Run` registry key. yt-dlp lives in `%LOCALAPPDATA%\utubmp3\bin`.

## Project layout

| Path | What's there |
|---|---|
| `utubmp3 Extension/Resources/` | Safari extension: `content.js` (MP3 button), `popup.*` (popup and tag editor), `background.js` (talks to the helper) |
| `utubmp3/Helper/` | Background helper: `HelperServer.swift` (endpoints, downloads), `HTTPServer.swift`, `Tags.swift` (clean/edit), `Tools.swift` (yt-dlp, ffmpeg, JS runtime) |
| `utubmp3/HelperInstaller.swift` | Registers the launch agent |
| `utubmp3/main.swift` | Starts the app, or the helper when run with `--helper` |
| `scripts/fetch-tools.sh` | Builds the bundled ffmpeg and downloads QuickJS |
| `scripts/build-ffmpeg.sh` | Builds the minimal ffmpeg (MP3 encoding, tags, cover art) for macOS, or for Windows with `TARGET=windows` |
| `windows/helper/` | Windows helper in Go: `server.go` (endpoints, downloads), `tags.go` (clean/edit), `tools.go` (yt-dlp, ffmpeg, JS runtime) |
| `windows/installer.nsi`, `windows/build.sh` | Windows installer (NSIS) and the script that builds it from macOS |

## Building from source

```sh
git clone https://github.com/harikanthl/utubmp3.git
cd utubmp3
./scripts/fetch-tools.sh   # ffmpeg (built from source, ~2 min) + QuickJS into utubmp3/Resources/bin (not committed)
open utubmp3.xcodeproj     # build & run the utubmp3 scheme
```

In Xcode, set **Signing & Capabilities ▸ Team** to your own team (a free Apple ID works) for both the `utubmp3` and `utubmp3 Extension` targets. If you build without a team ("Sign to Run Locally"), enable Safari ▸ Develop ▸ Allow Unsigned Extensions; Safari turns this off every time it quits.

Building from source doesn't need notarization: Gatekeeper only checks apps downloaded through a browser.

### Windows

The Windows installer is cross-built on a Mac:

```sh
brew install go mingw-w64 makensis
./windows/build.sh         # build/release/utubmp3-setup.exe
```

`go test ./...` in `windows/helper` runs the tag-cleanup tests. The helper also runs on macOS for testing: `UTUBMP3_PORT=47399 go run .` (the Mac app's helper already uses port 47321).

### Releases (notarized)

`scripts/release.sh` builds a Developer ID–signed, notarized and stapled `build/release/utubmp3.dmg` and `utubmp3.zip`, packages the Chrome extension as `utubmp3-chrome.zip`, builds the Windows installer `utubmp3-setup.exe`, and collects the source of the bundled FFmpeg and LAME (`ffmpeg-<version>-source.tar`); attach all five to the release. It needs a Developer ID Application certificate and notarization credentials, either:

- a gitignored `scripts/notarize-env.sh` (or `NOTARIZE_ENV=/path/to/file`) that exports `APPLE_ID`, `APP_PW` (an app-specific password) and `TEAM_ID`, or
- an existing `notarytool` keychain profile: `NOTARY_PROFILE=<name>`.

The app target runs without App Sandbox (it starts the helper and saves to `~/Downloads`), so it is meant for direct distribution, not the Mac App Store. The extension target stays sandboxed.

## License

utubmp3 is released under the [MIT License](LICENSE).

The bundled and downloaded tools keep their own licenses: FFmpeg and LAME (LGPL), QuickJS-NG (MIT) and yt-dlp (Unlicense). If you distribute a built app, follow their terms; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Parts of the helper and extension are adapted from [opalsaints/yt-dlp-chrome-extension](https://github.com/opalsaints/yt-dlp-chrome-extension) (MIT).

Only download content you have the rights to, such as your own uploads or openly licensed videos. Downloading from YouTube may be against its Terms of Service.
