// MP3 tag cleanup / editing, done with ffmpeg (stream copy, so the audio and
// cover art are untouched). Port of utubmp3/Helper/Tags.swift.
//
//   - clean: rebuild tags from the video's title/description, dropping YouTube
//     junk (hashtags, social links, URLs, the duplicated description).
//   - edit: write user-supplied values for any field; an empty value removes it.
package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
	"unicode/utf8"
)

var editableTags = []string{"title", "artist", "album", "album_artist", "composer", "lyricist",
	"genre", "date", "track", "publisher", "copyright"}

func isEditable(key string) bool {
	for _, k := range editableTags {
		if k == key {
			return true
		}
	}
	return false
}

// "Key : Value" lines commonly found in music-video descriptions.
var descriptionKeys = map[string][]string{
	"title":  {"song", "song name", "song title", "track", "track name", "title"},
	"album":  {"movie", "movie name", "film", "film name", "album", "album name"},
	"artist": {"singer", "singers", "singer(s)", "vocals", "sung by", "artist", "artists"},
	"composer": {"music", "music director", "music directer", "composer", "music composer",
		"composed by", "music by"},
	"lyricist":  {"lyrics", "lyricist", "lyrics by", "lyric writer", "lyricists", "written by"},
	"publisher": {"label", "music label", "record label", "music on", "audio on"},
}

var keyLookup = func() map[string]string {
	lookup := map[string]string{}
	for field, aliases := range descriptionKeys {
		for _, alias := range aliases {
			lookup[alias] = field
		}
	}
	return lookup
}()

var (
	kvLine         = regexp.MustCompile(`^\s*([A-Za-z][A-Za-z ().]{1,30}?)\s*[:：]\s*(.+?)\s*$`)
	copyrightLine  = regexp.MustCompile(`(?i)[©℗]|\bcopyright\b`)
	titleSeparator = regexp.MustCompile(`\s*[|｜]\s*`)
	titleNoise     = regexp.MustCompile(`(?i)\s*[(\[][^)\]]*(official|lyric|video|audio|hd|4k|full song)[^)\]]*[)\]]` +
		`|\s+(full video song|video song|lyrical video|lyrical song|lyrical|` +
		`telugu lyrics|hindi lyrics|tamil lyrics|lyrics|full song|song)\s*$`)
	unsafeFilenameChars = regexp.MustCompile(`[/\\:*?"<>|\x00-\x1f]`)
	whitespace          = regexp.MustCompile(`\s+`)
	newlines            = regexp.MustCompile("\r\n|[\n\r\v\f\u0085  ]")
)

// MARK: - Reading

func readTags(path string) (map[string]string, error) {
	result, err := run(ffmpegPath(), []string{"-v", "error", "-i", path, "-f", "ffmetadata", "-"}, 30*time.Second)
	if err != nil {
		return nil, err
	}
	if result.status != 0 {
		return nil, errors.New(lastChars(result.stderr, 300))
	}
	return parseFFMetadata(result.stdout), nil
}

// parseFFMetadata parses ffmpeg's ffmetadata format: key=value lines where =;#\ and
// newlines are backslash-escaped. Stops at the first [SECTION].
func parseFFMetadata(text string) map[string]string {
	tags := map[string]string{}
	chars := []rune(strings.ReplaceAll(text, "\r\n", "\n"))
	// Skip the ";FFMETADATA1" header line.
	i := 0
	for i < len(chars) && chars[i] != '\n' {
		i++
	}
	i++
	for i < len(chars) {
		switch chars[i] {
		case '\n':
			i++
			continue
		case '[':
			return tags
		case ';', '#':
			for i < len(chars) && chars[i] != '\n' {
				i++
			}
			continue
		}
		var key, value strings.Builder
		inValue := false
		for i < len(chars) {
			c := chars[i]
			i++
			if c == '\\' && i < len(chars) {
				if inValue {
					value.WriteRune(chars[i])
				} else {
					key.WriteRune(chars[i])
				}
				i++
			} else if c == '=' && !inValue {
				inValue = true
			} else if c == '\n' {
				break
			} else if inValue {
				value.WriteRune(c)
			} else {
				key.WriteRune(c)
			}
		}
		if inValue {
			tags[strings.ToLower(key.String())] = value.String()
		}
	}
	return tags
}

// MARK: - Cleaning

func cleanTitle(title string) string {
	first := title
	if loc := titleSeparator.FindStringIndex(title); loc != nil {
		first = title[:loc[0]]
	}
	for previous := ""; previous != first; {
		previous = first
		first = strings.Trim(titleNoise.ReplaceAllString(first, ""), " -–—")
	}
	if first == "" {
		return title
	}
	return first
}

