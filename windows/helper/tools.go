package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// yt-dlp is downloaded at runtime (not bundled) so it can self-update:
// YouTube breaks old versions regularly.
const updateInterval = 24 * time.Hour

var errTimedOut = errors.New("timed out")

func ytdlpPath() string { return filepath.Join(supportDir(), "bin", ytdlpName) }

// bundled returns a tool shipped next to the helper executable, if present.
func bundled(name string) string {
	exe, err := os.Executable()
	if err != nil {
		return ""
	}
	if resolved, err := filepath.EvalSymlinks(exe); err == nil {
		exe = resolved
	}
	path := filepath.Join(filepath.Dir(exe), name+exeSuffix)
	if isFile(path) {
		return path
	}
	return ""
}

func firstExecutable(paths ...string) string {
	for _, p := range paths {
		if p != "" && isFile(p) {
			return p
		}
	}
	return ""
}

func lookPath(name string) string {
	path, _ := exec.LookPath(name)
	return path
}

func ffmpegPath() string {
	if p := firstExecutable(bundled("ffmpeg"), lookPath("ffmpeg")); p != "" {
		return p
	}
	return "ffmpeg"
}

// jsRuntimeArgs are yt-dlp's --js-runtimes arguments: it needs a JS runtime to solve
// YouTube's challenges (without one: 403s and missing formats). A system deno/node is
// faster; the bundled QuickJS always works as a fallback.
func jsRuntimeArgs() []string {
	var args []string
	home, _ := os.UserHomeDir()
	if deno := firstExecutable(filepath.Join(home, ".deno", "bin", "deno"+exeSuffix), lookPath("deno")); deno != "" {
		args = append(args, "--js-runtimes", "deno:"+deno)
	}
	if node := lookPath("node"); node != "" {
		args = append(args, "--js-runtimes", "node:"+node)
	}
	if qjs := bundled("qjs"); qjs != "" {
		args = append(args, "--js-runtimes", "quickjs:"+qjs)
	}
	return args
}

// MARK: - yt-dlp install / update

var installMu, updateMu sync.Mutex

// ensureYtdlp downloads the standalone yt-dlp if it isn't installed yet.
func ensureYtdlp() error {
	installMu.Lock()
	defer installMu.Unlock()
	path := ytdlpPath()
	if isFile(path) {
		return nil
	}
	log.Printf("yt-dlp missing, downloading %s", ytdlpRelease)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	resp, err := http.Get(ytdlpRelease)
	if err != nil {
		return fmt.Errorf("yt-dlp download failed: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("yt-dlp download failed: HTTP %d", resp.StatusCode)
	}
	part := path + ".part"
	f, err := os.OpenFile(part, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o755)
	if err != nil {
		return err
	}
	_, err = io.Copy(f, resp.Body)
	if closeErr := f.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		os.Remove(part)
		return fmt.Errorf("yt-dlp download failed: %w", err)
	}
	return os.Rename(part, path)
}

// updateYtdlp installs yt-dlp if needed and runs `yt-dlp -U`. Serialized, so the
// daily update and a retry after a failed download don't both replace the binary.
func updateYtdlp() {
	updateMu.Lock()
	defer updateMu.Unlock()
	if err := ensureYtdlp(); err != nil {
		log.Printf("yt-dlp update failed: %v", err)
		return
	}
	result, err := run(ytdlpPath(), []string{"-U"}, 5*time.Minute)
	if err != nil {
		log.Printf("yt-dlp update failed: %v", err)
		return
	}
	lines := strings.Split(strings.TrimSpace(result.stdout+result.stderr), "\n")
	log.Printf("yt-dlp -U: %s", strings.TrimSpace(lines[len(lines)-1]))
}

// keepYtdlpUpdated updates yt-dlp now and once a day.
func keepYtdlpUpdated() {
	for {
		updateYtdlp()
		time.Sleep(updateInterval)
	}
}

// MARK: - Subprocesses

type processResult struct {
	status         int
	stdout, stderr string
}

func run(executable string, args []string, timeout time.Duration) (processResult, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, executable, args...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	// yt-dlp is Python: make it print paths as UTF-8 instead of the Windows code page.
	cmd.Env = append(os.Environ(), "PYTHONUTF8=1", "PYTHONIOENCODING=utf-8")
	hideWindow(cmd)
	err := cmd.Run()
	if ctx.Err() == context.DeadlineExceeded {
		return processResult{}, errTimedOut
	}
	var exitErr *exec.ExitError
	if err != nil && !errors.As(err, &exitErr) {
		return processResult{}, err
	}
	return processResult{cmd.ProcessState.ExitCode(), stdout.String(), stderr.String()}, nil
}
