// Serein Companion Safari Extension - Background Script

function flashBadge(tabId, text) {
    if (!tabId || !browser.browserAction || !browser.browserAction.setBadgeText) return;
    try {
        browser.browserAction.setBadgeText({ text: text, tabId: tabId });
        browser.browserAction.setBadgeBackgroundColor({ color: "#10B981", tabId: tabId });
        setTimeout(() => {
            try {
                browser.browserAction.setBadgeText({ text: "", tabId: tabId });
            } catch (e) {}
        }, 1800);
    } catch (e) {}
}

function sendToSerein(url, time, tabId) {
    if (!url) return;
    const cleanUrl = url.trim();
    if (cleanUrl.startsWith("safari-") || cleanUrl.startsWith("about:")) return;

    if (tabId) {
        flashBadge(tabId, "▶");
    }

    // Try native messaging first
    browser.runtime.sendNativeMessage("application.id", {
        action: "openMedia",
        url: cleanUrl,
        time: time || 0
    }, (response) => {
        const err = (typeof chrome !== "undefined" && chrome.runtime && chrome.runtime.lastError) ||
                    (typeof browser !== "undefined" && browser.runtime && browser.runtime.lastError);
        
        if (err) {
            console.log("[Serein] Native message fallback to URL scheme:", err);
            // Fallback: trigger custom URL scheme in tab
            const encoded = encodeURIComponent(cleanUrl);
            const schemeUrl = `serein://open?url=${encoded}&time=${time || 0}`;
            if (tabId && browser.tabs && browser.tabs.executeScript) {
                browser.tabs.executeScript(tabId, {
                    code: `window.location.href = ${JSON.stringify(schemeUrl)};`
                });
            }
        }
    });
}

function captureAndSend(tab) {
    if (!tab || !tab.id) return;

    const scriptCode = `
    (function() {
        let videos = Array.from(document.querySelectorAll('video'));
        let audios = Array.from(document.querySelectorAll('audio'));
        let allMedia = videos.concat(audios);
        let activeMedia = null;

        // Find playing media first
        for (let m of allMedia) {
            if (!m.paused && m.currentTime > 0) {
                activeMedia = m;
                break;
            }
        }
        // Otherwise find media with progress
        if (!activeMedia) {
            for (let m of allMedia) {
                if (m.currentTime > 0) {
                    activeMedia = m;
                    break;
                }
            }
        }
        // Otherwise pick the media with duration
        if (!activeMedia && allMedia.length > 0) {
            activeMedia = allMedia.reduce((a, b) => ((b.duration || 0) > (a.duration || 0) ? b : a), allMedia[0]);
        }

        let time = 0;
        if (activeMedia) {
            time = Math.floor(activeMedia.currentTime || 0);
            try {
                activeMedia.pause();
            } catch (e) {}
        }

        return {
            url: window.location.href,
            time: time
        };
    })();
    `;

    browser.tabs.executeScript(tab.id, { code: scriptCode }, (results) => {
        let pageUrl = tab.url;
        let time = 0;

        const err = (typeof chrome !== "undefined" && chrome.runtime && chrome.runtime.lastError) ||
                    (typeof browser !== "undefined" && browser.runtime && browser.runtime.lastError);

        if (!err && results && results[0]) {
            if (results[0].url) pageUrl = results[0].url;
            if (results[0].time) time = results[0].time;
        }

        if (pageUrl) {
            sendToSerein(pageUrl, time, tab.id);
        }
    });
}

// Click on Toolbar Icon
if (browser.browserAction && browser.browserAction.onClicked) {
    browser.browserAction.onClicked.addListener((tab) => {
        captureAndSend(tab);
    });
}

// Context Menu Items
browser.runtime.onInstalled.addListener(() => {
    if (browser.contextMenus && browser.contextMenus.create) {
        browser.contextMenus.create({
            id: "serein-play-page",
            title: "Play Page in Serein",
            contexts: ["page", "video", "audio"]
        });
        browser.contextMenus.create({
            id: "serein-play-link",
            title: "Play Link in Serein",
            contexts: ["link"]
        });
    }
});

if (browser.contextMenus && browser.contextMenus.onClicked) {
    browser.contextMenus.onClicked.addListener((info, tab) => {
        if (info.menuItemId === "serein-play-link" && info.linkUrl) {
            sendToSerein(info.linkUrl, 0, tab ? tab.id : null);
        } else if (info.srcUrl) {
            sendToSerein(info.srcUrl, 0, tab ? tab.id : null);
        } else if (tab) {
            captureAndSend(tab);
        }
    });
}
