package main

import (
	"reflect"
	"testing"
)

func TestSuggestClean(t *testing.T) {
	tags := map[string]string{
		"title":  "Samajavaragamana Full Video Song | Ala Vaikunthapurramuloo | Allu Arjun",
		"artist": "Aditya Music",
		"genre":  "Music",
		"date":   "2020",
		"description": "Song Name: Samajavaragamana\r\nMovie : Ala Vaikunthapurramuloo\n" +
			"Singer: Sid Sriram\nMusic: Thaman S\nLyrics : Sirivennela Seetharama Sastry\n" +
			"Subscribe: https://youtube.com/x\n#AlluArjun #Thaman\n℗ 2020 Aditya Music",
	}
	want := map[string]string{
		"title":     "Samajavaragamana",
		"album":     "Ala Vaikunthapurramuloo",
		"artist":    "Sid Sriram",
		"composer":  "Thaman S",
		"lyricist":  "Sirivennela Seetharama Sastry",
		"publisher": "Aditya Music",
		"copyright": "℗ 2020 Aditya Music",
		"date":      "2020",
	}
	if got := suggestClean(tags); !reflect.DeepEqual(got, want) {
		t.Errorf("suggestClean:\n got %v\nwant %v", got, want)
	}
}

func TestCleanTitle(t *testing.T) {
	for in, want := range map[string]string{
		"Butta Bomma Full Video Song (4K) | Ala Vaikunthapurramuloo": "Butta Bomma",
		"Kesariya - Lyrical | Brahmastra":                            "Kesariya",
		"Song (Official Audio)":                                      "Song",
		"Plain Title":                                                "Plain Title",
	} {
		if got := cleanTitle(in); got != want {
			t.Errorf("cleanTitle(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestParseFFMetadata(t *testing.T) {
	text := ";FFMETADATA1\r\ntitle=A \\= B\r\ndescription=line1\\\nline2\n;comment\n[CHAPTER]\ntitle=ch0\n"
	want := map[string]string{"title": "A = B", "description": "line1\nline2"}
	if got := parseFFMetadata(text); !reflect.DeepEqual(got, want) {
		t.Errorf("parseFFMetadata = %v, want %v", got, want)
	}
}

func TestVideoID(t *testing.T) {
	for in, want := range map[string]string{
		"https://www.youtube.com/watch?v=jNQXAC9IVRw&t=3": "jNQXAC9IVRw",
		"https://youtu.be/jNQXAC9IVRw":                    "jNQXAC9IVRw",
		"https://m.youtube.com/shorts/jNQXAC9IVRw":        "jNQXAC9IVRw",
		"https://music.youtube.com/watch?v=jNQXAC9IVRw":   "jNQXAC9IVRw",
		"https://evil.com/watch?v=jNQXAC9IVRw":            "",
		"https://notyoutube.com/watch?v=jNQXAC9IVRw":      "",
		"https://www.youtube.com/watch?v=short":           "",
		"https://www.youtube.com/watch?v=jNQXAC9IVRw;rm":  "",
	} {
		got, ok := videoIDFrom(in)
		if (want == "") == ok || (ok && got != want) {
			t.Errorf("videoIDFrom(%q) = %q, %v; want %q", in, got, ok, want)
		}
	}
}

func TestSafeName(t *testing.T) {
	if got := safeName(`a/b:c*?"<>| d .`); got != "a b c d" {
		t.Errorf("safeName = %q", got)
	}
}
