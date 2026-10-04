// Popup flow adapted from opalsaints/yt-dlp-chrome-extension (MIT).
const $ = (id) => document.getElementById(id);

function setStatus(type, message) {
    const s = $("status");
    s.hidden = false;
    s.className = type;
    s.textContent = message;
}

function videoIdFromUrl(url) {
    const m = url && url.match(/(?:[?&]v=|\/shorts\/|\/live\/)([A-Za-z0-9_-]{11})/);
    return m ? m[1] : null;
}

async function loadVideo(tab) {
    try {
        const info = await browser.tabs.sendMessage(tab.id, { action: "getVideoInfo" });
        if (info && !info.error) return info;
    } catch (e) { /* content script not ready; fall back to tab data */ }
    const videoId = videoIdFromUrl(tab.url);
    if (!videoId) return null;
    return {
        url: tab.url,
        videoId,
        title: (tab.title || "").replace(/ - YouTube$/, ""),
        channel: "",
        thumbnail: `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`,
    };
}

async function checkHelper() {
    const h = await browser.runtime.sendMessage({ action: "health" });
    if (h.ok) {
        $("helper").textContent = h.ytdlp && h.ffmpeg
            ? "Helper running · saves to ~/Downloads"
            : "Helper running, but yt-dlp or ffmpeg is missing (restart the helper; brew install ffmpeg)";
    } else {
        $("helper").textContent = h.message;
    }
}

async function download(url) {
    const btn = $("download");
    btn.disabled = true;
    setStatus("downloading", "Downloading and converting…");

    const start = await browser.runtime.sendMessage({ action: "download", url });
    if (start.status !== "downloading") {
        btn.disabled = false;
        setStatus("error", start.message || "Download failed");
        return;
    }

    let job;
    do {
        await new Promise((r) => setTimeout(r, 1500));
        job = await browser.runtime.sendMessage({ action: "status", id: start.id });
    } while (job.status === "downloading");

    btn.disabled = false;
    if (job.status === "complete") {
        setStatus("complete", "Saved: " + job.filename);
        loadFiles();
        const reveal = document.createElement("button");
        reveal.className = "secondary";
        reveal.textContent = "Show in Finder";
        reveal.onclick = () => browser.runtime.sendMessage({ action: "reveal", id: start.id });
        $("status").appendChild(reveal);
    } else {
        setStatus("error", job.message || "Download failed");
    }
}

const LABELS = {
    title: "Title", artist: "Artist", album: "Album", album_artist: "Album artist",
    composer: "Composer", lyricist: "Lyricist", genre: "Genre", date: "Year",
    track: "Track #", publisher: "Publisher / label", copyright: "Copyright",
};

function button(text, onclick, cls) {
    const b = document.createElement("button");
    b.textContent = text;
    if (cls) b.className = cls;
    b.onclick = onclick;
    return b;
}

async function loadFiles() {
    const res = await browser.runtime.sendMessage({ action: "files" });
    const list = $("files");
    list.textContent = "";
    if (!res.files || res.files.length === 0) {
        const li = document.createElement("li");
        li.className = "empty";
        li.textContent = res.files ? "No MP3s in ~/Downloads yet." : "";
        list.appendChild(li);
        return;
    }
    for (const name of res.files) {
        const li = document.createElement("li");
        const label = document.createElement("span");
        label.className = "name";
        label.textContent = name;
        label.title = name;
        li.append(
            label,
            button("Clean", () => cleanFile(name), "secondary"),
            button("Edit", () => openEditor(name), "secondary"),
        );
        list.appendChild(li);
    }
}

async function cleanFile(name) {
    setStatus("downloading", "Cleaning tags…");
    const res = await browser.runtime.sendMessage({ action: "clean", name });
    if (res.status === "ok") {
        setStatus("complete", "Cleaned: " + res.name);
        loadFiles();
    } else {
        setStatus("error", res.message || "Clean failed");
    }
}

async function openEditor(name) {
    const res = await browser.runtime.sendMessage({ action: "tags", name });
    if (!res.tags) {
        setStatus("error", res.message || "Could not read tags");
        return;
    }
    const fields = $("fields");
    fields.textContent = "";
    for (const [key, value] of Object.entries(res.tags)) {
        const label = document.createElement("label");
        label.textContent = LABELS[key] || key;
        const input = document.createElement("input");
        input.name = key;
        input.value = value;
        label.appendChild(input);
        fields.appendChild(label);
    }
    $("editor-name").textContent = name;
    $("editor").dataset.name = name;
    $("editor").hidden = false;
    $("editor").scrollIntoView({ behavior: "smooth" });
}

async function saveEditor(event) {
    event.preventDefault();
    const form = $("editor");
    const tags = Object.fromEntries(new FormData(form));
    setStatus("downloading", "Saving tags…");
    const res = await browser.runtime.sendMessage({ action: "edit", name: form.dataset.name, tags });
    if (res.status === "ok") {
        form.hidden = true;
        setStatus("complete", "Saved: " + res.name);
        loadFiles();
    } else {
        setStatus("error", res.message || "Save failed");
    }
}

document.addEventListener("DOMContentLoaded", async () => {
    checkHelper();
    loadFiles();
    $("editor").onsubmit = saveEditor;
    $("cancel").onclick = () => { $("editor").hidden = true; };
    const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
    const info = tab && /(^|\.)youtube\.com$/.test(new URL(tab.url || "about:blank").hostname)
        ? await loadVideo(tab)
        : null;

    if (!info) {
        $("not-youtube").hidden = false;
        return;
    }
    $("video").hidden = false;
    $("thumb").src = info.thumbnail;
    $("title").textContent = info.title;
    $("channel").textContent = info.channel;
    $("download").onclick = () => download(info.url);
});
