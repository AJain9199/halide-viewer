import AppKit

/// Plain NSWindow only becomes key/main if it has a title bar; a borderless
/// window is silently ignored by the key-window machinery unless this is
/// overridden, which is why keyboard input didn't reach the app at all.
private final class BorderlessKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// A borderless, screen-sized window — deliberately not the animated macOS
/// full-screen API (which switches Spaces and slides in). This opens
/// instantly with a FastStone-style kiosk look.
final class ImageWindowController: NSWindowController {

    convenience init(browser: FolderBrowser) {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let window = BorderlessKeyWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.level = .normal
        window.isReleasedWhenClosed = false

        let viewController = ImageViewController(browser: browser)
        window.contentViewController = viewController

        self.init(window: window)
    }

    func showFullscreen() {
        guard let window else { return }
        window.setFrame(NSScreen.main?.frame ?? window.frame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = [.hideMenuBar, .hideDock]
        if let canvas = (window.contentViewController as? ImageViewController)?.canvasView {
            window.makeFirstResponder(canvas)
        }
    }

    func closeViewer() {
        NSApp.presentationOptions = []
        window?.close()
        NSApp.terminate(nil)
    }
}
