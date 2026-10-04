//
//  ViewController.swift
//  utubmp3
//
//  Created by harikanth lingutla on 10/3/26.
//

import Cocoa
import SafariServices
import WebKit

let extensionBundleIdentifier = "com.harikanthlingutla.utubmp3.Extension"

class ViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {

    @IBOutlet var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        self.webView.navigationDelegate = self

        self.webView.configuration.userContentController.add(self, name: "controller")

        self.webView.loadFileURL(Bundle.main.url(forResource: "Main", withExtension: "html")!, allowingReadAccessTo: Bundle.main.resourceURL!)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        installHelper(webView)

        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionBundleIdentifier) { (state, error) in
            guard let state = state, error == nil else {
                // Insert code to inform the user that something went wrong.
                return
            }

            DispatchQueue.main.async {
                if #available(macOS 13, *) {
                    webView.evaluateJavaScript("show(\(state.isEnabled), true)")
                } else {
                    webView.evaluateJavaScript("show(\(state.isEnabled), false)")
                }
            }
        }
    }

    /// Registers the background helper (yt-dlp + ffmpeg runner) and reports its status on the page.
    private func installHelper(_ webView: WKWebView) {
        Task {
            let status: String
            do {
                try await Task.detached { try HelperInstaller.install() }.value
                status = await HelperInstaller.isRunning()
                    ? "ready"
                    : "Background helper installed but not responding. Log: ~/Library/Logs/utubmp3-helper.log"
            } catch {
                status = "Couldn’t start the background helper: \(error)"
            }
            let json = (try? JSONSerialization.data(withJSONObject: [status])).flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
            _ = try? await webView.evaluateJavaScript("showHelper(...\(json))")
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if (message.body as! String != "open-preferences") {
            return;
        }

        SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleIdentifier) { error in
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }

}
