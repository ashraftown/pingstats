export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (url.pathname === "/favicon.ico") {
      return new Response(null, { status: 204 });
    }

    const response = await env.ASSETS.fetch(request);

    if (!response.ok && response.status === 404) {
      return env.ASSETS.fetch(new Request(new URL("/index.html", request.url)));
    }

    return response;
  },
};
