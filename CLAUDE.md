# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Halide Viewer is a minimal, fast, full-screen macOS image viewer for culling
photos off a camera card: flag keepers (via real Finder tags), trash rejects,
and file the rest into a dated library — all via single keystrokes, no menus
or mouse. See README.md for the full feature list and keybinding table.

## Commands

Build and run (Swift Package Manager, no Xcode project):

```sh
swift build                       # debug build
swift build -c release            # release build
./Scripts/build_app.sh            # release build + assemble HalideViewer.app locally (ad-hoc signed)
./Scripts/build_app.sh --install  # same, then install to /Applications and register with Launch Services
```

There is no test suite and no linter configured in this repo.

Run the built app on a specific image:

```sh
open -a HalideViewer /path/to/photo.nef
```

## Architecture

Single executable target (`HalideViewer`), no other targets/dependencies.
Entry point `main.swift` creates `AppDelegate` and runs an `NSApplication`
directly (no storyboard/XIB, no SwiftUI — all views built programmatically).

**Flow:** `AppDelegate` opens the file passed on the command line (or via
`application(_:open:)` for double-click/`open -a`, or a picker if neither
fires) by constructing a `FolderBrowser`, then hands it to an
`ImageWindowController`, which owns a borderless, screen-sized `NSWindow`
containing one `ImageViewController`. The app is single-window and
single-document per launch — closing the viewer terminates the app
(`ImageWindowController.closeViewer`).

**Key components, one responsibility each:**
- `FolderBrowser` — pure state: enumerates sibling images in the opened
  file's folder (extensions in `FolderBrowser.supportedExtensions`), tracks
  current index and the in-session flagged set. Has no UI/IO side effects
  beyond initial directory listing.
- `ImageViewController` + `ImageCanvasView` — the entire UI. All keyboard
  input is handled in one `handle(_:)` switch (arrow keys/space navigate,
  unmodified letters trigger actions, Shift selects the "harder" variant of
  the same key — e.g. `Delete` = trash, `Shift+Delete` = permanent; `M` =
  file into library, `Shift+M` = ad hoc folder). No menu bar or modifier
  chords are used for browsing actions since the menu bar is hidden while
  viewing.
- `ImageLoader` — two decode paths: `loadPreview` pulls the embedded
  full-res JPEG preview out of RAW files via ImageIO (near-instant, used for
  normal browsing), while `loadFullResolution` does a real `CIRAWFilter`
  demosaic (only invoked on demand for pixel-level zoom). Also extracts EXIF
  capture date for filing.
- `ImageCache` — `NSCache`-backed preview cache plus background prefetch
  (`Task.detached`) of the ±2 neighboring images, so arrow-key navigation
  doesn't block on decode.
- `FinderTagging` — flagging is implemented as a real Finder tag
  (`"Flagged"`) written via `.tagNamesKey`, not app-private state, so
  flagged picks are visible in Finder/Spotlight. Read-modify-write preserves
  any other tags already on the file.
- `LibraryFiler` — auto-organize filing: derives `<home>/<year>/<month>/
  <optional session label>` from EXIF capture date (falling back to file
  creation date, then `Date()`), de-duplicating destination filenames via
  `uniqueDestination`.
- `AdHocFileOps` — one-off move/copy to a folder chosen via `NSOpenPanel`,
  outside the library structure; shares `LibraryFiler.uniqueDestination`.
- `TrashAction` (`DeleteAction` enum) — two-tier delete, each behind a
  confirmation `NSAlert`; trash failures (e.g. volumes without a Trash) fall
  back to a permanent-delete confirmation.
- `Preferences` — thin `UserDefaults` wrapper: library home folder, the
  session-scoped location label, and the one-time "prompt to become default
  app" flag.
- `DefaultAppRegistration` — registers the app as the default handler for
  `.nef` via `NSWorkspace.setDefaultApplication`; prompted once on first
  launch (since the menu bar is hidden during normal use) and re-triggerable
  with `D`.

**Filing operations that move files** (`fileIntoLibrary`/`adHocFile` with
`mode: .move`) call `browser.remove(_:)` afterward to keep the browsing list
and current index consistent; copy operations don't, since the source file
still exists at its original position.

**Batch vs. single-file actions:** filing (`M`/`C` and their Shift variants)
acts on `browser.filingTargets` — the flagged set if non-empty, otherwise
just the current file. Delete/trash always act on the current file only.
