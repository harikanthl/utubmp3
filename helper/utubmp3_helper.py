#!/usr/bin/env -S python3 -u
"""
utubmp3 local helper: a tiny HTTP server on 127.0.0.1 that runs yt-dlp + ffmpeg
to save the audio of a YouTube video as MP3 in ~/Downloads.

Safari web extensions can't spawn processes (their native handler is sandboxed),
so the extension talks to this helper over localhost instead of native messaging.

The yt-dlp invocation is adapted from opalsaints/yt-dlp-chrome-extension
(MIT License, Copyright (c) 2026 Jonathan Cowley) — see THIRD_PARTY_NOTICES.md.

Usage:  python3 helper/utubmp3_helper.py
(downloads helper/bin/yt-dlp on first run and runs `yt-dlp -U` daily)
"""

import json
import os
import re
import shutil
import subprocess
import threading
import time
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

import tags

HOST, PORT = "127.0.0.1", 8765
OUTPUT_DIR = os.path.expanduser("~/Downloads")

# The helper keeps its own standalone yt-dlp in helper/bin and self-updates it,
# because YouTube breaks old yt-dlp versions regularly.
YTDLP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bin", "yt-dlp")
YTDLP_RELEASE = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
UPDATE_INTERVAL = 24 * 60 * 60
FFMPEG = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
# yt-dlp needs a JS runtime to solve YouTube's challenges (otherwise: 403s / missing
# formats). It only looks for deno by default, so point it at whichever one we have.
JS_RUNTIMES = [
    f"{name}:{path}"
    for name in ("deno", "node")
    if (path := shutil.which(name) or (f"/opt/homebrew/bin/{name}" if os.path.exists(f"/opt/homebrew/bin/{name}") else None))
]

VIDEO_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")

jobs = {}
jobs_lock = threading.Lock()


def ensure_ytdlp():
    """Download the standalone yt-dlp into helper/bin if it isn't there yet."""
    if os.path.exists(YTDLP):
        return
    print(f"[utubmp3] yt-dlp missing, downloading {YTDLP_RELEASE}")
    os.makedirs(os.path.dirname(YTDLP), exist_ok=True)
    tmp = YTDLP + ".part"
    urllib.request.urlretrieve(YTDLP_RELEASE, tmp)
    os.chmod(tmp, 0o755)
    os.replace(tmp, YTDLP)


def update_ytdlp_forever():
    """Run `yt-dlp -U` now and then once a day."""
    while True:
        try:
            out = subprocess.run([YTDLP, "-U"], capture_output=True, text=True, timeout=300)
            lines = (out.stdout + out.stderr).strip().splitlines()
            print("[utubmp3] yt-dlp -U:", lines[-1] if lines else out.returncode)
        except Exception as e:  # noqa: BLE001 — a failed update shouldn't kill the helper
            print("[utubmp3] yt-dlp update failed:", e)
        time.sleep(UPDATE_INTERVAL)


def mp3_in_output_dir(name):
    """Resolve a bare .mp3 filename inside OUTPUT_DIR, or None."""
    if not isinstance(name, str) or not name.lower().endswith(".mp3") or os.path.basename(name) != name:
        return None
    path = os.path.join(OUTPUT_DIR, name)
    real = os.path.realpath(path)
    if os.path.dirname(real) != os.path.realpath(OUTPUT_DIR) or not os.path.isfile(real):
        return None
    return path


def recent_mp3s(limit=25):
    entries = [e for e in os.scandir(OUTPUT_DIR)
               if e.is_file() and e.name.lower().endswith(".mp3") and ".utubmp3.tmp." not in e.name]
    entries.sort(key=lambda e: e.stat().st_mtime, reverse=True)
    return [e.name for e in entries[:limit]]


def video_id_from_url(url):
    """Return the 11-char video id for a youtube.com / youtu.be URL, else None."""
    try:
        u = urlparse(url)
    except ValueError:
        return None
    host = (u.hostname or "").lower()
    if host == "youtu.be":
        vid = u.path.lstrip("/").split("/")[0]
    elif host == "youtube.com" or host.endswith(".youtube.com"):
        if u.path == "/watch":
            vid = parse_qs(u.query).get("v", [""])[0]
        elif u.path.startswith(("/shorts/", "/live/")):
            vid = u.path.split("/")[2]
        else:
            return None
    else:
        return None
    return vid if VIDEO_ID.match(vid) else None


