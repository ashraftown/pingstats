import { GITHUB_REPO } from "../consts";

// Ported from t3code apps/marketing/src/lib/releases.ts (stable channel only;
// PingStats has no nightly train, no Linux build, and no mobile apps).
// Resolves the exact versioned assets (PingStats-<version>-macos.dmg,
// PingStats-<version>-windows-setup.exe) instead of relying on the
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
  const suffix = platform === "mac" ? "-macos.dmg" : "-windows-setup.exe";
  const matches = assets.filter((a) => a.name.endsWith(suffix));
  // Prefer the versioned asset over the unversioned release alias.
  return (matches.find((a) => /^PingStats-\d/.test(a.name)) ?? matches[0])
    ?.browser_download_url ?? null;
}

// Resolves the exact versioned download for a platform. Falls back to the
// releases page when the GitHub API fails, so links never 404.
export async function resolveDownloadUrl(platform: "mac" | "win"): Promise<string> {
  try {
    const release = await fetchLatestRelease();
    return pickAsset(release.assets ?? [], platform) ?? RELEASES_URL;
  } catch {
    return RELEASES_URL;
  }
}

// In-flight request shared by every button on the page, so hero and footer
// trigger one GitHub call instead of one per button.
let pending: Promise<Release> | null = null;

export function fetchLatestRelease(): Promise<Release> {
  const cached = sessionStorage.getItem(CACHE_KEY);
  if (cached) return Promise.resolve(JSON.parse(cached));

  pending ??= fetch(LATEST_API_URL)
    .then(async (response) => {
      if (!response.ok) throw new Error(`GitHub release request failed: ${response.status}`);
      const data: Release = await response.json();
      // A rate-limit or error payload is still JSON: refuse anything shapeless
      // so callers fall back instead of rendering "undefined".
      if (!data?.tag_name || !Array.isArray(data.assets)) {
        throw new Error("GitHub release response missing tag_name or assets");
      }
      sessionStorage.setItem(CACHE_KEY, JSON.stringify(data));
      return data;
    })
    .finally(() => {
      pending = null;
    });
  return pending;
}
