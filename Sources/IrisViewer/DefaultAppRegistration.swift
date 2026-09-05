import AppKit
import UniformTypeIdentifiers

enum DefaultAppRegistration {

    static func makeDefaultForNEF(completion: ((Bool) -> Void)? = nil) {
        guard let type = UTType(filenameExtension: "nef") else {
            completion?(false)
            return
        }
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type) { error in
            DispatchQueue.main.async {
                completion?(error == nil)
            }
        }
    }

    /// Shown once on first launch, since the app's menu bar is hidden while
    /// browsing and this setting is otherwise easy to miss.
    static func promptOnFirstLaunchIfNeeded() {
        guard !Preferences.hasPromptedDefaultApp else { return }
        Preferences.hasPromptedDefaultApp = true

        let alert = NSAlert()
        alert.messageText = "Make IrisViewer the default for NEF files?"
        alert.informativeText = "Double-clicking a .nef file in Finder will open it in IrisViewer."
        let yes = alert.addButton(withTitle: "Make Default")
        yes.keyEquivalent = "\r"
        let later = alert.addButton(withTitle: "Not Now")
        later.keyEquivalent = "\u{1b}"
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        makeDefaultForNEF()
    }
}
