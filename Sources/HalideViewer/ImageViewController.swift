import AppKit

final class ImageViewController: NSViewController {

    let browser: FolderBrowser
    let canvasView = ImageCanvasView()
    private let hudLabel = NSTextField(labelWithString: "")
    private let exifOverlay = ExifOverlayView(frame: .zero)
    private var loadGeneration = 0

    /// EXIF panel visibility: `E` toggles a persistent pin; hovering the
    /// right edge of the screen shows it temporarily on top of that.
    private var exifPinned = false
    private var exifHovering = false
    private var exifFieldsCache: [URL: [ExifField]] = [:]
    private let exifHotZoneWidth: CGFloat = 48
    private let exifMargin: CGFloat = 20

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
        canvasView.mouseExitedHandler = { [weak self] in self?.setExifHovering(false) }
        container.addSubview(canvasView)

        exifOverlay.isHidden = true
        container.addSubview(exifOverlay)

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

    private func fileIntoLibrary(mode: FileOpMode) {
        let targets = browser.filingTargets
        guard !targets.isEmpty else { return }
        guard let home = Preferences.ensureLibraryHome() else { return }
        let filed = LibraryFiler.file(targets, mode: mode, into: home)
        guard !filed.isEmpty else { return }
        if mode == .move {
            let shown = browser.remove(filed)
            if shown == nil { closeViewer() } else { showCurrent(resetZoom: false) }
        } else {
            updateHUD()
        }
    }

    private func adHocFile(mode: FileOpMode) {
        let targets = browser.filingTargets
        guard !targets.isEmpty else { return }
        let succeeded = AdHocFileOps.chooseFolderAndFile(targets, mode: mode)
        guard !succeeded.isEmpty else { return }
        if mode == .move {
            let shown = browser.remove(succeeded)
            if shown == nil { closeViewer() } else { showCurrent(resetZoom: false) }
        } else {
            updateHUD()
        }
    }

    private func closeViewer() {
        (view.window?.windowController as? ImageWindowController)?.closeViewer()
    }

    // MARK: - EXIF panel

    private func handleMouseMoved(_ pointInCanvas: NSPoint) {
        setExifHovering(pointInCanvas.x >= canvasView.bounds.width - exifHotZoneWidth)
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
    private func handle(_ event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)

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
            if shift { adHocFile(mode: .move) } else { fileIntoLibrary(mode: .move) }
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
        guard mode != .fit else { return }
        offset.x += event.scrollingDeltaX
        offset.y -= event.scrollingDeltaY
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = convert(event.locationInWindow, from: nil)
        dragStartOffset = offset
        isDragging = false
    }

    /// While zoomed in, dragging pans instead of registering as a click.
    override func mouseDragged(with event: NSEvent) {
        guard mode != .fit else { return }
        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - dragOrigin.x
        let dy = point.y - dragOrigin.y
        if !isDragging && hypot(dx, dy) > dragThreshold {
            isDragging = true
        }
        guard isDragging else { return }
        offset = CGPoint(x: dragStartOffset.x + dx, y: dragStartOffset.y + dy)
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

    /// Scale and draw-rect origin for `mode`, given the current bounds.
    private func layout(for mode: ZoomMode, imgSize: CGSize) -> (scale: CGFloat, origin: CGPoint) {
        let fitScale = min(bounds.width / imgSize.width, bounds.height / imgSize.height)
        switch mode {
        case .fit:
            let drawSize = CGSize(width: imgSize.width * fitScale, height: imgSize.height * fitScale)
            let origin = CGPoint(x: bounds.midX - drawSize.width / 2 + offset.x, y: bounds.midY - drawSize.height / 2 + offset.y)
            return (fitScale, origin)
        case .actualSize:
            let scale = 1.0 / (window?.backingScaleFactor ?? 1.0)
            let drawSize = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
            let origin = CGPoint(x: bounds.midX - drawSize.width / 2 + offset.x, y: bounds.midY - drawSize.height / 2 + offset.y)
            return (scale, origin)
        case .clicked(let imagePoint):
            let scale = fitScale * Preferences.clickZoomFactor
            let origin = CGPoint(x: bounds.midX - imagePoint.x * scale + offset.x, y: bounds.midY - imagePoint.y * scale + offset.y)
            return (scale, origin)
        }
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
