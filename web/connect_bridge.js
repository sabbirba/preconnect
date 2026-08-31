if (!globalThis.__preconnectConnectBridgeInstalled) {
  globalThis.__preconnectConnectBridgeInstalled = true;
  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (message?.type !== "preconnect.pageConnectRequest") return false;
    const url = new URL(message.url);
    if (
      url.protocol !== "https:" ||
      url.hostname !== "connect.bracu.ac.bd" ||
      !url.pathname.startsWith("/api/")
    ) {
      sendResponse({ error: "Connect request target is not allowed" });
      return false;
    }
    const headers = new Headers(message.headers || {});
    if (!headers.get("authorization")) {
      sendResponse({ error: "No authorization observed from the Connect tab" });
      return false;
    }
    const bytes = message.body
      ? Uint8Array.from(atob(message.body), (character) => character.charCodeAt(0))
      : new Uint8Array();
    const init = {
      method: message.method,
      headers,
      credentials: "include",
      cache: "no-store",
    };
    if (bytes.length && message.method !== "GET" && message.method !== "HEAD") {
      init.body = bytes;
    }
    fetch(url.href, init)
      .then(async (response) => {
        const responseBytes = new Uint8Array(await response.arrayBuffer());
        let binary = "";
        for (const byte of responseBytes) binary += String.fromCharCode(byte);
        sendResponse({
          statusCode: response.status,
          headers: Object.fromEntries(response.headers.entries()),
          body: btoa(binary),
        });
      })
      .catch((error) => sendResponse({ error: String(error) }));
    return true;
  });
}
