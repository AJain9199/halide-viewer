import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: ImageWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMinimalMenu()

        let args = CommandLine.arguments.dropFirst()
        if let path = args.first {
            open(URL(fileURLWithPath: path))
        } else {
            // Give application(_:open:) a moment to fire (double-click on a
            // document routes through it); otherwise fall back to a picker.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, self.windowController == nil else { return }
                self.openViaPicker()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let first = urls.first, windowController == nil else { return }
        open(first)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func open(_ url: URL) {
        guard let browser = FolderBrowser(openingFile: url) else {
            let alert = NSAlert()
            alert.messageText = "Couldn't open this file"
            alert.informativeText = url.lastPathComponent
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        let controller = ImageWindowController(browser: browser)
        windowController = controller
        controller.showFullscreen()
        DefaultAppRegistration.promptOnFirstLaunchIfNeeded()
    }

    private func openViaPicker() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Image"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else {
            NSApp.terminate(nil)
            return
        }
        open(url)
    }

    private func buildMinimalMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        // No key equivalent here — press "D" while viewing (handled in
        // ImageViewController) instead of a Cmd-chord; this stays as a
        // mouse-reachable fallback for when the menu bar isn't hidden.
        let makeDefaultItem = NSMenuItem(
            title: "Make Default for NEF Files…",
            action: #selector(makeDefaultForNEF),
            keyEquivalent: ""
        )
        makeDefaultItem.target = self
        appMenu.addItem(makeDefaultItem)

        appMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Halide Viewer",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func makeDefaultForNEF() {
        DefaultAppRegistration.makeDefaultForNEF()
    }
}
