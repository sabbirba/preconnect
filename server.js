const fs = require("fs");
const http = require("http");
const https = require("https");
const path = require("path");
const { URL } = require("url");

const rootDir = path.join(__dirname, "web");
const port = Number(process.env.PORT || 80);
const upstream = "https://api.preconnect.app";

const mimeTypes = {
  ".html": "text/html; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".mjs": "application/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".wasm": "application/wasm",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".txt": "text/plain; charset=utf-8",
};

function cacheHeaderFor(filePath) {
  const normalized = filePath.replace(/\\/g, "/");
  const fileName = path.basename(normalized);

  if (
    fileName === "index.html" ||
    fileName === "version.json" ||
    fileName === "main.dart.js" ||
    fileName === "flutter_bootstrap.js" ||
    fileName === "flutter_service_worker.js"
  ) {
    return "no-store, no-cache, must-revalidate, max-age=0";
  }
  if (
    normalized.startsWith(path.join(rootDir, "assets").replace(/\\/g, "/")) ||
    normalized.startsWith(
      path.join(rootDir, "canvaskit").replace(/\\/g, "/")
    ) ||
    normalized.startsWith(path.join(rootDir, "icons").replace(/\\/g, "/"))
  ) {
    return "public, max-age=2592000, immutable";
  }
  return "public, max-age=604800";
}

function safeLocalPath(urlPathname) {
  const decoded = decodeURIComponent(urlPathname);
  const normalized = path.normalize(decoded).replace(/^(\.\.(\/|\\|$))+/, "");
  return path.join(rootDir, normalized);
}

function writeFileResponse(res, filePath) {
  fs.stat(filePath, (statErr, stat) => {
    if (statErr || !stat.isFile()) {
      res.statusCode = 404;
      res.end("Not found");
      return;
    }
    const ext = path.extname(filePath).toLowerCase();
    const contentType = mimeTypes[ext] || "application/octet-stream";
    res.setHeader("Content-Type", contentType);
    res.setHeader("Cache-Control", cacheHeaderFor(filePath));
    res.setHeader("X-Content-Type-Options", "nosniff");
    const stream = fs.createReadStream(filePath);
    stream.on("error", () => {
      res.statusCode = 500;
      res.end("Internal server error");
    });
    stream.pipe(res);
  });
}

function proxyApi(req, res, requestUrl) {
  const targetPath = requestUrl.pathname.replace(/^\/api\/?/, "/");
  const target = new URL(`${upstream}${targetPath}${requestUrl.search || ""}`);
  const headers = { ...req.headers };
  headers.host = target.host;
  headers["x-forwarded-proto"] = "https";
  headers["x-real-ip"] = req.socket.remoteAddress || "";

  const proxyReq = https.request(
    target,
    {
      method: req.method,
      headers,
    },
    (proxyRes) => {
      res.writeHead(proxyRes.statusCode || 502, proxyRes.headers);
      proxyRes.pipe(res);
    }
  );

  proxyReq.on("error", () => {
    res.statusCode = 502;
    res.setHeader("Content-Type", "application/json; charset=utf-8");
    res.end(JSON.stringify({ error: "Upstream API unavailable" }));
  });

  req.pipe(proxyReq);
}

const server = http.createServer((req, res) => {
  const requestUrl = new URL(req.url || "/", `http://${req.headers.host || ""}`);

  if (requestUrl.pathname.startsWith("/api/")) {
    proxyApi(req, res, requestUrl);
    return;
  }

  let candidatePath = safeLocalPath(requestUrl.pathname);
  if (requestUrl.pathname === "/") {
    candidatePath = path.join(rootDir, "index.html");
  }

  fs.stat(candidatePath, (err, stat) => {
    if (!err && stat.isFile()) {
      writeFileResponse(res, candidatePath);
      return;
    }
    writeFileResponse(res, path.join(rootDir, "index.html"));
  });
});

server.listen(port, "0.0.0.0", () => {
  console.log(`PreConnect web server running on :${port}`);
});
