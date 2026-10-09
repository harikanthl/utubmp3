# utubmp3

A Safari extension for macOS that saves the audio of a YouTube video as an MP3, with built-in tools to clean up or edit the MP3's tags.

Install the app, open it once, turn on the extension, and you're done. No terminal, Homebrew or Python needed.

## Features

- **One-click MP3**: a **⬇ MP3** button next to Like/Share on YouTube videos (it floats in the corner on Shorts), plus a toolbar popup.
- **Best-quality audio** converted to MP3, with the video thumbnail embedded as cover art.
- **Automatic tag cleanup**: every download gets proper tags (title, singers, album/movie, composer, lyricist, label) parsed from the video's description. Hashtags, social links, URLs and the duplicated description are removed, and the file is renamed to `Title - Album.mp3`.
- **Tag editor**: the popup lists recent MP3s in `~/Downloads` with **Clean** and **Edit** buttons. Edit lets you change any tag; an empty field removes it. Audio and cover art are never re-encoded.
- **Always up to date**: yt-dlp updates itself daily, so downloads keep working when YouTube changes.
- **Runs locally**: nothing leaves your Mac except the download from YouTube.

## Requirements

- macOS 26.2 or later (the app target's deployment target)
- Safari

## Install

1. Download the latest `utubmp3-<version>.dmg` from [Releases](https://github.com/harikanthl/utubmp3/releases), drag `utubmp3.app` to Applications, and open it once. The app is notarized by Apple.
2. Click **Quit and Open Safari Settings…** and turn on the **utubmp3** extension. Allow it on `youtube.com` when Safari asks.
3. Open any YouTube video and click **⬇ MP3**.

MP3s are saved to `~/Downloads`. On the first download, macOS asks whether utubmp3 may access the Downloads folder; click **Allow**.

Opening the app also sets up a small background helper (see [How it works](#how-it-works)). It starts automatically at every login, and macOS may show a "Background Items Added" notification the first time.

## Use

| Where | What to do |
|---|---|
| YouTube video page | Click **⬇ MP3**. It changes to ⏳ while converting and ✅ **Saved** when done; click ✅ to show the file in Finder. Hover over ⚠️ to see the error. |
| Toolbar popup | **Download MP3** for the current video, with a **Show in Finder** button when it finishes. |
| Popup ▸ Recent MP3s | **Clean** fixes a file's tags automatically; **Edit** opens a form with every tag. |

## Troubleshooting

| Problem | Fix |
|---|---|
| "Helper not running" in the popup | Open the utubmp3 app once; it restarts the helper. |
| "Helper is still setting up" | On first run, the helper is downloading yt-dlp (about 35 MB). Wait a moment. |
| Download fails with `HTTP Error 403` | Usually fixed by yt-dlp's daily update; quitting and reopening the app forces an update check. Age-restricted or members-only videos aren't supported. |
| Slow downloads | Without Deno or Node installed, the helper uses the bundled QuickJS to solve YouTube's challenges, which takes about 15–20 seconds per video. Installing [Deno](https://deno.com) or Node 22+ makes it faster; they're used automatically. |
| Anything else | Check the helper log at `~/Library/Logs/utubmp3-helper.log`. |

## Uninstall

1. Turn off the extension in Safari Settings ▸ Extensions.
2. Remove the background helper and its files:
   ```sh
   launchctl bootout gui/$(id -u)/com.harikanthlingutla.utubmp3.helper
   rm ~/Library/LaunchAgents/com.harikanthlingutla.utubmp3.helper.plist
   rm -rf ~/Library/Application\ Support/utubmp3 ~/Library/Logs/utubmp3-helper.log
   ```
3. Delete `utubmp3.app`.

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

## Project layout

| Path | What's there |
|---|---|
| `utubmp3 Extension/Resources/` | Safari extension: `content.js` (MP3 button), `popup.*` (popup and tag editor), `background.js` (talks to the helper) |
| `utubmp3/Helper/` | Background helper: `HelperServer.swift` (endpoints, downloads), `HTTPServer.swift`, `Tags.swift` (clean/edit), `Tools.swift` (yt-dlp, ffmpeg, JS runtime) |
| `utubmp3/HelperInstaller.swift` | Registers the launch agent |
| `utubmp3/main.swift` | Starts the app, or the helper when run with `--helper` |
| `scripts/fetch-tools.sh` | Downloads the bundled ffmpeg and QuickJS |

## Building from source

```sh
git clone https://github.com/harikanthl/utubmp3.git
cd utubmp3
./scripts/fetch-tools.sh   # ffmpeg + QuickJS into utubmp3/Resources/bin (not committed)
open utubmp3.xcodeproj     # build & run the utubmp3 scheme
```

In Xcode, set **Signing & Capabilities ▸ Team** to your own team (a free Apple ID works) for both the `utubmp3` and `utubmp3 Extension` targets. If you build without a team ("Sign to Run Locally"), enable Safari ▸ Develop ▸ Allow Unsigned Extensions; Safari turns this off every time it quits.

Building from source doesn't need notarization: Gatekeeper only checks apps downloaded through a browser.

### Releases (notarized)

`scripts/release.sh` builds a Developer ID–signed, notarized and stapled `build/release/utubmp3-<version>.dmg` and `.zip` for GitHub Releases. It needs a Developer ID Application certificate and notarization credentials, either:

- a gitignored `scripts/notarize-env.sh` (or `NOTARIZE_ENV=/path/to/file`) that exports `APPLE_ID`, `APP_PW` (an app-specific password) and `TEAM_ID`, or
- an existing `notarytool` keychain profile: `NOTARY_PROFILE=<name>`.

The app target runs without App Sandbox (it starts the helper and saves to `~/Downloads`), so it is meant for direct distribution, not the Mac App Store. The extension target stays sandboxed.

## License

utubmp3 is released under the [MIT License](LICENSE).

The bundled and downloaded tools keep their own licenses: FFmpeg (GPLv3), QuickJS-NG (MIT) and yt-dlp (Unlicense). If you distribute a built app, follow their terms; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Parts of the helper and extension are adapted from [opalsaints/yt-dlp-chrome-extension](https://github.com/opalsaints/yt-dlp-chrome-extension) (MIT).

Only download content you have the rights to, such as your own uploads or openly licensed videos. Downloading from YouTube may be against its Terms of Service.
