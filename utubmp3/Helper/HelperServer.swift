//
//  HelperServer.swift
//  utubmp3
//
//  The background helper: `utubmp3 --helper`, started at login by launchd.
//  Safari web extensions can't spawn processes, so the extension talks to this
//  over http://127.0.0.1:47321 and it runs yt-dlp + ffmpeg.
//
//  The yt-dlp invocation is adapted from opalsaints/yt-dlp-chrome-extension
//  (MIT License) — see THIRD_PARTY_NOTICES.md.
//

import Foundation

nonisolated enum HelperServer {
    static let port: UInt16 = 47321

    private static let jobsLock = NSLock()
    nonisolated(unsafe) private static var jobs: [String: [String: Any]] = [:]
    nonisolated(unsafe) private static var server: HTTPServer?  // keeps the listener alive

    static func run() -> Never {
        helperLog("helper starting on 127.0.0.1:\(port) (ffmpeg: \(Tools.ffmpeg), js: \(Tools.jsRuntimeArgs))")
        Tools.keepYtdlpUpdated()
        do {
            server = try HTTPServer(port: port, handler: handle)
            server?.start()
        } catch {
            helperLog("could not start server: \(error)")
            exit(1)
        }
        dispatchMain()
    }

    /// Blocks DNS rebinding: a page whose domain resolves to 127.0.0.1 sends its own Host.
    static func isLocalHost(_ host: String?) -> Bool {
        host == "127.0.0.1:\(port)" || host == "localhost:\(port)"
    }

    /// Requests from ordinary web pages carry an http(s) Origin; the extension's don't.
    static func isWebOrigin(_ origin: String) -> Bool {
        origin.hasPrefix("http://") || origin.hasPrefix("https://")
    }

    private static func error(_ status: Int, _ message: String) -> HTTPResponse {
        HTTPResponse(status: status, json: ["status": "error", "message": message])
    }

    static func handle(_ request: HTTPRequest) -> HTTPResponse {
        guard isLocalHost(request.headers["host"]) else { return error(403, "forbidden") }
        if let origin = request.headers["origin"], isWebOrigin(origin) {
            return error(403, "forbidden")
        }
        if request.method == "POST",
           request.headers["content-type"]?.split(separator: ";").first != "application/json" {
            return error(415, "expected application/json")
        }
        let body = request.jsonBody

        switch (request.method, request.path) {
        case ("GET", "/health"):
            return HTTPResponse(status: 200, json: [
                "ok": true,
                "app": "utubmp3",
                "ytdlp": FileManager.default.isExecutableFile(atPath: Tools.ytdlp.path),
                "ffmpeg": FileManager.default.isExecutableFile(atPath: Tools.ffmpeg),
            ])

        case ("GET", "/status"):
            jobsLock.lock()
            let job = jobs[request.query["id"] ?? ""]
            jobsLock.unlock()
            return job.map { HTTPResponse(status: 200, json: $0) } ?? error(404, "unknown job")

        case ("GET", "/files"):
            return HTTPResponse(status: 200, json: ["files": recentMP3s()])

        case ("GET", "/tags"):
            guard let path = mp3InOutputDir(request.query["name"]) else { return error(404, "file not found") }
            do {
                let current = try Tags.read(path)
                var tags: [String: String] = [:]
                for key in Tags.editable { tags[key] = current[key] ?? "" }
                return HTTPResponse(status: 200, json: ["tags": tags])
            } catch {
                return self.error(500, "\(error)")
            }

        case ("POST", "/download"):
            guard let videoID = videoID(from: body["url"] as? String ?? "") else {
                return error(400, "Not a YouTube video URL")
            }
            let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            setJob(id, ["status": "downloading", "videoId": videoID])
            DispatchQueue.global().async { runJob(id, videoID) }
            return HTTPResponse(status: 200, json: ["status": "downloading", "id": id])

        case ("POST", "/clean"), ("POST", "/edit"):
            guard let path = mp3InOutputDir(body["name"] as? String) else { return error(404, "file not found") }
            do {
                let newPath = request.path == "/clean"
                    ? try Tags.clean(path)
                    : try Tags.edit(path, (body["tags"] as? [String: Any] ?? [:]).compactMapValues { "\($0)" })
                return HTTPResponse(status: 200, json: ["status": "ok", "name": (newPath as NSString).lastPathComponent])
            } catch {
                return self.error(500, "\(error)")
            }

        case ("POST", "/reveal"):
            var filepath = ""
            if let name = body["name"] as? String {
                filepath = mp3InOutputDir(name) ?? ""
            } else {
                jobsLock.lock()
                filepath = jobs[body["id"] as? String ?? ""]?["filepath"] as? String ?? ""
                jobsLock.unlock()
            }
            let args = FileManager.default.fileExists(atPath: filepath) ? ["-R", filepath] : [Tools.outputDir.path]
            _ = try? Tools.run("/usr/bin/open", args, timeout: 10)
            return HTTPResponse(status: 200, json: ["status": "ok"])

        default:
            return error(404, "not found")
        }
    }

    // MARK: - Jobs

    private static func setJob(_ id: String, _ update: [String: Any]) {
        jobsLock.lock()
        jobs[id, default: [:]].merge(update) { _, new in new }
        jobsLock.unlock()
    }

    private static func runJob(_ id: String, _ videoID: String) {
        do {
            try Tools.ensureYtdlp()
            try FileManager.default.createDirectory(at: Tools.outputDir, withIntermediateDirectories: true)
            let args = [
                "--no-playlist",
                "--ffmpeg-location", Tools.ffmpeg,
                "-f", "bestaudio/best",
                "--extract-audio",
                "--audio-format", "mp3",
                "--audio-quality", "0",
                "--embed-thumbnail",
                "--embed-metadata",
            ] + Tools.jsRuntimeArgs + [
                "--no-simulate",
                "--print", "after_move:filepath",
                "-o", Tools.outputDir.appendingPathComponent("%(title)s.%(ext)s").path,
                "https://www.youtube.com/watch?v=\(videoID)",
            ]
            let result = try Tools.run(Tools.ytdlp.path, args, timeout: 900)
            guard result.status == 0 else {
                let message = (result.stderr.isEmpty ? result.stdout : result.stderr)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                setJob(id, ["status": "error", "message": String(message.suffix(300))])
                return
            }

            var filepath = result.stdout.split(separator: "\n").last.map {
                $0.trimmingCharacters(in: .whitespaces)
            } ?? ""
            if !filepath.isEmpty {
                // Auto-clean every download; keep the file even if cleaning fails.
                do { filepath = try Tags.clean(filepath) } catch { helperLog("auto-clean failed: \(error)") }
            }
            let filename = (filepath as NSString).lastPathComponent
            setJob(id, ["status": "complete", "filepath": filepath,
                        "filename": filename.isEmpty ? "download complete" : filename])
        } catch ToolError.timedOut {
            setJob(id, ["status": "error", "message": "Download timed out (15 min limit)"])
        } catch {
            setJob(id, ["status": "error", "message": "\(error)"])
        }
    }

    // MARK: - Validation

    private static let videoIDPattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9_-]{11}$")

    /// The 11-char video id for a youtube.com / youtu.be URL, else nil.
    static func videoID(from url: String) -> String? {
        guard let components = URLComponents(string: url), let host = components.host?.lowercased() else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        let id: String?
        if host == "youtu.be" {
            id = parts.first
        } else if host == "youtube.com" || host.hasSuffix(".youtube.com") {
            if components.path == "/watch" {
                id = components.queryItems?.first { $0.name == "v" }?.value
            } else if parts.count >= 2, parts[0] == "shorts" || parts[0] == "live" {
                id = parts[1]
            } else {
                id = nil
            }
        } else {
            id = nil
        }
        guard let id, videoIDPattern.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) != nil else {
            return nil
        }
        return id
    }

    /// Resolves a bare .mp3 filename inside ~/Downloads, or nil.
    static func mp3InOutputDir(_ name: String?) -> String? {
        guard let name, name.lowercased().hasSuffix(".mp3"), !name.contains("/"), name != ".mp3" else { return nil }
        let url = Tools.outputDir.appendingPathComponent(name)
        let real = url.resolvingSymlinksInPath()
        guard real.deletingLastPathComponent().path == Tools.outputDir.resolvingSymlinksInPath().path else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: real.path, isDirectory: &isDir), !isDir.boolValue else { return nil }
        return url.path
    }

    static func recentMP3s(limit: Int = 25) -> [String] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Tools.outputDir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        let mp3s = urls.filter {
            $0.pathExtension.lowercased() == "mp3" && !$0.lastPathComponent.contains(".utubmp3.tmp.")
                && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return mp3s.sorted { modified($0) > modified($1) }.prefix(limit).map(\.lastPathComponent)
    }
}
