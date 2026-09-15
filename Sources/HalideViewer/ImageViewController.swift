import AppKit

final class ImageViewController: NSViewController {

    let browser: FolderBrowser
    let canvasView = ImageCanvasView()
    private let hudLabel = NSTextField(labelWithString: "")
    private let exifOverlay = ExifOverlayView(frame: .zero)
    private let progressOverlay = ProgressOverlayView(frame: .zero)
    private let statusLabel = NSTextField(labelWithString: "")
    private var loadGeneration = 0

    /// EXIF panel visibility: `E` toggles a persistent pin; hovering the
    /// right edge of the screen shows it temporarily on top of that.
    private var exifPinned = false
    private var exifHovering = false
    private var exifFieldsCache: [URL: [ExifField]] = [:]
    private let exifHotZoneWidth: CGFloat = 48
    private let exifMargin: CGFloat = 20

    /// Status line (top-left): shows a summary of the last copy/move for 1s
    /// right after it happens, and again on hover over the top-left corner;
    /// it fades out (never hides abruptly) when either of those ends.
    private var lastActionSummary: String?
    private var statusHovering = false
    private var statusFadeWorkItem: DispatchWorkItem?
    private let statusHotZoneWidth: CGFloat = 220
    private let statusHotZoneHeight: CGFloat = 70

    init(browser: FolderBrowser) {
        self.browser = browser
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        canvasView.frame = container.bounds
        canvasView.autoresizingMask = [.width, .height]
        canvasView.keyDownHandler = { [weak self] event in self?.handle(event) }
        canvasView.mouseMovedHandler = { [weak self] point in self?.handleMouseMoved(point) }
        canvasView.mouseExitedHandler = { [weak self] in
            self?.setExifHovering(false)
            self?.setStatusHovering(false)
        }
        container.addSubview(canvasView)

        exifOverlay.isHidden = true
        container.addSubview(exifOverlay)

        progressOverlay.frame = NSRect(
            x: (container.bounds.width - ProgressOverlayView.width) / 2,
            y: (container.bounds.height - ProgressOverlayView.height) / 2,
            width: ProgressOverlayView.width,
            height: ProgressOverlayView.height
        )
        progressOverlay.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        container.addSubview(progressOverlay)

        hudLabel.frame = NSRect(x: 16, y: 16, width: container.bounds.width - 32, height: 20)
        hudLabel.autoresizingMask = [.width, .maxYMargin]
        hudLabel.textColor = .white
        hudLabel.backgroundColor = .clear
        hudLabel.isBezeled = false
        hudLabel.isEditable = false
        hudLabel.isSelectable = false
        hudLabel.font = .systemFont(ofSize: 13, weight: .medium)
        let shadow = NSShadow()
        shadow.shadowColor = .black
        shadow.shadowBlurRadius = 3
        hudLabel.shadow = shadow
        container.addSubview(hudLabel)

        statusLabel.frame = NSRect(x: 16, y: container.bounds.height - 36, width: container.bounds.width - 32, height: 20)
        statusLabel.autoresizingMask = [.width, .minYMargin]
        statusLabel.textColor = .white
        statusLabel.backgroundColor = .clear
        statusLabel.isBezeled = false
        statusLabel.isEditable = false
        statusLabel.isSelectable = false
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.shadow = shadow
        statusLabel.alphaValue = 0
        container.addSubview(statusLabel)

        self.view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(canvasView)
        showCurrent()
    }

    // MARK: - Navigation / display

    private func showCurrent(resetZoom: Bool = true) {
        guard let url = browser.currentURL else { return }
        loadGeneration += 1
        let generation = loadGeneration

        updateHUD()

        let maxPixelSize = maxPixelSizeForScreen()
        if let cached = ImageCache.shared.preview(for: url) {
            canvasView.setImage(cached, resetView: resetZoom)
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let image = ImageCache.shared.preview(for: url) ?? ImageLoader.loadPreview(url: url, maxPixelSize: maxPixelSize)
            guard let image else { return }
            ImageCache.shared.store(image, for: url)
            await MainActor.run {
                guard generation == self.loadGeneration else { return }
                self.canvasView.setImage(image, resetView: resetZoom)
            }
        }

        let neighbors = [-2, -1, 1, 2].compactMap { browser.url(offsetFromCurrent: $0) }
        ImageCache.shared.prefetch(urls: neighbors, maxPixelSize: maxPixelSize)

        if exifPinned || exifHovering {
            refreshExifOverlay()
        }
    }

