package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

const (
	exeSuffix    = ".exe"
	ytdlpName    = "yt-dlp.exe"
	ytdlpRelease = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
)

// supportDir is %LOCALAPPDATA%\utubmp3 (yt-dlp, log).
func supportDir() string {
	if dir := os.Getenv("LOCALAPPDATA"); dir != "" {
		return filepath.Join(dir, "utubmp3")
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, "AppData", "Local", "utubmp3")
}

var (
	shell32                  = syscall.NewLazyDLL("shell32.dll")
	ole32                    = syscall.NewLazyDLL("ole32.dll")
	procSHGetKnownFolderPath = shell32.NewProc("SHGetKnownFolderPath")
	procCoTaskMemFree        = ole32.NewProc("CoTaskMemFree")
	procMessageBoxW          = syscall.NewLazyDLL("user32.dll").NewProc("MessageBoxW")
	// FOLDERID_Downloads {374DE290-123F-4565-9164-39C4925E467B}
	folderIDDownloads = syscall.GUID{Data1: 0x374DE290, Data2: 0x123F, Data3: 0x4565,
		Data4: [8]byte{0x91, 0x64, 0x39, 0xC4, 0x92, 0x5E, 0x46, 0x7B}}
)

// outputDir is the user's Downloads folder, wherever they moved it.
func outputDir() string {
	var ptr *uint16
	r, _, _ := procSHGetKnownFolderPath.Call(uintptr(unsafe.Pointer(&folderIDDownloads)), 0, 0,
		uintptr(unsafe.Pointer(&ptr)))
	if r == 0 && ptr != nil {
		defer procCoTaskMemFree.Call(uintptr(unsafe.Pointer(ptr)))
		n := 0
		for *(*uint16)(unsafe.Add(unsafe.Pointer(ptr), n*2)) != 0 {
			n++
		}
		return syscall.UTF16ToString(unsafe.Slice(ptr, n))
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, "Downloads")
}

func samePath(a, b string) bool { return strings.EqualFold(filepath.Clean(a), filepath.Clean(b)) }

const createNoWindow = 0x08000000

// hideWindow keeps console tools (yt-dlp, ffmpeg) from flashing a window.
func hideWindow(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: createNoWindow}
}

// reveal opens Explorer with the file selected.
func reveal(path string) {
	explorer := filepath.Join(os.Getenv("WINDIR"), "explorer.exe")
	cmd := exec.Command(explorer)
	// Explorer parses its own command line: /select,"path" must not be re-quoted by Go.
	cmd.SysProcAttr = &syscall.SysProcAttr{CmdLine: `"` + explorer + `" /select,"` + path + `"`}
	cmd.Start()
	go cmd.Wait()
}

func openFolder(path string) {
	cmd := exec.Command(filepath.Join(os.Getenv("WINDIR"), "explorer.exe"), path)
	cmd.Start()
	go cmd.Wait()
}

// showRunningMessage tells someone who opened utubmp3 from the Start menu that it works
// in the background.
func showRunningMessage() {
	const mbIconInformation, mbSetForeground = 0x40, 0x10000
	text, _ := syscall.UTF16PtrFromString("utubmp3 is running in the background.\n\n" +
		"Open a YouTube video in Chrome or Edge and click \u2B07 MP3. " +
		"MP3s are saved to your Downloads folder.")
	title, _ := syscall.UTF16PtrFromString("utubmp3")
	procMessageBoxW.Call(0, uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(title)),
		mbIconInformation|mbSetForeground)
}
