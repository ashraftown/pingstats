import { readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const sourcePath = join(root, "assets/icons/app-icon.png");
const macOSPath = join(root, "apps/macos/PingStats/Assets.xcassets/AppIcon.appiconset");
const windowsPath = join(root, "apps/windows/PingStats.Windows/Resources");
const checkOnly = process.argv.includes("--check");

const macOSIcons = [
  ["icon_16x16.png", 16],
  ["icon_16x16@2x.png", 32],
  ["icon_32x32.png", 32],
  ["icon_32x32@2x.png", 64],
  ["icon_128x128.png", 128],
  ["icon_128x128@2x.png", 256],
  ["icon_256x256.png", 256],
  ["icon_256x256@2x.png", 512],
  ["icon_512x512.png", 512],
  ["icon_512x512@2x.png", 1024],
];
const windowsIconSizes = [16, 24, 32, 48, 64, 128, 256];

const source = await readFile(sourcePath);
const metadata = await sharp(source).metadata();
if (metadata.width !== 1024 || metadata.height !== 1024) {
  throw new Error(`Expected a 1024×1024 master icon, got ${metadata.width}×${metadata.height}.`);
}

const cache = new Map();
const renderSquare = (size) => {
  if (!cache.has(size)) {
    cache.set(size, sharp(source).resize(size, size).png().toBuffer());
  }
  return cache.get(size);
};

const renderWindows = async (size) => {
  const radius = Math.round(size * 0.22);
  const mask = Buffer.from(
    `<svg width="${size}" height="${size}" xmlns="http://www.w3.org/2000/svg"><rect width="${size}" height="${size}" rx="${radius}" fill="white"/></svg>`,
  );
  return sharp(await renderSquare(size))
    .composite([{ input: mask, blend: "dest-in" }])
    .png()
    .toBuffer();
};

const makeIco = (images) => {
  const header = Buffer.alloc(6 + images.length * 16);
  header.writeUInt16LE(0, 0);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(images.length, 4);

  let offset = header.length;
  images.forEach(({ size, png }, index) => {
    const entry = 6 + index * 16;
    const dimension = size === 256 ? 0 : size;
    header.writeUInt8(dimension, entry);
    header.writeUInt8(dimension, entry + 1);
    header.writeUInt8(0, entry + 2);
    header.writeUInt8(0, entry + 3);
    header.writeUInt16LE(1, entry + 4);
    header.writeUInt16LE(32, entry + 6);
    header.writeUInt32LE(png.length, entry + 8);
    header.writeUInt32LE(offset, entry + 12);
    offset += png.length;
  });

  return Buffer.concat([header, ...images.map(({ png }) => png)]);
};

const outputs = new Map();
for (const [name, size] of macOSIcons) {
  outputs.set(join(macOSPath, name), await renderSquare(size));
}

const windowsPng = await renderWindows(256);
const icoImages = await Promise.all(
  windowsIconSizes.map(async (size) => ({ size, png: await renderWindows(size) })),
);
outputs.set(join(windowsPath, "app.png"), windowsPng);
outputs.set(join(windowsPath, "app.ico"), makeIco(icoImages));

const stale = [];
for (const [path, expected] of outputs) {
  let actual;
  try {
    actual = await readFile(path);
  } catch {
    actual = undefined;
  }

  if (!actual?.equals(expected)) {
    if (checkOnly) {
      stale.push(path.slice(root.length + 1));
    } else {
      await writeFile(path, expected);
      console.log(`Generated ${path.slice(root.length + 1)}`);
    }
  }
}

if (stale.length > 0) {
  console.error(`Generated icons are stale:\n${stale.map((path) => `- ${path}`).join("\n")}`);
  process.exitCode = 1;
} else if (checkOnly) {
  console.log("Generated icons match the master source.");
}
