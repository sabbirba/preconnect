const { onRequest } = require("firebase-functions/v2/https");

exports.api = onRequest({ cors: true }, async (req, res) => {
  const path = req.path;
  let targetUrl;

  if (path.startsWith("/api/")) {
    targetUrl = `https://connect.bracu.ac.bd${path}`;
  } else if (path.startsWith("/cdn/")) {
    targetUrl = `https://connect.bracu.ac.bd${path}`;
  } else if (path.startsWith("/sso/")) {
    const subPath = path.substring(5);
    targetUrl = `https://sso.bracu.ac.bd/realms/bracu/protocol/openid-connect/${subPath}`;
  } else {
    return res.status(404).send({ error: "Not Found" });
  }

  const urlObj = new URL(req.url, `http://${req.headers.host}`);
  const queryString = urlObj.search;
  const fullTargetUrl = queryString ? `${targetUrl}${queryString}` : targetUrl;

  const headers = {};
  for (const [key, value] of Object.entries(req.headers)) {
    if (key.toLowerCase() === "host") continue;
    headers[key] = value;
  }

  if (path.startsWith("/sso/")) {
    headers["origin"] = "https://sso.bracu.ac.bd";
    headers["referer"] = "https://sso.bracu.ac.bd/";
  } else {
    headers["origin"] = "https://connect.bracu.ac.bd";
    headers["referer"] = "https://connect.bracu.ac.bd/student/profile/overview";
  }

  try {
    const fetchOptions = {
      method: req.method,
      headers: headers,
    };

    if (["POST", "PUT", "PATCH", "DELETE"].includes(req.method) && req.rawBody) {
      fetchOptions.body = req.rawBody;
    }

    const response = await fetch(fullTargetUrl, fetchOptions);
    const contentType = response.headers.get("content-type");

    const excludeHeaders = [
      "access-control-allow-origin",
      "access-control-allow-headers",
      "access-control-allow-methods",
      "access-control-allow-credentials",
      "content-encoding",
    ];

    response.headers.forEach((value, key) => {
      if (!excludeHeaders.includes(key.toLowerCase())) {
        res.setHeader(key, value);
      }
    });

    res.status(response.status);

    if (contentType && (contentType.includes("json") || contentType.includes("text"))) {
      const text = await response.text();
      return res.send(text);
    } else {
      const buffer = await response.arrayBuffer();
      return res.send(Buffer.from(buffer));
    }
  } catch (error) {
    console.error("Proxy request failed:", error);
    return res.status(502).send({ error: "Failed to connect to university portal" });
  }
});
