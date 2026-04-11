export default {
  async fetch(request, env) {
    const response = await env.ASSETS.fetch(request);

    if (response.status !== 404) {
      return response;
    }

    const url = new URL(request.url);
    const accept = `${request.headers.get('accept') || ''}`.toLowerCase();
    const wantsHtml = accept.includes('text/html');

    if (!wantsHtml) {
      return response;
    }

    url.pathname = '/index.html';
    return env.ASSETS.fetch(new Request(url, request));
  },
};

