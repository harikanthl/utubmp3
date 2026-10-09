// utubmp3 helper for Windows: the Go port of the Mac app's background helper
// (utubmp3/Helper/*.swift). Chrome extensions can't spawn processes, so the
// extension talks to this over http://127.0.0.1:47321 and it runs yt-dlp + ffmpeg.
//
// The installer starts it at login (HKCU\...\Run) with --background. It has no
// window; it logs to %LOCALAPPDATA%\utubmp3\helper.log. Opened from the Start menu
// (no --background) it also says that it's running, so the click does something visible.
// The code is portable so it can be tested on macOS too (UTUBMP3_PORT overrides the
// port there, since the Mac helper uses it).
package main

import (
	"errors"
	"fmt"
	"log"
	"net"
	"os"
	"path/filepath"
	"slices"
)

const defaultPort = 47321

func main() {
	if err := os.MkdirAll(supportDir(), 0o755); err == nil {
		logPath := filepath.Join(supportDir(), "helper.log")
		if info, err := os.Stat(logPath); err == nil && info.Size() > 1<<20 {
			os.Remove(logPath)
		}
		if f, err := os.OpenFile(logPath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644); err == nil {
			log.SetOutput(f)
		}
	}
	log.SetPrefix("[utubmp3] ")

	interactive := !slices.Contains(os.Args[1:], "--background")
	port := defaultPort
	if p := os.Getenv("UTUBMP3_PORT"); p != "" {
		fmt.Sscan(p, &port)
	}
	listener, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		// Most likely another copy is already running (started at login and again by the installer).
		var opErr *net.OpError
		if errors.As(err, &opErr) {
			log.Printf("port %d busy, exiting: %v", port, err)
			if interactive {
				showRunningMessage()
			}
			os.Exit(0)
		}
		log.Fatalf("could not listen: %v", err)
	}
	log.Printf("helper starting on 127.0.0.1:%d (ffmpeg: %s, js: %v, downloads: %s)",
		port, ffmpegPath(), jsRuntimeArgs(), outputDir())
	go keepYtdlpUpdated()
	if interactive {
		go showRunningMessage()
	}
	log.Fatal(serve(listener, port))
}