def run_job(job_id, video_id):
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    cmd = [
        YTDLP,
        "--no-playlist",
        "--ffmpeg-location", FFMPEG,
        "-f", "bestaudio/best",
        "--extract-audio",
        "--audio-format", "mp3",
        "--audio-quality", "0",
        "--embed-thumbnail",
        "--embed-metadata",
        *[arg for rt in JS_RUNTIMES for arg in ("--js-runtimes", rt)],
        "--no-simulate",
        "--print", "after_move:filepath",
        "-o", os.path.join(OUTPUT_DIR, "%(title)s.%(ext)s"),
        f"https://www.youtube.com/watch?v={video_id}",
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
        if result.returncode == 0:
            lines = [l for l in result.stdout.splitlines() if l.strip()]
            filepath = lines[-1].strip() if lines else ""
            update = {"status": "complete", "filepath": filepath,
                      "filename": os.path.basename(filepath) or "download complete"}
        else:
            msg = (result.stderr.strip() or result.stdout.strip())[-300:]
            update = {"status": "error", "message": msg or "yt-dlp failed"}
    except subprocess.TimeoutExpired:
        update = {"status": "error", "message": "Download timed out (15 min limit)"}
    except FileNotFoundError:
        update = {"status": "error", "message": "yt-dlp not found in helper/bin. Restart the helper to re-download it."}
    except Exception as e:  # noqa: BLE001 — report anything back to the extension
        update = {"status": "error", "message": str(e)}
    with jobs_lock:
        jobs[job_id].update(update)


class Handler(BaseHTTPRequestHandler):
    def _web_origin(self):
        # Requests from ordinary web pages carry an http(s) Origin; the extension's don't.
        origin = self.headers.get("Origin", "")
        return origin.startswith(("http://", "https://"))

    def _send(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        origin = self.headers.get("Origin")
        if origin and not self._web_origin():
            self.send_header("Access-Control-Allow-Origin", origin)
        self.end_headers()
        self.wfile.write(data)

    def _guard(self):
        if self._web_origin():
            self._send(403, {"status": "error", "message": "forbidden"})
            return False
        return True

    def do_OPTIONS(self):
        if not self._guard():
            return
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", self.headers.get("Origin", "*"))
        self.send_header("Access-Control-Allow-Methods", "GET, POST")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        if not self._guard():
            return
        u = urlparse(self.path)
        if u.path == "/health":
            self._send(200, {"ok": True,
                             "ytdlp": os.path.exists(YTDLP),
                             "ffmpeg": bool(shutil.which(FFMPEG) or os.path.exists(FFMPEG))})
        elif u.path == "/files":
            self._send(200, {"files": recent_mp3s()})
        elif u.path == "/tags":
            path = mp3_in_output_dir(parse_qs(u.query).get("name", [""])[0])
            if not path:
                self._send(404, {"status": "error", "message": "file not found"})
                return
            current = tags.read_tags(FFMPEG, path)
            self._send(200, {
                "tags": {k: current.get(k, "") for k in tags.EDITABLE},
            })
        elif u.path == "/status":
            job_id = parse_qs(u.query).get("id", [""])[0]
            with jobs_lock:
                job = dict(jobs.get(job_id, {}))
            if job:
                self._send(200, job)
            else:
                self._send(404, {"status": "error", "message": "unknown job"})
        else:
            self._send(404, {"status": "error", "message": "not found"})

    def do_POST(self):
        if not self._guard():
            return
        if self.headers.get("Content-Type", "").split(";")[0] != "application/json":
            self._send(415, {"status": "error", "message": "expected application/json"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            body = json.loads(self.rfile.read(min(length, 10_000)) or b"{}")
        except (ValueError, json.JSONDecodeError):
            self._send(400, {"status": "error", "message": "bad json"})
            return

        path = urlparse(self.path).path
        if path == "/download":
            video_id = video_id_from_url(body.get("url", ""))
            if not video_id:
                self._send(400, {"status": "error", "message": "Not a YouTube video URL"})
                return
            job_id = uuid.uuid4().hex
            with jobs_lock:
                jobs[job_id] = {"status": "downloading", "videoId": video_id}
            threading.Thread(target=run_job, args=(job_id, video_id), daemon=True).start()
            self._send(200, {"status": "downloading", "id": job_id})
        elif path in ("/clean", "/edit"):
            target = mp3_in_output_dir(body.get("name"))
            if not target:
                self._send(404, {"status": "error", "message": "file not found"})
                return
            try:
                if path == "/clean":
                    new_path = tags.clean(FFMPEG, target)
                else:
                    new_path = tags.edit(FFMPEG, target, body.get("tags") or {})
            except subprocess.CalledProcessError as e:
                self._send(500, {"status": "error", "message": (e.stderr or str(e))[-300:]})
                return
            self._send(200, {"status": "ok", "name": os.path.basename(new_path)})
        elif path == "/reveal":
            with jobs_lock:
                filepath = jobs.get(body.get("id", ""), {}).get("filepath", "")
            if body.get("name"):
                filepath = mp3_in_output_dir(body["name"]) or ""
            if filepath and os.path.exists(filepath):
                subprocess.Popen(["open", "-R", filepath])
            else:
                subprocess.Popen(["open", OUTPUT_DIR])
            self._send(200, {"status": "ok"})
        else:
            self._send(404, {"status": "error", "message": "not found"})

    def log_message(self, fmt, *args):
        print("[utubmp3]", fmt % args)


if __name__ == "__main__":
    ensure_ytdlp()
    threading.Thread(target=update_ytdlp_forever, daemon=True).start()
    print(f"utubmp3 helper on http://{HOST}:{PORT}  (yt-dlp: {YTDLP}, ffmpeg: {FFMPEG}, js: {JS_RUNTIMES or 'none'})")
    print(f"MP3s are saved to {OUTPUT_DIR}. Ctrl+C to stop.")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
