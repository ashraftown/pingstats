import { GITHUB_REPO, MACOS_DMG, WINDOWS_ZIP } from "../consts";

// Ported from t3code apps/marketing/src/lib/releases.ts (stable channel only;
// PingStats has no nightly train, no Linux build, and no mobile apps).
// Resolves the exact versioned assets (PingStats-<version>-macos.dmg,
// PingStats-<version>-windows.zip) instead of relying on the
// /releases/latest/download redirect, and exposes the tag for display.

export const RELEASES_URL = `${GITHUB_REPO}/releases`;

const LATEST_API_URL = "https://api.github.com/repos/ashraftown/pingstats/releases/latest";

export interface ReleaseAsset {
  name: string;
  browser_download_url: string;
}

export interface Release {
  tag_name: string;
  html_url: string;
  published_at: string;
  assets: ReleaseAsset[];
}

const CACHE_KEY = "pingstats-release";

export function pickAsset(
  assets: ReleaseAsset[],
  platform: "mac" | "win",
): string | null {
  const suffix = platform === "mac" ? "-macos.dmg" : "-windows.zip";
  return assets.find((a) => a.name.endsWith(suffix))?.browser_download_url ?? null;
}

export function fallbackUrl(platform: "mac" | "win"): string {
  return platform === "mac" ? MACOS_DMG : WINDOWS_ZIP;
}

export async function fetchLatestRelease(): Promise<Release> {
  const cached = sessionStorage.getItem(CACHE_KEY);
  if (cached) return JSON.parse(cached);

  const response = await fetch(LATEST_API_URL);
  if (!response.ok) throw new Error(`GitHub release request failed: ${response.status}`);
  const data: Release = await response.json();
  // A rate-limit or error payload is still JSON: refuse anything shapeless
  // so callers fall back instead of rendering "undefined".
  if (!data?.tag_name || !Array.isArray(data.assets)) {
    throw new Error("GitHub release response missing tag_name or assets");
  }

  if (data?.assets) {
    sessionStorage.setItem(CACHE_KEY, JSON.stringify(data));
  }

  return data;
}
