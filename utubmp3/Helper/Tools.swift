//
//  Tools.swift
//  utubmp3
//
//  Locates the external tools the helper runs (yt-dlp, ffmpeg, a JS runtime)
//  and runs them as subprocesses.
//

import Foundation

nonisolated struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

nonisolated enum ToolError: Error, CustomStringConvertible {
    case timedOut
    case failed(String)

    var description: String {
        switch self {
        case .timedOut: return "timed out"
        case .failed(let message): return message
        }
    }
}

nonisolated enum Tools {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let outputDir = home.appendingPathComponent("Downloads", isDirectory: true)
    static let supportDir = home.appendingPathComponent("Library/Application Support/utubmp3", isDirectory: true)

    /// yt-dlp is downloaded at runtime (not bundled) so it can self-update:
    /// YouTube breaks old versions regularly.
    static let ytdlp = supportDir.appendingPathComponent("bin/yt-dlp")
    static let ytdlpRelease = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
    static let updateInterval: TimeInterval = 24 * 60 * 60

    static func bundled(_ name: String) -> String? {
        (Bundle.main.url(forResource: name, withExtension: nil)
            ?? Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "bin"))?.path
    }

    static func firstExecutable(_ paths: [String]) -> String? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var ffmpeg: String {
        bundled("ffmpeg") ?? firstExecutable(["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]) ?? "ffmpeg"
    }

    /// `--js-runtimes` arguments for yt-dlp, which needs a JS runtime to solve
    /// YouTube's challenges (without one: 403s and missing formats). A system
    /// deno/node is faster; the bundled QuickJS always works as a fallback.
    static var jsRuntimeArgs: [String] {
        var runtimes: [String] = []
        if let deno = firstExecutable(["\(home.path)/.deno/bin/deno", "/opt/homebrew/bin/deno", "/usr/local/bin/deno"]) {
            runtimes.append("deno:\(deno)")
        }
        if let node = firstExecutable(["/opt/homebrew/bin/node", "/usr/local/bin/node"]) {
            runtimes.append("node:\(node)")
        }
        if let qjs = bundled("qjs") {
            runtimes.append("quickjs:\(qjs)")
        }
        return runtimes.flatMap { ["--js-runtimes", $0] }
    }

    // MARK: - yt-dlp install / update

    private static let installLock = NSLock()

    /// Downloads the standalone yt-dlp if it isn't installed yet.
    static func ensureYtdlp() throws {
        installLock.lock()
        defer { installLock.unlock() }
        if FileManager.default.isExecutableFile(atPath: ytdlp.path) { return }

        helperLog("yt-dlp missing, downloading \(ytdlpRelease)")
        try FileManager.default.createDirectory(at: ytdlp.deletingLastPathComponent(), withIntermediateDirectories: true)
        let part = ytdlp.appendingPathExtension("part")

        let done = DispatchSemaphore(value: 0)
        var failure: Error?
        URLSession.shared.downloadTask(with: ytdlpRelease) { location, response, error in
            defer { done.signal() }
            if let error { failure = error; return }
            guard let location, (response as? HTTPURLResponse)?.statusCode == 200 else {
                failure = ToolError.failed("yt-dlp download failed")
                return
            }
            do {
                try? FileManager.default.removeItem(at: part)
                try FileManager.default.moveItem(at: location, to: part)
            } catch {
                failure = error
            }
        }.resume()
        done.wait()
        if let failure { throw failure }

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: part.path)
        _ = try FileManager.default.replaceItemAt(ytdlp, withItemAt: part)
    }

    /// Installs yt-dlp if needed, then runs `yt-dlp -U` now and once a day.
    static func keepYtdlpUpdated() {
        Thread.detachNewThread {
            while true {
                do {
                    try ensureYtdlp()
                    let result = try run(ytdlp.path, ["-U"], timeout: 300)
                    let lines = (result.stdout + result.stderr).split(separator: "\n")
                    helperLog("yt-dlp -U: \(lines.last.map(String.init) ?? "exit \(result.status)")")
                } catch {
                    helperLog("yt-dlp update failed: \(error)")
                }
                Thread.sleep(forTimeInterval: updateInterval)
            }
        }
    }

    // MARK: - Subprocesses

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()

        // Drain both pipes concurrently so a chatty process can't fill one and block.
        var errData = Data()
        let errDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            errData = err.fileHandleForReading.readDataToEndOfFile()
            errDone.signal()
        }
        var timedOut = false
        let killer = DispatchWorkItem {
            timedOut = true
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

        let outData = out.fileHandleForReading.readDataToEndOfFile()
        errDone.wait()
        process.waitUntilExit()
        killer.cancel()
        if timedOut { throw ToolError.timedOut }

        return ProcessResult(status: process.terminationStatus,
                             stdout: String(decoding: outData, as: UTF8.self),
                             stderr: String(decoding: errData, as: UTF8.self))
    }
}

nonisolated func helperLog(_ message: String) {
    let line = "[utubmp3] \(message)\n"
    FileHandle.standardError.write(Data(line.utf8))
}
