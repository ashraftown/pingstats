# App icons

`master.png` is the source image for the macOS and Windows app icons. Keep it
square and opaque. Do not edit the generated app icon files directly.

Run `npm run icons:generate` from the repository root after changing the master
image. The script creates all macOS asset catalog sizes and the rounded Windows
PNG and multi-size ICO. Run `npm run icons:check` to check that generated files
match the source without changing them.

The macOS files stay square so macOS can apply its system corner mask. The
Windows files get transparent rounded corners in the generator.
