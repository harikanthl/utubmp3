# utubmp3

A Safari extension for macOS that saves the audio of a YouTube video as an MP3, with tools to clean up or edit the MP3's tags.

## For users

1. Install `utubmp3.app` (drag it to Applications) and open it once.
2. Click **Quit and Open Safari Settings…** and turn on the utubmp3 extension.
3. On a YouTube video, click **⬇ MP3** next to Like/Share (it floats in the corner on Shorts), or use the toolbar popup.

That's it: no terminal, no Homebrew. MP3s are saved to `~/Downloads`, and their tags are cleaned automatically. The first download asks for permission to access the Downloads folder.

The popup also lists recent MP3s in `~/Downloads`:

- **Clean** rebuilds the tags from the video's title and description (title, singers, album, composer, lyricist, label), drops hashtags, links and the duplicated description, and renames the file to `Title - Album.mp3`.
- **Edit** lets you change any tag; an empty field removes it.

Tag changes use ffmpeg stream copy, so the audio and cover art are never re-encoded.

## How it works

Safari extensions can't run programs, so the app includes a background helper: the same executable started as `utubmp3 --helper`. Opening the app registers it as a login item (`~/Library/LaunchAgents/com.harikanthlingutla.utubmp3.helper.plist`), so it starts at every login and restarts if it exits. The extension talks to it on `http://127.0.0.1:8765`, and the helper refuses requests from web pages.

| Part | Where |
|---|---|
| Safari extension (button, popup) | `utubmp3 Extension/Resources/` |
| Helper (HTTP server, downloads, tags) | `utubmp3/Helper/` |
| Login-item registration | `utubmp3/HelperInstaller.swift` |

The helper uses:

- **yt-dlp**: downloaded on first run to `~/Library/Application Support/utubmp3/bin/`, and updated at startup and once a day.
- **ffmpeg**: bundled in the app.
- **A JS runtime** for YouTube's challenges: Deno or Node if installed (faster), otherwise the bundled QuickJS.

Helper log: `~/Library/Logs/utubmp3-helper.log`.

## Building

```sh
./scripts/fetch-tools.sh   # downloads ffmpeg + QuickJS into utubmp3/Resources/bin (not committed)
open utubmp3.xcodeproj     # build & run the utubmp3 scheme
```

For unsigned local builds, enable Safari ▸ Develop ▸ Allow Unsigned Extensions. To give the app to other people, sign it with a Developer ID and notarize it. Notarization also requires signing the bundled `ffmpeg` and `qjs` with the hardened runtime.

## License

MIT, see [LICENSE](LICENSE). The bundled and downloaded tools keep their own licenses (FFmpeg is GPLv3); see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Only download content you have the rights to.