    private func maxPixelSizeForScreen() -> Int {
        let screen = view.window?.screen ?? NSScreen.main
        let scale = screen?.backingScaleFactor ?? 2
        let size = screen?.frame.size ?? CGSize(width: 1920, height: 1080)
        return Int(max(size.width, size.height) * scale)
    }

    private func updateHUD() {
        guard let url = browser.currentURL else { hudLabel.stringValue = ""; return }
        let position = "\(browser.currentIndex + 1) / \(browser.count)"
        let flag = browser.isFlagged(url) ? "  ★ Flagged" : ""
        hudLabel.stringValue = "\(position) — \(url.lastPathComponent)\(flag)"
    }

    private func goTo(delta: Int) {
        guard browser.advance(by: delta) != nil else { return }
        showCurrent()
    }

    // MARK: - Actions

    private func toggleFlag() {
        guard let url = browser.currentURL else { return }
        let newState = browser.toggleFlag(url)
        FinderTagging.setFlagged(newState, on: url)
        updateHUD()
    }

    private func trashCurrent() {
        guard let url = browser.currentURL else { return }
        guard DeleteAction.confirmAndTrash(url) else { return }
        removeAndAdvance(url)
    }

    private func deletePermanentlyCurrent() {
        guard let url = browser.currentURL else { return }
        guard DeleteAction.confirmAndDeletePermanently(url) else { return }
        removeAndAdvance(url)
    }

    private func removeAndAdvance(_ url: URL) {
        browser.remove(url)
        if browser.currentURL == nil {
            closeViewer()
        } else {
            showCurrent()
        }
    }

    /// Files into the auto-organized library (`⌘M` to move, `C` to copy).
    private func fileIntoLibrary(mode: FileOpMode) {
        let targets = browser.filingTargets
        guard !targets.isEmpty else { return }

        guard let home = Preferences.libraryHomeURL, home.isReachableDirectory else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Library Home Not Available"
            alert.informativeText = "No library home folder is set, or it can't be reached right now (e.g. an unmounted drive). Set one with the P key."
            alert.runModal()
            return
        }

