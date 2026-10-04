//
//  main.swift
//  utubmp3
//
//  The same executable is both the app and its background helper:
//  launchd starts `utubmp3 --helper` at login (see HelperInstaller).
//

import Cocoa

if CommandLine.arguments.contains("--helper") {
    HelperServer.run()
} else {
    _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
}
