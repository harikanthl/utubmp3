# Third-party notices

Parts of `utubmp3/Helper/HelperServer.swift`, `content.js` and `popup.js` are adapted from
[opalsaints/yt-dlp-chrome-extension](https://github.com/opalsaints/yt-dlp-chrome-extension) (commit d9711ba).

```
MIT License

Copyright (c) 2026 Jonathan Cowley

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Bundled and downloaded tools

These are not part of this repository. `scripts/fetch-tools.sh` downloads them into
`utubmp3/Resources/bin` for building, and the app downloads yt-dlp at runtime. They run as
separate programs and keep their own licenses. If you distribute a built `utubmp3.app`, you
must comply with them (for FFmpeg, that includes the GPL's source-availability terms).

- **FFmpeg**, static build from https://ffmpeg.martin-riedl.de, configured with
  `--enable-gpl --enable-version3`, so it is licensed under the **GNU GPL v3**.
  Source: https://ffmpeg.org/download.html
- **QuickJS-NG**, https://github.com/quickjs-ng/quickjs, **MIT License**.
- **yt-dlp**, https://github.com/yt-dlp/yt-dlp, **The Unlicense**. It is downloaded at runtime
  into `~/Library/Application Support/utubmp3/bin` and self-updates.
