// Relays requests from the content script and popup to the local helper
// (helper/utubmp3_helper.py), which runs yt-dlp + ffmpeg.
const HELPER = "http://127.0.0.1:8765";

async function call(path, body) {
    try {
        const res = await fetch(HELPER + path, body === undefined ? {} : {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(body),
        });
        return await res.json();
    } catch (e) {
        return {
            status: "error",
            message: "Helper not running. Start it with: python3 helper/utubmp3_helper.py",
        };
    }
}

browser.runtime.onMessage.addListener((request) => {
    switch (request.action) {
        case "health":   return call("/health");
        case "download": return call("/download", { url: request.url });
        case "status":   return call("/status?id=" + encodeURIComponent(request.id));
        case "reveal":   return call("/reveal", { id: request.id, name: request.name });
        case "files":    return call("/files");
        case "tags":     return call("/tags?name=" + encodeURIComponent(request.name));
        case "clean":    return call("/clean", { name: request.name });
        case "edit":     return call("/edit", { name: request.name, tags: request.tags });
    }
});
