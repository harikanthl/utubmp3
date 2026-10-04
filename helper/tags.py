"""
MP3 tag cleanup / editing for utubmp3, done with ffprobe + ffmpeg (stream copy,
so the audio and cover art are untouched).

- clean: rebuild tags from the video's title/description, dropping YouTube junk
  (hashtags, social links, URLs, the duplicated description).
- edit: write user-supplied values for any field; an empty value removes it.
"""

import json
import os
import re
import subprocess

EDITABLE = ["title", "artist", "album", "album_artist", "composer", "lyricist",
            "genre", "date", "track", "publisher", "copyright"]
KEEP_ON_CLEAN = EDITABLE

# "Key : Value" lines commonly found in music-video descriptions.
DESCRIPTION_KEYS = {
    "title": ["song", "song name", "song title", "track", "track name", "title"],
    "album": ["movie", "movie name", "film", "film name", "album", "album name"],
    "artist": ["singer", "singers", "singer(s)", "vocals", "sung by", "artist", "artists"],
    "composer": ["music", "music director", "music directer", "composer", "music composer",
                 "composed by", "music by"],
    "lyricist": ["lyrics", "lyricist", "lyrics by", "lyric writer", "lyricists", "written by"],
    "publisher": ["label", "music label", "record label", "music on", "audio on"],
}
KEY_LOOKUP = {alias: field for field, aliases in DESCRIPTION_KEYS.items() for alias in aliases}
KV_LINE = re.compile(r"^\s*([A-Za-z][A-Za-z ().]{1,30}?)\s*[:：]\s*(.+?)\s*$")
TITLE_NOISE = re.compile(
    r"\s*[(\[][^)\]]*(official|lyric|video|audio|hd|4k|full song)[^)\]]*[)\]]"
    r"|\s+(full video song|video song|lyrical video|lyrical song|lyrical|"
    r"telugu lyrics|hindi lyrics|tamil lyrics|lyrics|full song|song)\s*$",
    re.IGNORECASE,
)


def ffprobe_path(ffmpeg):
    sibling = os.path.join(os.path.dirname(ffmpeg), "ffprobe")
    return sibling if os.path.exists(sibling) else "ffprobe"


def read_tags(ffmpeg, path):
    out = subprocess.run(
        [ffprobe_path(ffmpeg), "-v", "error", "-show_entries", "format_tags", "-of", "json", path],
        capture_output=True, text=True, timeout=30, check=True,
    )
    tags = json.loads(out.stdout).get("format", {}).get("tags", {})
    return {k.lower(): v for k, v in tags.items()}


def _clean_title(title):
    first = re.split(r"\s*[|｜]\s*", title)[0]
    prev = None
    while prev != first:
        prev, first = first, TITLE_NOISE.sub("", first).strip(" -–—")
    return first or title


def suggest_clean(tags):
    """Tags to keep after cleaning: parsed credits + existing useful tags."""
    description = tags.get("description") or tags.get("synopsis") or tags.get("comment") or ""
    parsed = {}
    for line in description.splitlines():
        if "http" in line:
            continue
        m = KV_LINE.match(line)
        if m:
            field = KEY_LOOKUP.get(m.group(1).strip().lower())
            if field and field not in parsed:
                parsed[field] = m.group(2)
        elif "copyright" not in parsed and re.search(r"[©℗]|\bcopyright\b", line, re.I) and len(line) < 200:
            parsed["copyright"] = line.strip()

    clean = {k: tags[k] for k in KEEP_ON_CLEAN if tags.get(k)}
    clean["title"] = parsed.get("title") or _clean_title(tags.get("title", ""))
    for field in ("album", "composer", "lyricist", "copyright"):
        if parsed.get(field) and not tags.get(field):
            clean[field] = parsed[field]
    if parsed.get("artist"):
        # yt-dlp sets artist to the uploading channel; keep that as the publisher
        # so the source isn't lost when the singers take over the artist field.
        if tags.get("artist") and not clean.get("publisher"):
            clean["publisher"] = tags["artist"]
        clean["artist"] = parsed["artist"]
    if parsed.get("publisher"):
        clean["publisher"] = parsed["publisher"]
    if clean.get("genre", "").lower() == "music":
        del clean["genre"]
    return {k: v for k, v in clean.items() if v}


def _safe_name(text):
    text = re.sub(r'[/\\:*?"<>|\x00-\x1f]', " ", text)
    return re.sub(r"\s+", " ", text).strip(" .")[:150]


def write_tags(ffmpeg, path, tags):
    """Replace all tags in `path` with `tags`, then rename it from title/album.
    Returns the new path."""
    tmp = path + ".utubmp3.tmp.mp3"
    cmd = [ffmpeg, "-v", "error", "-y", "-i", path, "-map", "0", "-c", "copy",
           "-map_metadata", "-1", "-fflags", "+bitexact", "-id3v2_version", "3"]
    for k, v in tags.items():
        cmd += ["-metadata", f"{k}={v}"]
    subprocess.run(cmd + [tmp], capture_output=True, text=True, timeout=120, check=True)

    base = _safe_name(" - ".join(x for x in (tags.get("title"), tags.get("album")) if x))
    new_path = path
    if base:
        directory = os.path.dirname(path)
        candidate, n = os.path.join(directory, base + ".mp3"), 2
        while os.path.exists(candidate) and os.path.realpath(candidate) != os.path.realpath(path):
            candidate, n = os.path.join(directory, f"{base} ({n}).mp3"), n + 1
        new_path = candidate
    os.replace(tmp, new_path)
    if new_path != path:
        os.remove(path)
    return new_path


def clean(ffmpeg, path):
    return write_tags(ffmpeg, path, suggest_clean(read_tags(ffmpeg, path)))


def edit(ffmpeg, path, values):
    current = read_tags(ffmpeg, path)
    tags = {k: current[k] for k in KEEP_ON_CLEAN if current.get(k)}
    for k in EDITABLE:
        if k in values:
            v = str(values[k]).strip()[:500]
            if v:
                tags[k] = v
            else:
                tags.pop(k, None)
    return write_tags(ffmpeg, path, tags)
