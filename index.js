export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;

    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": request.headers.get("Origin") || "*",
          "Access-Control-Allow-Methods": "GET, POST, OPTIONS, PUT, DELETE, PATCH",
          "Access-Control-Allow-Headers": "Authorization, Content-Type, X-REALM, X-SOURCE, X-ID-Token, Accept, Accept-Language, If-None-Match, If-Match",
          "Access-Control-Allow-Credentials": "true",
          "Access-Control-Max-Age": "86400",
        },
      });
    }

    let targetUrl = null;
    let targetHost = "";
    let targetOrigin = "";

    if (path.startsWith("/api/")) {
      targetUrl = "https://connect.bracu.ac.bd" + path;
      targetHost = "connect.bracu.ac.bd";
      targetOrigin = "https://connect.bracu.ac.bd";
    } else if (path.startsWith("/cdn/")) {
      targetUrl = "https://connect.bracu.ac.bd" + path;
      targetHost = "connect.bracu.ac.bd";
      targetOrigin = "https://connect.bracu.ac.bd";
    } else if (path.startsWith("/sso/")) {
      targetUrl =
        "https://sso.bracu.ac.bd/realms/bracu/protocol/openid-connect/" +
        path.substring(5);
      targetHost = "sso.bracu.ac.bd";
      targetOrigin = "https://sso.bracu.ac.bd";
    }

    if (!targetUrl) {
      return new Response("Not Found", { status: 404 });
    }

    if (url.search) {
      targetUrl += url.search;
    }

    const headers = new Headers(request.headers);
    headers.set("Host", targetHost);
    headers.set("Origin", targetOrigin);
    headers.set("Referer", targetOrigin + "/");

    const hasBody = request.method !== "GET" && request.method !== "HEAD";
    try {
      const response = await fetch(targetUrl, {
        method: request.method,
        headers: headers,
        body: hasBody ? request.body : undefined,
        redirect: "manual",
      });

      const responseHeaders = new Headers(response.headers);
      responseHeaders.set(
        "Access-Control-Allow-Origin",
        request.headers.get("Origin") || "*",
      );
      responseHeaders.set("Access-Control-Allow-Credentials", "true");
      responseHeaders.set(
        "Access-Control-Allow-Methods",
        "GET, POST, OPTIONS, PUT, DELETE, PATCH",
      );

      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: responseHeaders,
      });
    } catch (err) {
      return new Response(JSON.stringify({ error: err.message }), {
        status: 500,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      });
    }
  },
};
