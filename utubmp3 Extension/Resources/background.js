// Relays requests from the content script and popup to the local helper
// (the utubmp3 app running with --helper), which runs yt-dlp + ffmpeg.
// Safari exposes `browser`, Chrome `chrome`; both support promises in MV3.
const ext = globalThis.browser ?? globalThis.chrome;

const HELPER = "http://127.0.0.1:47321";

async function call(path, body) {
    try {
        const res = await fetch(HELPER + path, body === undefined ? {} : {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(body),
        });
        const json = await res.json();
        // Something else may be listening on the port; only trust our own helper.
        if (path === "/health" && json.app !== "utubmp3") throw new Error("not utubmp3");
        return json;
    } catch (e) {
        return {
            status: "error",
            message: "Helper not running. Open the utubmp3 app once to start it.",
        };
    }
}

function route(request) {
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
}

ext.runtime.onMessage.addListener((request, sender, sendResponse) => {
    const reply = route(request);
    if (!reply) return false;
    reply.then(sendResponse);
    return true;  // keep the channel open for the async reply
});
