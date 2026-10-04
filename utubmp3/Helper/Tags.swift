//
//  Tags.swift
//  utubmp3
//
//  MP3 tag cleanup / editing, done with ffmpeg (stream copy, so the audio and
//  cover art are untouched).
//
//  - clean: rebuild tags from the video's title/description, dropping YouTube
//    junk (hashtags, social links, URLs, the duplicated description).
//  - edit: write user-supplied values for any field; an empty value removes it.
//

import Foundation

nonisolated enum Tags {
    static let editable = ["title", "artist", "album", "album_artist", "composer", "lyricist",
                           "genre", "date", "track", "publisher", "copyright"]

    /// "Key : Value" lines commonly found in music-video descriptions.
    private static let descriptionKeys: [String: [String]] = [
        "title": ["song", "song name", "song title", "track", "track name", "title"],
        "album": ["movie", "movie name", "film", "film name", "album", "album name"],
        "artist": ["singer", "singers", "singer(s)", "vocals", "sung by", "artist", "artists"],
        "composer": ["music", "music director", "music directer", "composer", "music composer",
                     "composed by", "music by"],
        "lyricist": ["lyrics", "lyricist", "lyrics by", "lyric writer", "lyricists", "written by"],
        "publisher": ["label", "music label", "record label", "music on", "audio on"],
    ]
    private static let keyLookup: [String: String] = {
        var lookup: [String: String] = [:]
        for (field, aliases) in descriptionKeys {
            for alias in aliases { lookup[alias] = field }
        }
        return lookup
    }()

    private static let kvLine = try! NSRegularExpression(
        pattern: #"^\s*([A-Za-z][A-Za-z ().]{1,30}?)\s*[:：]\s*(.+?)\s*$"#)
    private static let copyrightLine = try! NSRegularExpression(
        pattern: #"[©℗]|\bcopyright\b"#, options: .caseInsensitive)
    private static let titleSeparator = try! NSRegularExpression(pattern: #"\s*[|｜]\s*"#)
    private static let titleNoise = try! NSRegularExpression(
        pattern: #"\s*[(\[][^)\]]*(official|lyric|video|audio|hd|4k|full song)[^)\]]*[)\]]"#
            + #"|\s+(full video song|video song|lyrical video|lyrical song|lyrical|"#
            + #"telugu lyrics|hindi lyrics|tamil lyrics|lyrics|full song|song)\s*$"#,
        options: .caseInsensitive)
    private static let unsafeFilenameChars = try! NSRegularExpression(pattern: #"[/\\:*?"<>|\x00-\x1f]"#)
    private static let whitespace = try! NSRegularExpression(pattern: #"\s+"#)

    // MARK: - Reading

    static func read(_ path: String) throws -> [String: String] {
        let result = try Tools.run(Tools.ffmpeg, ["-v", "error", "-i", path, "-f", "ffmetadata", "-"], timeout: 30)
        guard result.status == 0 else { throw ToolError.failed(String(result.stderr.suffix(300))) }
        return parseFFMetadata(result.stdout)
    }

    /// Parses ffmpeg's ffmetadata format: `key=value` lines where `=;#\` and
    /// newlines are backslash-escaped. Stops at the first `[SECTION]`.
    static func parseFFMetadata(_ text: String) -> [String: String] {
        var tags: [String: String] = [:]
        var chars = Array(text)[...]
        // Skip the ";FFMETADATA1" header line.
        if let newline = chars.firstIndex(of: "\n") { chars = chars[(newline + 1)...] }

        while let first = chars.first {
            if first == "\n" { chars.removeFirst(); continue }
            if first == "[" { break }
            if first == ";" || first == "#" {
                if let newline = chars.firstIndex(of: "\n") { chars = chars[(newline + 1)...] } else { break }
                continue
            }
            var key = "", value = "", inValue = false
            while let c = chars.popFirst() {
                if c == "\\", let escaped = chars.popFirst() {
                    if inValue { value.append(escaped) } else { key.append(escaped) }
                } else if c == "=" && !inValue {
                    inValue = true
                } else if c == "\n" {
                    break
                } else if inValue {
                    value.append(c)
                } else {
                    key.append(c)
                }
            }
            if inValue { tags[key.lowercased()] = value }
        }
        return tags
    }

    // MARK: - Cleaning

    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> [String]? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (1..<match.numberOfRanges).map { i in
            Range(match.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
    }

    private static func cleanTitle(_ title: String) -> String {
        let range = NSRange(title.startIndex..., in: title)
        var first = title
        if let sep = titleSeparator.firstMatch(in: title, range: range), let r = Range(sep.range, in: title) {
            first = String(title[..<r.lowerBound])
        }
        var previous: String?
        while previous != first {
            previous = first
            first = titleNoise.stringByReplacingMatches(in: first, range: NSRange(first.startIndex..., in: first),
                                                        withTemplate: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: " -–—"))
        }
        return first.isEmpty ? title : first
    }

    /// Tags to keep after cleaning: credits parsed from the description plus existing useful tags.
    static func suggestClean(_ tags: [String: String]) -> [String: String] {
        let description = [tags["description"], tags["synopsis"], tags["comment"]]
            .compactMap { $0 }.first { !$0.isEmpty } ?? ""
        var parsed: [String: String] = [:]
        for line in description.components(separatedBy: .newlines) where !line.contains("http") {
            if let groups = firstMatch(kvLine, in: line) {
                let key = groups[0].trimmingCharacters(in: .whitespaces).lowercased()
                if let field = keyLookup[key], parsed[field] == nil {
                    parsed[field] = groups[1]
                }
            } else if parsed["copyright"] == nil, line.count < 200,
                      copyrightLine.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                parsed["copyright"] = line.trimmingCharacters(in: .whitespaces)
            }
        }

        var clean = tags.filter { editable.contains($0.key) && !$0.value.isEmpty }
        clean["title"] = parsed["title"] ?? cleanTitle(tags["title"] ?? "")
        for field in ["album", "composer", "lyricist", "copyright"] {
            if let value = parsed[field], (tags[field] ?? "").isEmpty { clean[field] = value }
        }
        if let singers = parsed["artist"] {
            // yt-dlp sets artist to the uploading channel; keep that as the publisher
            // so the source isn't lost when the singers take over the artist field.
            if let channel = tags["artist"], !channel.isEmpty, (clean["publisher"] ?? "").isEmpty {
                clean["publisher"] = channel
            }
            clean["artist"] = singers
        }
        if let label = parsed["publisher"] { clean["publisher"] = label }
        if clean["genre"]?.lowercased() == "music" { clean["genre"] = nil }
        return clean.filter { !$0.value.isEmpty }
    }

    // MARK: - Writing

    private static func safeName(_ text: String) -> String {
        var name = unsafeFilenameChars.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        name = whitespace.stringByReplacingMatches(
            in: name, range: NSRange(name.startIndex..., in: name), withTemplate: " ")
        return String(name.trimmingCharacters(in: CharacterSet(charactersIn: " .")).prefix(150))
    }

    /// Replaces all tags in `path` with `tags`, then renames it from title/album.
    /// Returns the new path.
    static func write(_ path: String, _ tags: [String: String]) throws -> String {
        let tmp = path + ".utubmp3.tmp.mp3"
        var args = ["-v", "error", "-y", "-i", path, "-map", "0", "-c", "copy",
                    "-map_metadata", "-1", "-fflags", "+bitexact", "-id3v2_version", "3"]
        for (key, value) in tags.sorted(by: { $0.key < $1.key }) {
            args += ["-metadata", "\(key)=\(value)"]
        }
        let result = try Tools.run(Tools.ffmpeg, args + [tmp], timeout: 120)
        guard result.status == 0 else {
            try? FileManager.default.removeItem(atPath: tmp)
            throw ToolError.failed(String(result.stderr.suffix(300)))
        }

        let fm = FileManager.default
        let base = safeName([tags["title"], tags["album"]].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: " - "))
        var newPath = path
        if !base.isEmpty {
            let directory = (path as NSString).deletingLastPathComponent
            let original = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            var candidate = (directory as NSString).appendingPathComponent(base + ".mp3")
            var n = 2
            while fm.fileExists(atPath: candidate),
                  URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path != original {
                candidate = (directory as NSString).appendingPathComponent("\(base) (\(n)).mp3")
                n += 1
            }
            newPath = candidate
        }
        if newPath == path {
            _ = try fm.replaceItemAt(URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: tmp))
        } else {
            try fm.moveItem(atPath: tmp, toPath: newPath)
            try fm.removeItem(atPath: path)
        }
        return newPath
    }

    static func clean(_ path: String) throws -> String {
        try write(path, suggestClean(try read(path)))
    }

    static func edit(_ path: String, _ values: [String: String]) throws -> String {
        var tags = try read(path).filter { editable.contains($0.key) && !$0.value.isEmpty }
        for key in editable {
            guard let raw = values[key] else { continue }
            let value = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
            tags[key] = value.isEmpty ? nil : value
        }
        return try write(path, tags)
    }
}