        performFileOperation(targets, mode: mode, destinationName: home.lastPathComponent) { urls, reportFileComplete in
            LibraryFiler.file(urls, mode: mode, into: home, onFileComplete: reportFileComplete)
        }
    }

    /// One-off copy to a folder chosen fresh each time (`Shift+C`).
    private func adHocFile(mode: FileOpMode) {
        let targets = browser.filingTargets
        guard !targets.isEmpty else { return }
        guard let destination = AdHocFileOps.chooseFolder(mode: mode) else { return }
        performFileOperation(targets, mode: mode, destinationName: destination.lastPathComponent) { urls, reportFileComplete in
            AdHocFileOps.file(urls, mode: mode, to: destination, onFileComplete: reportFileComplete)
        }
    }

    /// "Move" (`M` / `Shift+M`): move to a remembered-or-chosen destination.
    private func performMoveCommand() {
        let targets = browser.filingTargets
        guard !targets.isEmpty else { return }
        guard let destination = MoveDestinationDialog.chooseDestination() else { return }
        performFileOperation(targets, mode: .move, destinationName: destination.lastPathComponent) { urls, reportFileComplete in
            AdHocFileOps.file(urls, mode: .move, to: destination, onFileComplete: reportFileComplete)
        }
    }

    /// Runs a copy/move `work` closure behind the progress overlay, then
    /// announces it in the status line and applies the usual post-filing
    /// browsing update: on move, remove filed files from the browser
    /// (closing the viewer if none remain); on copy, just refresh the HUD.
    private func performFileOperation(
        _ urls: [URL],
        mode: FileOpMode,
        destinationName: String,
        work: @escaping (_ urls: [URL], _ reportFileComplete: @escaping () -> Void) -> [URL]
    ) {
        progressOverlay.run(mode: mode, fileCount: urls.count, destinationName: destinationName, work: { reportFileComplete in
            work(urls, reportFileComplete)
        }, completion: { [weak self] filed in
            guard let self, !filed.isEmpty else { return }
            let verb = mode == .move ? "Moved" : "Copied"
            let noun = filed.count == 1 ? "file" : "files"
            self.announce("\(verb) \(filed.count) \(noun) to \(destinationName)…")
            if mode == .move {
                let shown = self.browser.remove(filed)
                if shown == nil { self.closeViewer() } else { self.showCurrent(resetZoom: false) }
            } else {
                self.updateHUD()
            }
        })
    }

    private func closeViewer() {
        (view.window?.windowController as? ImageWindowController)?.closeViewer()
    }

    // MARK: - Status line

    /// Shows `summary` immediately, fading it out after 1 second — unless the
    /// cursor is already sitting in the hover corner, in which case it stays
    /// up until the cursor leaves, same as a hover-triggered show.
    private func announce(_ summary: String) {
        lastActionSummary = summary
        presentStatus(autoHideAfter: statusHovering ? nil : 1.0)
    }

    private func setStatusHovering(_ hovering: Bool) {
        guard statusHovering != hovering else { return }
        statusHovering = hovering
        if hovering {
            presentStatus(autoHideAfter: nil)
        } else {
            fadeOutStatus()
        }
    }

    /// Shows the last action's summary. With `autoHideAfter` set, schedules a
    /// fade-out after that delay; with `nil` (hovering), stays up until the
    /// hover ends. Either path cancels a previously scheduled fade-out.
    private func presentStatus(autoHideAfter delay: TimeInterval?) {
        guard let lastActionSummary else { return }
        statusFadeWorkItem?.cancel()
        statusLabel.stringValue = lastActionSummary
        statusLabel.alphaValue = 1

        guard let delay else { return }
        let workItem = DispatchWorkItem { [weak self] in self?.fadeOutStatus() }
        statusFadeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func fadeOutStatus() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            statusLabel.animator().alphaValue = 0
        }
    }

    // MARK: - EXIF panel

    private func handleMouseMoved(_ pointInCanvas: NSPoint) {
        setExifHovering(pointInCanvas.x >= canvasView.bounds.width - exifHotZoneWidth)
        setStatusHovering(
            pointInCanvas.x <= statusHotZoneWidth && pointInCanvas.y >= canvasView.bounds.height - statusHotZoneHeight
        )
    }

    private func setExifHovering(_ hovering: Bool) {
        guard exifHovering != hovering else { return }
        exifHovering = hovering
        updateExifVisibility()
    }

    private func toggleExifPinned() {
        exifPinned.toggle()
        updateExifVisibility()
    }

    private func updateExifVisibility() {
        let visible = exifPinned || exifHovering
        exifOverlay.isHidden = !visible
        if visible {
            refreshExifOverlay()
        }
    }

    private func refreshExifOverlay() {
        guard let url = browser.currentURL else {
            exifOverlay.update(fields: [])
            return
        }
        let fields = exifFieldsCache[url] ?? ExifReader.fields(for: url)
        exifFieldsCache[url] = fields

        let height = exifOverlay.update(fields: fields)
        let x = view.bounds.width - ExifOverlayView.width - exifMargin
        let y = (view.bounds.height - height) / 2
        exifOverlay.frame = NSRect(x: x, y: y, width: ExifOverlayView.width, height: height)
    }

    // MARK: - Key handling

    /// Every action is a single key, no modifier required — Shift only
    /// distinguishes a "harder" variant of the same key (permanent delete vs
    /// trash, ad hoc folder vs auto-organize) rather than gating access to it.
    /// `M`/`⌘M` is the one exception: Command switches "Move" (remembered
    /// destination) to "file into library" instead.
    private func handle(_ event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        let command = event.modifierFlags.contains(.command)

        switch event.keyCode {
        case 123: goTo(delta: -1); return // Left arrow
        case 124: goTo(delta: 1); return  // Right arrow
        case 49: goTo(delta: 1); return   // Space
        case 53: closeViewer(); return    // Esc
        case 51, 117: // Delete/Backspace, Forward Delete
            if shift { deletePermanentlyCurrent() } else { trashCurrent() }
            return
        default: break
        }

        guard let chars = event.charactersIgnoringModifiers?.lowercased() else { return }
        switch chars {
        case "f":
            toggleFlag()
        case "m":
            if command { fileIntoLibrary(mode: .move) } else { performMoveCommand() }
        case "c":
            if shift { adHocFile(mode: .copy) } else { fileIntoLibrary(mode: .copy) }
        case "1":
            canvasView.zoomToActualSize()
        case "0":
            canvasView.zoomToFit()
        case "l":
            Preferences.promptForLocationLabel()
        case "p":
            Preferences.chooseLibraryHome()
        case "d":
            DefaultAppRegistration.makeDefaultForNEF()
        case "e":
            toggleExifPinned()
        case "z":
            Preferences.promptForClickZoomFactor()
        default:
            break
        }
    }
}

