import AppKit

final class ImageViewController: NSViewController {

    let browser: FolderBrowser
    let canvasView = ImageCanvasView()
    private let hudLabel = NSTextField(labelWithString: "")
    private var loadGeneration = 0

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
        container.addSubview(canvasView)

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
        default:
            break
        }
    }
}

/// Draws a CGImage centered in the view with a "fit" mode (default) and an
/// "actual size" mode (pixel-for-pixel, panned via scroll/trackpad).
final class ImageCanvasView: NSView {

    var keyDownHandler: ((NSEvent) -> Void)?

    private var image: CGImage?
    private var offset: CGPoint = .zero
    private enum ZoomMode { case fit, actualSize }
    private var mode: ZoomMode = .fit

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if let keyDownHandler {
            keyDownHandler(event)
        } else {
            super.keyDown(with: event)
        }
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
        guard mode == .actualSize else { return }
        offset.x += event.scrollingDeltaX
        offset.y -= event.scrollingDeltaY
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        dirtyRect.fill()
        guard let image else { return }

        let imgSize = CGSize(width: image.width, height: image.height)
        guard imgSize.width > 0, imgSize.height > 0 else { return }

        let scale: CGFloat
        switch mode {
        case .fit:
            scale = min(bounds.width / imgSize.width, bounds.height / imgSize.height)
        case .actualSize:
            scale = 1.0 / (window?.backingScaleFactor ?? 1.0)
        }

        let drawSize = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
        let origin = CGPoint(
            x: bounds.midX - drawSize.width / 2 + offset.x,
            y: bounds.midY - drawSize.height / 2 + offset.y
        )
        let rect = CGRect(origin: origin, size: drawSize)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: rect)
    }
}
