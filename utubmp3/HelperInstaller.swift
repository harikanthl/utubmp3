//
//  HelperInstaller.swift
//  utubmp3
//
//  Registers the background helper as a per-user launch agent so it starts at
//  login and is restarted if it exits. Re-registered on every app launch, so it
//  always points at the current copy of the app.
//

import Foundation

nonisolated enum HelperInstaller {
    static let label = "com.harikanthlingutla.utubmp3.helper"
    static let plistURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/utubmp3-helper.log")

    static func install() throws {
        guard let executable = Bundle.main.executablePath else { throw ToolError.failed("no executable path") }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable, "--helper"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": logURL.path,
            "StandardErrorPath": logURL.path,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: plistURL, options: .atomic)

        // Restart so a new app version or location takes effect.
        let domain = "gui/\(getuid())"
        _ = try? Tools.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"], timeout: 15)
        var lastError = ""
        for _ in 0..<10 {  // bootout finishes asynchronously; bootstrap fails until it has
            let result = try Tools.run("/bin/launchctl", ["bootstrap", domain, plistURL.path], timeout: 15)
            if result.status == 0 { return }
            lastError = result.stderr
            Thread.sleep(forTimeInterval: 0.5)
        }
        throw ToolError.failed("launchctl bootstrap failed: \(lastError)")
    }

    /// Polls the helper's /health endpoint.
    static func isRunning() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(HelperServer.port)/health") else { return false }
        for _ in 0..<20 {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["ok"] as? Bool == true {
                return true
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }
}
