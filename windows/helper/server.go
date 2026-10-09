package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"mime"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
)

const maxRequestSize = 64 * 1024

var (
	jobsMu sync.Mutex
	jobs   = map[string]map[string]any{}
)

func serve(listener net.Listener, port int) error {
	server := &http.Server{
		Handler:           handler(port),
		ReadHeaderTimeout: 10 * time.Second,
	}
	return server.Serve(listener)
}

// isWebOrigin: requests from ordinary web pages carry an http(s) Origin; the extension's don't.
func isWebOrigin(origin string) bool {
	return strings.HasPrefix(origin, "http://") || strings.HasPrefix(origin, "https://")
}

func handler(port int) http.Handler {
	localHosts := map[string]bool{
		fmt.Sprintf("127.0.0.1:%d", port): true,
		fmt.Sprintf("localhost:%d", port): true,
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Connection", "close")
		origin := r.Header.Get("Origin")
		// Only the extension (non-http origin) gets CORS access; web pages are refused below.
		if origin != "" && !isWebOrigin(origin) {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		status, body := handle(r, localHosts)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		json.NewEncoder(w).Encode(body)
	})
}

func errorJSON(status int, message string) (int, map[string]any) {
	return status, map[string]any{"status": "error", "message": message}
}

func handle(r *http.Request, localHosts map[string]bool) (int, map[string]any) {
	// Blocks DNS rebinding: a page whose domain resolves to 127.0.0.1 sends its own Host.
	if !localHosts[r.Host] {
		return errorJSON(403, "forbidden")
	}
	if isWebOrigin(r.Header.Get("Origin")) {
		return errorJSON(403, "forbidden")
	}
	body := map[string]any{}
	if r.Method == http.MethodPost {
		if mediaType, _, _ := mime.ParseMediaType(r.Header.Get("Content-Type")); mediaType != "application/json" {
			return errorJSON(415, "expected application/json")
		}
		data, err := io.ReadAll(io.LimitReader(r.Body, maxRequestSize+1))
		if err != nil || len(data) > maxRequestSize {
			return errorJSON(400, "request too large")
		}
		json.Unmarshal(data, &body)
	}
	query := r.URL.Query()

	switch r.Method + " " + r.URL.Path {
	case "GET /health":
		return 200, map[string]any{
			"ok":     true,
			"app":    "utubmp3",
			"ytdlp":  isFile(ytdlpPath()),
			"ffmpeg": isFile(ffmpegPath()),
		}

	case "GET /status":
		jobsMu.Lock()
		job, ok := jobs[query.Get("id")]
		var copied map[string]any
		if ok {
			copied = make(map[string]any, len(job))
			for k, v := range job {
				copied[k] = v
			}
		}
		jobsMu.Unlock()
		if !ok {
			return errorJSON(404, "unknown job")
		}
		return 200, copied

	case "GET /files":
		return 200, map[string]any{"files": recentMP3s(25)}

	case "GET /tags":
		path, ok := mp3InOutputDir(query.Get("name"))
		if !ok {
			return errorJSON(404, "file not found")
		}
		current, err := readTags(path)
		if err != nil {
			return errorJSON(500, err.Error())
		}
		tags := map[string]string{}
		for _, key := range editableTags {
			tags[key] = current[key]
		}
		return 200, map[string]any{"tags": tags}

	case "POST /download":
		raw, _ := body["url"].(string)
		videoID, ok := videoIDFrom(raw)
		if !ok {
			return errorJSON(400, "Not a YouTube video URL")
		}
		id := newJobID()
		setJob(id, map[string]any{"status": "downloading", "videoId": videoID})
		go runJob(id, videoID)
		return 200, map[string]any{"status": "downloading", "id": id}

	case "POST /clean", "POST /edit":
		name, _ := body["name"].(string)
		path, ok := mp3InOutputDir(name)
		if !ok {
			return errorJSON(404, "file not found")
		}
		var newPath string
		var err error
		if r.URL.Path == "/clean" {
			newPath, err = cleanTags(path)
		} else {
			values := map[string]string{}
			if raw, ok := body["tags"].(map[string]any); ok {
				for k, v := range raw {
					if v != nil {
						values[k] = fmt.Sprint(v)
					}
				}
			}
			newPath, err = editTags(path, values)
		}
		if err != nil {
			return errorJSON(500, err.Error())
		}
		return 200, map[string]any{"status": "ok", "name": filepath.Base(newPath)}

	case "POST /reveal":
		var path string
		if name, ok := body["name"].(string); ok {
			path, _ = mp3InOutputDir(name)
		} else {
			id, _ := body["id"].(string)
			jobsMu.Lock()
			path, _ = jobs[id]["filepath"].(string)
			jobsMu.Unlock()
		}
		if isFile(path) {
			reveal(path)
		} else {
			openFolder(outputDir())
		}
		return 200, map[string]any{"status": "ok"}
	}
	return errorJSON(404, "not found")
}

// MARK: - Jobs

func newJobID() string {
	b := make([]byte, 16)
	rand.Read(b)
	return hex.EncodeToString(b)
}

