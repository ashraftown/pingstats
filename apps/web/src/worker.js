const SECURITY_HEADERS = {
  "Content-Security-Policy": [
    "default-src 'self'",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data:",
    "font-src 'self'",
    "base-uri 'self'",
    "form-action 'none'",
    "frame-ancestors 'none'",
  ].join("; "),
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "Permissions-Policy": "geolocation=(), microphone=(), camera=()",
};

const withSecurityHeaders = (headers) => {
  for (const [key, value] of Object.entries(SECURITY_HEADERS)) {
    headers.set(key, value);
  }
  return headers;
};

export default {
  async fetch(request, env, ctx) {
    const response = await env.ASSETS.fetch(request);

    // Single-page landing: serve index.html for navigations to unknown paths.
    // Only for HTML requests so missing assets return a real 404.
    if (
      response.status === 404 &&
      request.headers.get("accept")?.includes("text/html")
    ) {
      const fallback = await env.ASSETS.fetch(
        new Request(new URL("/index.html", request.url)),
      );
      return new Response(fallback.body, {
        status: 200,
        headers: withSecurityHeaders(new Headers(fallback.headers)),
      });
    }

    return new Response(response.body, {
      status: response.status,
      headers: withSecurityHeaders(new Headers(response.headers)),
    });
  },
};
