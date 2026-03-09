const DEFAULT_BROKER_BASE = "https://api.preconnect.app";
const DEFAULT_SESSION_EMAIL = "web@preconnect.app";
const DEFAULT_VM_BASE = "https://vm.preconnect.app";

function json(data, init = {}) {
  return new Response(JSON.stringify(data), {
    ...init,
    headers: {
      "content-type": "application/json; charset=utf-8",
      ...(init.headers || {}),
    },
  });
}

function passthroughNoStore(upstream) {
  const headers = new Headers(upstream.headers);
  headers.set("cache-control", "no-store, no-cache, must-revalidate");
  headers.set("pragma", "no-cache");
  headers.set("expires", "0");
  return new Response(upstream.body, {
    status: upstream.status,
    headers,
  });
}

function normalizeEmail(input) {
  return `${input || ""}`.trim().toLowerCase();
}

async function proxyToBroker(path, init = {}, env) {
  const base = `${env.BROKER_BASE || DEFAULT_BROKER_BASE}`.replace(/\/+$/, "");
  return fetch(`${base}${path}`, init);
}

async function proxyToVm(path, init = {}, env) {
  const base = `${env.VM_BASE || DEFAULT_VM_BASE}`.replace(/\/+$/, "");
  return fetch(`${base}${path}`, init);
}

async function handleCreateSession(request, env) {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, { status: 405 });
  }

  let body = {};
  try {
    const text = await request.text();
    if (text.trim() !== "") {
      body = JSON.parse(text);
    }
  } catch (_) {
    body = {};
  }

  const studentEmail = normalizeEmail(body?.studentEmail || body?.email);
  const payload = {
    studentEmail: studentEmail.includes("@")
      ? studentEmail
      : DEFAULT_SESSION_EMAIL,
  };
  const upstream = await proxyToBroker(
    "/web-login/session",
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(payload),
    },
    env,
  );

  return passthroughNoStore(upstream);
}

async function handleWebLoginProxy(request, url, env) {
  const path = `${url.pathname || ""}`;
  if (!path.startsWith("/api/web-login/")) return null;
  if (path === "/api/web-login/session") return null;

  const brokerPath = path.replace(/^\/api/, "") + (url.search || "");
  const headers = new Headers(request.headers);
  headers.delete("host");
  const init = {
    method: request.method,
    headers,
  };
  if (request.method !== "GET" && request.method !== "HEAD") {
    init.body = await request.text();
  }
  const upstream = await proxyToBroker(brokerPath, init, env);
  return passthroughNoStore(upstream);
}

async function handleVmProxy(request, url, env) {
  const path = `${url.pathname || ""}`;
  if (!path.startsWith("/vm/")) return null;

  const vmPath = path + (url.search || "");
  const headers = new Headers(request.headers);
  headers.delete("host");
  const init = {
    method: request.method,
    headers,
  };
  if (request.method !== "GET" && request.method !== "HEAD") {
    init.body = await request.text();
  }
  const upstream = await proxyToVm(vmPath, init, env);
  return passthroughNoStore(upstream);
}

function isDisallowedImageHost(hostname) {
  const host = `${hostname || ""}`.trim().toLowerCase();
  if (!host) return true;
  if (host === "localhost" || host === "127.0.0.1" || host === "::1") {
    return true;
  }
  if (/^10\.\d+\.\d+\.\d+$/.test(host)) return true;
  if (/^192\.168\.\d+\.\d+$/.test(host)) return true;
  if (/^172\.(1[6-9]|2\d|3[0-1])\.\d+\.\d+$/.test(host)) return true;
  if (host.endsWith(".local")) return true;
  return false;
}

async function handleImageProxy(url) {
  const raw = `${url.searchParams.get("u") || ""}`.trim();
  if (!raw) {
    return new Response("Missing image url", { status: 400 });
  }

  let target;
  try {
    target = new URL(raw);
  } catch (_) {
    return new Response("Invalid image url", { status: 400 });
  }

  if (target.protocol !== "https:" && target.protocol !== "http:") {
    return new Response("Unsupported image protocol", { status: 400 });
  }
  if (isDisallowedImageHost(target.hostname)) {
    return new Response("Image host blocked", { status: 403 });
  }

  const upstream = await fetch(target.toString(), {
    cf: { cacheTtl: 60 * 60 * 12, cacheEverything: true },
    headers: { "user-agent": "preconnect-web-image-proxy/1.0" },
  });

  if (!upstream.ok) {
    return new Response("Image fetch failed", { status: upstream.status });
  }

  const contentType = upstream.headers.get("content-type") || "";
  if (!contentType.toLowerCase().startsWith("image/")) {
    return new Response("Unsupported image response", { status: 415 });
  }

  return new Response(upstream.body, {
    status: 200,
    headers: {
      "content-type": contentType,
      "cache-control": "public, max-age=3600, s-maxage=43200",
    },
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/img") {
      return handleImageProxy(url);
    }

    if (url.pathname === "/api/web-login/session") {
      return handleCreateSession(request, env);
    }

    if (url.pathname.startsWith("/api/web-login/")) {
      const res = await handleWebLoginProxy(request, url, env);
      if (res) return res;
    }

    if (url.pathname.startsWith("/vm/")) {
      const res = await handleVmProxy(request, url, env);
      if (res) return res;
    }

    return env.ASSETS.fetch(request);
  },
};
