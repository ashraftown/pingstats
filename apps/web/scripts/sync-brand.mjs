import { copyFileSync, readdirSync, statSync } from "node:fs";
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

for (const entry of WEB_SERVED) {
  const src = join(BRAND_ROOT, entry);
  const dest = join(PUBLIC_ROOT, entry);

  if (!statSync(src, { throwIfNoEntry: false })) {
    console.warn(`sync-brand: missing ${src}, skipping`);
    continue;
  }

  copyFileSync(src, dest);
}

const screenshotsSrc = join(BRAND_ROOT, SCREENSHOTS_DIR);
if (statSync(screenshotsSrc, { throwIfNoEntry: false })?.isDirectory()) {
  for (const file of readdirSync(screenshotsSrc)) {
    copyFileSync(join(screenshotsSrc, file), join(PUBLIC_ROOT, file));
  }
} else {
  console.warn(`sync-brand: missing ${SCREENSHOTS_DIR} dir, skipping`);
}

console.log(`sync-brand: copied ${WEB_SERVED.length} files + ${SCREENSHOTS_DIR} to ${PUBLIC_ROOT}`);
