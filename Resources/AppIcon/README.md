# Halide Viewer — app identity assets

Mark: **Emulsion lattice** (2A). A silver-halide crystal carrying an internal
honeycomb lattice, with the accent ring reading as the viewing aperture.
Colors are taken from the Classical tokens: ink #201f1d, lattice #bab6b6,
accent #b68235, ground #f3f2f2.

## Files

    assets/halide-icon.svg          1024 app icon, full lattice (use at 128px and up)
    assets/halide-icon-small.svg    reduced 3-line version (use at 32-64px)
    assets/halide-icon-tiny.svg     crystal only, heaviest stroke (use at 16px)
    assets/halide-mark.svg          mark only, transparent, light grounds
    assets/halide-mark-dark.svg     mark only, transparent, dark grounds
    assets/halide-mark-small.svg    reduced mark, transparent (menu bar, favicon)
    assets/halide-lockup.svg        horizontal lockup: mark + "Halide / VIEWER"
    Halide.iconset/                 ten PNGs, Apple's required icon sizes

## Building Halide.icns

The @2x files are stored with a `-2x` suffix (`@` is not filename-safe here).
Restore the names and run iconutil:

    cd Halide.iconset
    for f in *-2x.png; do mv "$f" "${f%-2x.png}@2x.png"; done
    cd ..
    iconutil -c icns Halide.iconset -o Halide.icns

Then in Xcode: drop `Halide.icns` in the target's resources and set
`ASSETCATALOG_COMPILER_APPICON_NAME`, or drag the ten PNGs into an
`AppIcon` image set in Assets.xcassets.

## Other places this mark is needed

- Menu bar / template image: `halide-mark-small.svg` at 18pt, rendered as a
  template (single ink) so macOS can tint it.
- Dock badge, About panel, DMG background: `halide-icon.svg`.
- Web / marketing: `halide-lockup.svg`. The lockup references Cormorant
  Garamond and Lora; convert the text to outlines before shipping it anywhere
  the fonts are not loaded.

## Icon geometry

1024x1024 canvas, corner radius 185 (Apple's squircle proportion). The crystal
spans 31.1-168.9 on the 200 unit grid, i.e. an inset of ~159px at 1024.
Stroke weights are set per size, not scaled: the 32px variant drops the lattice
and thickens the crystal, and the 16px tile (`halide-icon-tiny.svg`) drops the
accent ring too and carries the heaviest stroke so it still reads in a Finder
list.
