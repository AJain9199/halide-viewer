# Halide Viewer

A minimal, fast, full-screen image viewer for macOS, built for quickly culling
photos straight off a camera card — flag keepers, trash rejects, and file the
rest into a dated library, all from single keystrokes with no menus or mouse
required.

## Features

- **Fast full-screen browsing** of a folder's images with arrow keys / space,
  including camera RAW formats (NEF, CR2, CR3, ARW, DNG, ORF, RW2, RAF) as
  well as JPEG, PNG, TIFF, and HEIC.
- **Flagging** that writes real Finder tags, so flagged picks show up in
  Finder and Spotlight too.
- **Two-tier delete** — Trash (recoverable) or permanent delete, each behind
  a confirmation dialog.
- **Auto-organize filing** — move or copy the current file (or all flagged
  files at once) into `<library>/<year>/<month>/<optional location label>`,
  derived from the photo's EXIF capture date.
- **Ad hoc filing** — move or copy to any folder you pick, outside the
  organized library.
- Can be set as the **default app for `.nef` (Nikon RAW) files**, so
  double-clicking one in Finder opens it directly in Halide Viewer.

## Requirements

- macOS 13 (Ventura) or later
- [Swift](https://www.swift.org/install/) 5.9+ / Xcode command line tools, to build from source

## Installation

Halide Viewer is distributed as source — build it locally with Swift Package Manager:

```sh
git clone <this-repository-url>
cd HalideViewer
./Scripts/build_app.sh --install
```

This builds a release binary, assembles `HalideViewer.app`, ad-hoc code-signs
it, and copies it to `/Applications`.

Run without `--install` to build `HalideViewer.app` in the project directory
without installing it:

```sh
./Scripts/build_app.sh
```

Launch the app by double-clicking `HalideViewer.app`, or open a specific image
with it directly:

```sh
open -a HalideViewer /path/to/photo.nef
```

On first launch you'll be asked whether to make Halide Viewer the default
viewer for `.nef` files — you can also toggle this later from the app menu
(**Halide Viewer → Make Default for NEF Files…**) or with the `D` key.

## Usage

Open an image and Halide Viewer shows every supported image in that folder,
full-screen, starting at the one you opened. All actions are single
keystrokes — no modifier keys, since the menu bar is hidden while browsing.

| Key | Action |
| --- | --- |
| `←` / `→` / `Space` | Previous / next image |
| `Esc` | Close viewer |
| `F` | Toggle flag (writes a Finder tag) |
| `Delete` | Move current file to Trash (with confirmation) |
| `Shift+Delete` | Delete current file permanently (with confirmation) |
| `M` | File into library (move) — flagged files if any are flagged, else the current file |
| `Shift+M` | Move to a folder you choose (ad hoc, outside the library) |
| `C` | File into library (copy) |
| `Shift+C` | Copy to a folder you choose (ad hoc) |
| `0` | Zoom to fit |
| `1` | Zoom to actual size (pixel-for-pixel, scroll/trackpad to pan) |
| `L` | Set a session location label (appended to the filed path) |
| `P` | Choose/change the library home folder |
| `D` | Make Halide Viewer the default app for `.nef` files |
| `E` | Toggle the EXIF info panel (also shows temporarily while the cursor is at the right edge of the screen) |

The first time you file a photo into the library, you'll be prompted to
choose a library home folder. Filed photos land at
`<library>/<year>/<month>/<location label>/<filename>`, using the photo's
EXIF capture date (falling back to file creation date). The location label
is optional, session-scoped, and set with `L`.

## License

[MIT](LICENSE)
