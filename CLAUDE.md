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

`Scripts/build_app.sh` copies `Resources/AppIcon/Halide.icns` into the app
bundle (referenced by `CFBundleIconFile` in `Info.plist`). That `.icns` is
built from `Resources/AppIcon/Halide.iconset` via `iconutil -c icns
Halide.iconset -o Halide.icns` — regenerate it there if the source PNGs
change; `Resources/AppIcon/assets/` holds the SVG sources (full icon, mark,
lockup) for other contexts (menu bar, marketing).

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
  the same key — e.g. `Delete` = trash, `Shift+Delete` = permanent). `M` is
  the one key where a modifier changes the destination rather than just the
  severity: plain `M`/`Shift+M` both run `performMoveCommand()` (move to a
  remembered-or-chosen destination via `MoveDestinationDialog`), while `⌘M`
  runs `fileIntoLibrary(mode: .move)` instead. No menu bar or modifier
  chords are otherwise used since the menu bar is hidden while viewing.
  `ImageCanvasView` also has a third zoom mode, `.clicked(imagePoint:)`,
  toggled by mouse click: click zooms in centered on the clicked point at
  `Preferences.clickZoomFactor` × fit scale, re-clicking returns to fit.
  `.actualSize` and `.clicked` both run their computed origin through
  `clampedToFillBounds`, which pins the image to cover the view on any axis
  where it's large enough to (no black void at the edges) and otherwise
  centers that axis, same as `.fit`. Pan gestures (`mouseDragged`,
  `scrollWheel`) clamp the *stored* `offset` itself via `clampedOffset`
  (not just the value used at draw time) — clamping only at draw time let
  `offset` accumulate past the boundary while pinned, so panning back the
  other way had to "unwind" that excess before the image visually moved.
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
  `uniqueDestination`. `fileIntoLibrary` (⌘M / `C`) warns instead of filing
  if `Preferences.libraryHomeURL` is unset or not currently reachable
  (`URL.isReachableDirectory`) — it no longer auto-prompts a picker like it
  used to; use `P` to set the library home explicitly.
- `AdHocFileOps` — one-off move/copy: `chooseFolder(mode:)` just runs the
  `NSOpenPanel`, `file(_:mode:to:onFileComplete:)` does the actual
  move/copy given a known destination (shared by the ad hoc picker path and
  `MoveDestinationDialog`'s remembered destinations); shares
  `LibraryFiler.uniqueDestination`.
- `MoveDestinationDialog` — backs `M`/`Shift+M`: an `NSAlert` with an
  `NSPopUpButton` of `Preferences.recentMoveDestinations` (newest first,
  capped at 5) plus a "Choose Folder…" entry that opens a picker inline and
  prepends the result. Pre-selects the most-recently-used destination; on
  confirm, `Preferences.rememberMoveDestination` promotes the chosen one to
  the front for next time. With no history yet, skips straight to the
  folder picker.
- `ProgressOverlayView` — wraps any copy/move: a small centered overlay
  with a determinate progress bar ("Moving N file(s) to <destination>…"),
  shown/hidden via `isHidden` while the file op runs on a background queue
  (the passed-in `onFileComplete`/`reportFileComplete` callback advances the
  bar per file), then hands the succeeded URLs back on the main thread.
  It's a plain subview of `ImageViewController`'s own container view, *not*
  a separate `NSPanel` — ordering a whole extra window in/out while
  `NSApp.presentationOptions = [.hideMenuBar, .hideDock]` is active (see
  `ImageWindowController.showFullscreen`) is expensive (the window server
  has to reconcile the auto-hidden menu bar/dock against another window
  coming to front), which made an early NSPanel-based version feel
  sluggish — even reusing one window across calls — for every single
  operation, fast or slow. A subview toggle has none of that overhead.
  `ImageViewController.performFileOperation` is the one call site that
  wires this up for all three filing paths (library, ad hoc, "Move"),
  applies the shared post-filing browsing update, and calls `announce(_:)`
  to report the result in the status line.
- Status line (`ImageViewController.statusLabel`, top-left, opposite the
  bottom-left HUD) — shows a summary of the last copy/move
  ("Moved/Copied N file(s) to <destination>…") for 1 second right after it
  happens, or again on hovering the top-left corner
  (`statusHotZoneWidth`/`statusHotZoneHeight`, same hover-overlay pattern as
  the EXIF panel's right-edge zone). It never hides abruptly — `announce`/
  `presentStatus` set `alphaValue = 1` directly, and `fadeOutStatus`
  animates back to 0 via `NSAnimationContext`. If the cursor is already in
  the hover corner when `announce` fires, it skips scheduling the 1s
  auto-hide so it doesn't fade out from under an actively-hovering cursor.
- `TrashAction` (`DeleteAction` enum) — two-tier delete, each behind a
  confirmation `NSAlert`; trash failures (e.g. volumes without a Trash) fall
  back to a permanent-delete confirmation.
- `Preferences` — thin `UserDefaults` wrapper: library home folder, the
  session-scoped location label, the click-to-zoom factor, the recent
  "Move" destinations list, and the one-time "prompt to become default app"
  flag.
- `DefaultAppRegistration` — registers the app as the default handler for
  `.nef` via `NSWorkspace.setDefaultApplication`; prompted once on first
  launch (since the menu bar is hidden during normal use) and re-triggerable
  with `D`.

**Filing operations that move files** (`fileIntoLibrary`/`adHocFile`/
`performMoveCommand` with `mode: .move`) have `performFileOperation` call
`browser.remove(_:)` afterward to keep the browsing list and current index
consistent; copy operations don't, since the source file still exists at
its original position.

**Batch vs. single-file actions:** filing (`M`/`⌘M`/`C` and `Shift+C`) acts
on `browser.filingTargets` — the flagged set if non-empty, otherwise just
the current file. Delete/trash always act on the current file only.