func setJob(id string, update map[string]any) {
	jobsMu.Lock()
	defer jobsMu.Unlock()
	if jobs[id] == nil {
		jobs[id] = map[string]any{}
	}
	for k, v := range update {
		jobs[id][k] = v
	}
}

func lastChars(s string, n int) string {
	r := []rune(s)
	if len(r) > n {
		r = r[len(r)-n:]
	}
	return string(r)
}

func runJob(id, videoID string) {
	if err := ensureYtdlp(); err != nil {
		setJob(id, map[string]any{"status": "error", "message": err.Error()})
		return
	}
	if err := os.MkdirAll(outputDir(), 0o755); err != nil {
		setJob(id, map[string]any{"status": "error", "message": err.Error()})
		return
	}
	args := []string{
		"--no-playlist",
		"--ffmpeg-location", ffmpegPath(),
		"-f", "bestaudio/best",
		"--extract-audio",
		"--audio-format", "mp3",
		"--audio-quality", "0",
		"--embed-thumbnail",
		"--embed-metadata",
	}
	args = append(args, jsRuntimeArgs()...)
	args = append(args,
		"--no-simulate",
		"--print", "after_move:filepath",
		"-o", filepath.Join(outputDir(), "%(title)s.%(ext)s"),
		"https://www.youtube.com/watch?v="+videoID,
	)
	result, err := run(ytdlpPath(), args, 15*time.Minute)
	if err == nil && result.status != 0 {
		// YouTube changes often break yt-dlp between daily updates: update and retry once.
		log.Print("download failed, updating yt-dlp and retrying")
		updateYtdlp()
		result, err = run(ytdlpPath(), args, 15*time.Minute)
	}
	if err == errTimedOut {
		setJob(id, map[string]any{"status": "error", "message": "Download timed out (15 min limit)"})
		return
	}
	if err != nil {
		setJob(id, map[string]any{"status": "error", "message": err.Error()})
		return
	}
	if result.status != 0 {
		message := result.stderr
		if strings.TrimSpace(message) == "" {
			message = result.stdout
		}
		setJob(id, map[string]any{"status": "error", "message": lastChars(strings.TrimSpace(message), 300)})
		return
	}

	lines := strings.Split(strings.TrimRight(result.stdout, "\r\n"), "\n")
	path := strings.TrimSpace(lines[len(lines)-1])
	if path != "" {
		// Auto-clean every download; keep the file even if cleaning fails.
		if cleaned, err := cleanTags(path); err == nil {
			path = cleaned
		} else {
			log.Printf("auto-clean failed: %v", err)
		}
	}
	filename := "download complete"
	if path != "" {
		filename = filepath.Base(path)
	}
	setJob(id, map[string]any{"status": "complete", "filepath": path, "filename": filename})
}

// MARK: - Validation

var videoIDPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{11}$`)

// videoIDFrom returns the 11-char video id for a youtube.com / youtu.be URL.
func videoIDFrom(raw string) (string, bool) {
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		return "", false
	}
	host := strings.ToLower(u.Hostname())
	var parts []string
	for _, p := range strings.Split(u.Path, "/") {
		if p != "" {
			parts = append(parts, p)
		}
	}
	id := ""
	switch {
	case host == "youtu.be":
		if len(parts) > 0 {
			id = parts[0]
		}
	case host == "youtube.com" || strings.HasSuffix(host, ".youtube.com"):
		if u.Path == "/watch" {
			id = u.Query().Get("v")
		} else if len(parts) >= 2 && (parts[0] == "shorts" || parts[0] == "live") {
			id = parts[1]
		}
	}
	return id, videoIDPattern.MatchString(id)
}

// mp3InOutputDir resolves a bare .mp3 filename inside the Downloads folder.
func mp3InOutputDir(name string) (string, bool) {
	if !strings.HasSuffix(strings.ToLower(name), ".mp3") || strings.ContainsAny(name, `/\:`) ||
		name == ".mp3" || name == "" {
		return "", false
	}
	path := filepath.Join(outputDir(), name)
	real, err := filepath.EvalSymlinks(path)
	if err != nil {
		return "", false
	}
	dir, err := filepath.EvalSymlinks(outputDir())
	if err != nil || !samePath(filepath.Dir(real), dir) {
		return "", false
	}
	if !isFile(real) {
		return "", false
	}
	return path, true
}

func recentMP3s(limit int) []string {
	entries, _ := os.ReadDir(outputDir())
	type file struct {
		name     string
		modified time.Time
	}
	var mp3s []file
	for _, e := range entries {
		name := e.Name()
		if strings.HasPrefix(name, ".") || !strings.EqualFold(filepath.Ext(name), ".mp3") ||
			strings.Contains(name, ".utubmp3.tmp.") {
			continue
		}
		info, err := e.Info()
		if err != nil || !info.Mode().IsRegular() {
			continue
		}
		mp3s = append(mp3s, file{name, info.ModTime()})
	}
	sort.Slice(mp3s, func(i, j int) bool { return mp3s[i].modified.After(mp3s[j].modified) })
	names := []string{}
	for i, f := range mp3s {
		if i == limit {
			break
		}
		names = append(names, f.name)
	}
	return names
}

func isFile(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular()
}