// suggestClean returns the tags to keep after cleaning: credits parsed from the
// description plus existing useful tags.
func suggestClean(tags map[string]string) map[string]string {
	description := ""
	for _, key := range []string{"description", "synopsis", "comment"} {
		if tags[key] != "" {
			description = tags[key]
			break
		}
	}
	parsed := map[string]string{}
	for _, line := range newlines.Split(description, -1) {
		if strings.Contains(line, "http") {
			continue
		}
		if groups := kvLine.FindStringSubmatch(line); groups != nil {
			key := strings.ToLower(strings.TrimSpace(groups[1]))
			if field, ok := keyLookup[key]; ok {
				if _, seen := parsed[field]; !seen {
					parsed[field] = groups[2]
				}
			}
		} else if _, seen := parsed["copyright"]; !seen && utf8.RuneCountInString(line) < 200 &&
			copyrightLine.MatchString(line) {
			parsed["copyright"] = strings.TrimSpace(line)
		}
	}

	clean := map[string]string{}
	for k, v := range tags {
		if isEditable(k) && v != "" {
			clean[k] = v
		}
	}
	if title, ok := parsed["title"]; ok {
		clean["title"] = title
	} else {
		clean["title"] = cleanTitle(tags["title"])
	}
	for _, field := range []string{"album", "composer", "lyricist", "copyright"} {
		if value, ok := parsed[field]; ok && tags[field] == "" {
			clean[field] = value
		}
	}
	if singers, ok := parsed["artist"]; ok {
		// yt-dlp sets artist to the uploading channel; keep that as the publisher
		// so the source isn't lost when the singers take over the artist field.
		if channel := tags["artist"]; channel != "" && clean["publisher"] == "" {
			clean["publisher"] = channel
		}
		clean["artist"] = singers
	}
	if label, ok := parsed["publisher"]; ok {
		clean["publisher"] = label
	}
	if strings.ToLower(clean["genre"]) == "music" {
		delete(clean, "genre")
	}
	for k, v := range clean {
		if v == "" {
			delete(clean, k)
		}
	}
	return clean
}

// MARK: - Writing

func safeName(text string) string {
	name := unsafeFilenameChars.ReplaceAllString(text, " ")
	name = whitespace.ReplaceAllString(name, " ")
	name = strings.Trim(name, " .")
	if r := []rune(name); len(r) > 150 {
		name = string(r[:150])
	}
	return name
}

func sameFile(a, b string) bool {
	ia, errA := os.Stat(a)
	ib, errB := os.Stat(b)
	return errA == nil && errB == nil && os.SameFile(ia, ib)
}

// writeTags replaces all tags in path with tags, then renames it from title/album.
// Returns the new path.
func writeTags(path string, tags map[string]string) (string, error) {
	tmp := path + ".utubmp3.tmp.mp3"
	args := []string{"-v", "error", "-y", "-i", path, "-map", "0", "-c", "copy",
		"-map_metadata", "-1", "-fflags", "+bitexact", "-id3v2_version", "3"}
	keys := make([]string, 0, len(tags))
	for k := range tags {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		args = append(args, "-metadata", k+"="+tags[k])
	}
	result, err := run(ffmpegPath(), append(args, tmp), 2*time.Minute)
	if err == nil && result.status != 0 {
		err = errors.New(lastChars(result.stderr, 300))
	}
	if err != nil {
		os.Remove(tmp)
		return "", err
	}

	var parts []string
	for _, k := range []string{"title", "album"} {
		if tags[k] != "" {
			parts = append(parts, tags[k])
		}
	}
	newPath := path
	if base := safeName(strings.Join(parts, " - ")); base != "" {
		dir := filepath.Dir(path)
		candidate := filepath.Join(dir, base+".mp3")
		for n := 2; isFile(candidate) && !sameFile(candidate, path); n++ {
			candidate = filepath.Join(dir, fmt.Sprintf("%s (%d).mp3", base, n))
		}
		newPath = candidate
	}
	// Replace the original in place first; a rename then covers case-only changes too.
	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
		return "", err
	}
	if newPath != path {
		if err := os.Rename(path, newPath); err != nil {
			return path, nil // tags are written; keep the old name
		}
	}
	return newPath, nil
}

func cleanTags(path string) (string, error) {
	tags, err := readTags(path)
	if err != nil {
		return "", err
	}
	return writeTags(path, suggestClean(tags))
}

func editTags(path string, values map[string]string) (string, error) {
	current, err := readTags(path)
	if err != nil {
		return "", err
	}
	tags := map[string]string{}
	for k, v := range current {
		if isEditable(k) && v != "" {
			tags[k] = v
		}
	}
	for _, key := range editableTags {
		raw, ok := values[key]
		if !ok {
			continue
		}
		value := strings.TrimSpace(raw)
		if r := []rune(value); len(r) > 500 {
			value = string(r[:500])
		}
		if value == "" {
			delete(tags, key)
		} else {
			tags[key] = value
		}
	}
	return writeTags(path, tags)
}
