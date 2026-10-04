# utubmp3

A Safari extension that saves the audio of a YouTube video as an MP3, plus tools to clean up or edit the MP3's tags.

Safari extensions can't run programs, so the work is done by a small local helper (`helper/utubmp3_helper.py`) that the extension talks to on `127.0.0.1:8765`. **The helper must be running for the extension to work.**

## Setup

1. Install ffmpeg and Node (Node is the JS runtime yt-dlp uses for YouTube's challenges):
   ```sh
   brew install ffmpeg node
   ```
2. Start the helper and leave it running:
   ```sh
   python3 helper/utubmp3_helper.py
   ```
   On first run it downloads a standalone yt-dlp into `helper/bin/`, and it runs `yt-dlp -U` at startup and once a day.
3. Open `utubmp3.xcodeproj`, run the `utubmp3` app, then enable the extension in Safari ▸ Settings ▸ Extensions (for unsigned builds: Develop ▸ Allow Unsigned Extensions).

## Use

- On a YouTube video, click **⬇ MP3** next to Like/Share (floating button on Shorts), or use the toolbar popup. Files go to `~/Downloads`.
- The popup lists recent MP3s in `~/Downloads`:
  - **Clean** rebuilds tags from the video's title/description (title, singers, album, composer, lyricist, label), drops hashtags, links and the duplicated description, and renames the file to `Title - Album.mp3`.
  - **Edit** lets you change any tag; an empty field removes it.

Tag changes use ffmpeg stream copy, so the audio and cover art are not re-encoded.

Only download content you have the rights to.

## Credits

Parts of the helper and extension are adapted from [opalsaints/yt-dlp-chrome-extension](https://github.com/opalsaints/yt-dlp-chrome-extension) (MIT) — see `THIRD_PARTY_NOTICES.md`.