private extension URL {
    var isReachableDirectory: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

/// Draws a CGImage centered in the view with a "fit" mode (default), an
/// "actual size" mode, and a click-to-zoom mode — the latter two panned via
/// scroll/trackpad or click-drag.
final class ImageCanvasView: NSView {

    var keyDownHandler: ((NSEvent) -> Void)?
    /// Fires with the mouse location in this view's coordinate space.
    var mouseMovedHandler: ((NSPoint) -> Void)?
    var mouseExitedHandler: (() -> Void)?

    private var image: CGImage?
    private var offset: CGPoint = .zero
    /// `clicked`'s point is in image pixel space (same units as the image's
    /// width/height), with the same up/down convention `draw`'s rect uses.
    private enum ZoomMode: Equatable { case fit, actualSize, clicked(imagePoint: CGPoint) }
    private var mode: ZoomMode = .fit

    /// Distinguishes a plain click (toggles click-zoom) from a click-drag
    /// (pans) — a drag is only recognized once the mouse moves past this
    /// many points from where the button went down.
    private let dragThreshold: CGFloat = 3
    private var dragOrigin: NSPoint = .zero
    private var dragStartOffset: CGPoint = .zero
    private var isDragging = false

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if let keyDownHandler {
            keyDownHandler(event)
        } else {
            super.keyDown(with: event)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        mouseMovedHandler?(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        mouseExitedHandler?()
    }

    func setImage(_ image: CGImage?, resetView: Bool) {
        self.image = image
        if resetView {
            mode = .fit
            offset = .zero
        }
        needsDisplay = true
    }

    func zoomToFit() {
        mode = .fit
        offset = .zero
        needsDisplay = true
    }

    func zoomToActualSize() {
        mode = .actualSize
        offset = .zero
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        guard mode != .fit, let image else { return }
        let imgSize = CGSize(width: image.width, height: image.height)
        let proposed = CGPoint(x: offset.x + event.scrollingDeltaX, y: offset.y - event.scrollingDeltaY)
        offset = clampedOffset(proposed, mode: mode, imgSize: imgSize)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = convert(event.locationInWindow, from: nil)
        dragStartOffset = offset
        isDragging = false
    }

    /// While zoomed in, dragging pans instead of registering as a click.
    override func mouseDragged(with event: NSEvent) {
        guard mode != .fit, let image else { return }
        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - dragOrigin.x
        let dy = point.y - dragOrigin.y
        if !isDragging && hypot(dx, dy) > dragThreshold {
            isDragging = true
        }
        guard isDragging else { return }
        let imgSize = CGSize(width: image.width, height: image.height)
        let proposed = CGPoint(x: dragStartOffset.x + dx, y: dragStartOffset.y + dy)
        offset = clampedOffset(proposed, mode: mode, imgSize: imgSize)
        needsDisplay = true
    }

    /// A plain click (not a drag) zooms in on the clicked region (centered),
    /// at `Preferences.clickZoomFactor` times "fit" scale; clicking again
    /// while zoomed in this way zooms back out to fit.
    override func mouseUp(with event: NSEvent) {
        guard !isDragging else { isDragging = false; return }
        guard let image else { return }
        let imgSize = CGSize(width: image.width, height: image.height)
        guard imgSize.width > 0, imgSize.height > 0 else { return }

        if case .clicked = mode {
            mode = .fit
            offset = .zero
            needsDisplay = true
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let (scale, origin) = layout(for: mode, imgSize: imgSize)
        let imagePoint = CGPoint(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
        mode = .clicked(imagePoint: imagePoint)
        offset = .zero
        needsDisplay = true
    }

    /// Scale, draw size, and the offset-`.zero` origin for `mode` — i.e. where
    /// the image sits before any user pan is applied.
    private func geometry(for mode: ZoomMode, imgSize: CGSize) -> (scale: CGFloat, drawSize: CGSize, baseOrigin: CGPoint) {
        let fitScale = min(bounds.width / imgSize.width, bounds.height / imgSize.height)
        let scale: CGFloat
        let baseOrigin: CGPoint
        switch mode {
        case .fit:
            scale = fitScale
            baseOrigin = CGPoint(x: bounds.midX - imgSize.width * scale / 2, y: bounds.midY - imgSize.height * scale / 2)
        case .actualSize:
            scale = 1.0 / (window?.backingScaleFactor ?? 1.0)
            baseOrigin = CGPoint(x: bounds.midX - imgSize.width * scale / 2, y: bounds.midY - imgSize.height * scale / 2)
        case .clicked(let imagePoint):
            scale = fitScale * Preferences.clickZoomFactor
            baseOrigin = CGPoint(x: bounds.midX - imagePoint.x * scale, y: bounds.midY - imagePoint.y * scale)
        }
        return (scale, CGSize(width: imgSize.width * scale, height: imgSize.height * scale), baseOrigin)
    }

    /// Scale and draw-rect origin for `mode`, given the current bounds and pan `offset`.
    private func layout(for mode: ZoomMode, imgSize: CGSize) -> (scale: CGFloat, origin: CGPoint) {
        let (scale, drawSize, base) = geometry(for: mode, imgSize: imgSize)
        guard mode != .fit else { return (scale, base) }
        let origin = CGPoint(x: base.x + offset.x, y: base.y + offset.y)
        return (scale, clampedToFillBounds(origin: origin, drawSize: drawSize))
    }

    /// Clamps a prospective pan `offset` so the resulting origin never leaves
    /// black void visible — done at the point `offset` is set (not just at
    /// draw time) so a pan that hits the edge doesn't keep accumulating
    /// "phantom" distance that then has to be unwound before the image
    /// visually moves back the other way.
    private func clampedOffset(_ proposedOffset: CGPoint, mode: ZoomMode, imgSize: CGSize) -> CGPoint {
        let (_, drawSize, base) = geometry(for: mode, imgSize: imgSize)
        let origin = CGPoint(x: base.x + proposedOffset.x, y: base.y + proposedOffset.y)
        let clampedOrigin = clampedToFillBounds(origin: origin, drawSize: drawSize)
        return CGPoint(x: clampedOrigin.x - base.x, y: clampedOrigin.y - base.y)
    }

    /// Keeps a zoomed-in image covering the view on each axis where it's
    /// large enough to (preventing black void at the edges); on an axis
    /// where the image is still smaller than the view, centers it instead.
    private func clampedToFillBounds(origin: CGPoint, drawSize: CGSize) -> CGPoint {
        func clampAxis(_ value: CGFloat, contentLength: CGFloat, viewLength: CGFloat) -> CGFloat {
            guard contentLength > viewLength else {
                return (viewLength - contentLength) / 2
            }
            return min(max(value, viewLength - contentLength), 0)
        }
        return CGPoint(
            x: clampAxis(origin.x, contentLength: drawSize.width, viewLength: bounds.width),
            y: clampAxis(origin.y, contentLength: drawSize.height, viewLength: bounds.height)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        dirtyRect.fill()
        guard let image else { return }

        let imgSize = CGSize(width: image.width, height: image.height)
        guard imgSize.width > 0, imgSize.height > 0 else { return }

        let (scale, origin) = layout(for: mode, imgSize: imgSize)
        let drawSize = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
        let rect = CGRect(origin: origin, size: drawSize)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: rect)
    }
}
