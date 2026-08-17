import { copyFileSync, readdirSync, rmSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const APP_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const BRAND_ROOT = resolve(APP_ROOT, "../../assets");
const PUBLIC_ROOT = join(APP_ROOT, "public");

const WEB_SERVED = [
  "logo.svg",
  "favicon.svg",
  "favicon-32x32.png",
  "favicon.ico",
  "apple-touch-icon.png",
  "og-image.png",
];

const SCREENSHOTS_DIR = "screenshots";

const fail = (missing) => {
  console.error(`sync-brand: required source missing: ${missing}`);
  process.exit(1);
};

for (const entry of WEB_SERVED) {
  const src = join(BRAND_ROOT, entry);
  if (!statSync(src, { throwIfNoEntry: false })) {
    fail(src);
  }
}

const screenshotsSrc = join(BRAND_ROOT, SCREENSHOTS_DIR);
if (!statSync(screenshotsSrc, { throwIfNoEntry: false })?.isDirectory()) {
  fail(screenshotsSrc);
}
const screenshots = readdirSync(screenshotsSrc);

for (const entry of WEB_SERVED) {
  copyFileSync(join(BRAND_ROOT, entry), join(PUBLIC_ROOT, entry));
}

for (const file of screenshots) {
  copyFileSync(join(screenshotsSrc, file), join(PUBLIC_ROOT, file));
}

// Prune stale synced files so public/ mirrors assets/ exactly. site.webmanifest
// and _headers are web-only and must be preserved; anything else in public/ that
// is not a current brand source (e.g. a renamed or deleted screenshot) is
// removed so the CI drift check sees it and the change is committed or caught.
const expected = new Set([...WEB_SERVED, ...screenshots, "site.webmanifest", "_headers"]);
for (const name of readdirSync(PUBLIC_ROOT)) {
  if (!expected.has(name)) {
    rmSync(join(PUBLIC_ROOT, name));
  }
}

console.log(`sync-brand: copied ${WEB_SERVED.length} files + ${SCREENSHOTS_DIR} to ${PUBLIC_ROOT}`);