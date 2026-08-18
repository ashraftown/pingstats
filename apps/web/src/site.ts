export const siteUrl = "https://pingstats.corewaze.com";

export const siteName = "PingStats";
export const siteTitle =
  "PingStats — Live Network Latency in Your Menu Bar or System Tray";
export const siteDescription =
  "Live network latency in your menu bar or system tray. PingStats is a lightweight desktop utility that shows real-time ping to any host.";
export const siteLocale = "en_US";

export const siteIcon = {
  // v=2: cache-bust after the 2026-08 logo refresh (rings + signal dot mark).
  path: "/favicon.svg?v=2",
  type: "image/svg+xml",
} as const;

export const siteFaviconPng = {
  path: "/favicon-32x32.png?v=2",
  width: 32,
  height: 32,
  type: "image/png",
} as const;

export const siteFaviconIco = {
  path: "/favicon.ico?v=2",
  sizes: "16x16 32x32",
  type: "image/x-icon",
} as const;

export const siteAppleIcon = {
  path: "/apple-touch-icon.png?v=2",
  width: 180,
  height: 180,
  type: "image/png",
} as const;

export const siteManifest = {
  path: "/site.webmanifest",
  type: "application/manifest+json",
} as const;

export const siteShareImage = {
  path: "/og-image.png",
  width: 1200,
  height: 630,
  type: "image/png",
  alt: "PingStats — live network latency in your menu bar or system tray",
} as const;

export const siteLogo = {
  path: "/logo.svg",
  type: "image/svg+xml",
} as const;

export const brandColors = {
  background: "#09090b",
  foreground: "#fafafa",
  accent: "#3E8EF7",
} as const;
