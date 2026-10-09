//go:build !windows

// Non-Windows stand-ins, so the helper can be run and tested on macOS.
package main

import (
	"os"
	"os/exec"
	"path/filepath"
)

const (
	exeSuffix    = ""
	ytdlpName    = "yt-dlp"
	ytdlpRelease = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
)

func supportDir() string {
	if dir := os.Getenv("UTUBMP3_SUPPORT_DIR"); dir != "" {
		return dir
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, "Library", "Application Support", "utubmp3")
}

func outputDir() string {
	if dir := os.Getenv("UTUBMP3_OUTPUT_DIR"); dir != "" {
		return dir
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, "Downloads")
}

func samePath(a, b string) bool { return filepath.Clean(a) == filepath.Clean(b) }

func hideWindow(*exec.Cmd) {}

func showRunningMessage() {}

func reveal(path string) { exec.Command("/usr/bin/open", "-R", path).Start() }

func openFolder(path string) { exec.Command("/usr/bin/open", path).Start() }
