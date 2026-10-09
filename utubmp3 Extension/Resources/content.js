// Adds an "MP3" button to YouTube watch/Shorts pages and answers the popup's
// request for video info. Video-info extraction adapted from
// opalsaints/yt-dlp-chrome-extension (MIT).

const ext = globalThis.browser ?? globalThis.chrome;  // Safari / Chrome
const BUTTON_ID = "utubmp3-btn";

function currentVideoId() {
    const u = new URL(location.href);
    if (u.pathname === "/watch") return u.searchParams.get("v");
    const m = u.pathname.match(/^\/(?:shorts|live)\/([A-Za-z0-9_-]{11})/);
    return m ? m[1] : null;
}

function extractVideoInfo() {
    const videoId = currentVideoId();
    if (!videoId) return { error: "Not a YouTube video page" };

    const titleEl =
        document.querySelector("h1.ytd-watch-metadata yt-formatted-string") ||
        document.querySelector("#title h1");
    const channelEl =
        document.querySelector("ytd-watch-metadata #channel-name a") ||
        document.querySelector("#channel-name a");

    return {
        url: location.href,
        videoId,
        title: titleEl ? titleEl.textContent.trim() : document.title.replace(/ - YouTube$/, "").trim(),
        channel: channelEl ? channelEl.textContent.trim() : "",
        thumbnail: `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`,
    };
}

function setButton(btn, text, cls, disabled) {
    btn.textContent = text;
    btn.className = btn.className.replace(/\butubmp3-(done|error)\b/g, "").trim();
    if (cls) btn.classList.add(cls);
    btn.disabled = !!disabled;
}

async function startDownload(btn) {
    const videoId = currentVideoId();
    if (!videoId) return;
    setButton(btn, "⏳ Converting…", null, true);

    const start = await ext.runtime.sendMessage({ action: "download", url: location.href });
    if (start.status !== "downloading") {
        setButton(btn, "⚠️ MP3", "utubmp3-error");
        btn.title = start.message || "Download failed";
        return;
    }

    while (true) {
        await new Promise((r) => setTimeout(r, 1500));
        const job = await ext.runtime.sendMessage({ action: "status", id: start.id });
        if (job.status === "downloading") continue;
        // The user may have navigated to another video meanwhile; only touch our button if it's the same one.
        if (currentVideoId() !== videoId) return;
        if (job.status === "complete") {
            setButton(btn, "✅ Saved", "utubmp3-done");
            btn.title = job.filename + " — click to show in Finder";
            btn.onclick = () => ext.runtime.sendMessage({ action: "reveal", id: start.id });
        } else {
            setButton(btn, "⚠️ MP3", "utubmp3-error");
            btn.title = job.message || "Download failed";
        }
        return;
    }
}

function ensureButton() {
    const videoId = currentVideoId();
    let btn = document.getElementById(BUTTON_ID);

    if (!videoId) {
        btn?.remove();
        return;
    }
    // New video: reset the button.
    if (btn && btn.dataset.videoId !== videoId) {
        btn.remove();
        btn = null;
    }

    // Prefer sitting next to Like/Share on watch pages; float elsewhere (e.g. Shorts).
    const anchor = document.querySelector("ytd-watch-metadata #top-level-buttons-computed");
    if (btn) {
        if (anchor && btn.classList.contains("utubmp3-floating")) {
            btn.classList.remove("utubmp3-floating");
            anchor.appendChild(btn);
        }
        return;
    }

    btn = document.createElement("button");
    btn.id = BUTTON_ID;
    btn.dataset.videoId = videoId;
    btn.title = "Download audio as MP3";
    setButton(btn, "⬇ MP3");
    btn.onclick = () => startDownload(btn);

    if (anchor) {
        anchor.appendChild(btn);
    } else {
        btn.classList.add("utubmp3-floating");
        document.body.appendChild(btn);
    }
}

// YouTube is a single-page app: re-check on its navigation event and on DOM changes.
document.addEventListener("yt-navigate-finish", ensureButton);
let pending = false;
new MutationObserver(() => {
    if (pending) return;
    pending = true;
    requestAnimationFrame(() => { pending = false; ensureButton(); });
}).observe(document.documentElement, { childList: true, subtree: true });
ensureButton();

ext.runtime.onMessage.addListener((request, sender, sendResponse) => {
    if (request.action === "getVideoInfo") sendResponse(extractVideoInfo());
});
