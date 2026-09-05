import AppKit

enum Preferences {
    private static let defaults = UserDefaults.standard
    private static let libraryHomeKey = "libraryHomePath"
    private static let locationLabelKey = "sessionLocationLabel"
    private static let hasPromptedDefaultAppKey = "hasPromptedDefaultApp"
    private static let clickZoomFactorKey = "clickZoomFactor"
    static let defaultClickZoomFactor: CGFloat = 2.5

    static var libraryHomeURL: URL? {
        get {
            guard let path = defaults.string(forKey: libraryHomeKey) else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        set { defaults.set(newValue?.path, forKey: libraryHomeKey) }
    }

    static var sessionLocationLabel: String {
        get { defaults.string(forKey: locationLabelKey) ?? "" }
        set { defaults.set(newValue, forKey: locationLabelKey) }
    }

    static var hasPromptedDefaultApp: Bool {
        get { defaults.bool(forKey: hasPromptedDefaultAppKey) }
        set { defaults.set(newValue, forKey: hasPromptedDefaultAppKey) }
    }

    /// Multiplier applied on top of "fit" scale when click-to-zoom engages.
    static var clickZoomFactor: CGFloat {
        get {
            let stored = defaults.double(forKey: clickZoomFactorKey)
            return stored > 0 ? CGFloat(stored) : defaultClickZoomFactor
        }
        set { defaults.set(Double(newValue), forKey: clickZoomFactorKey) }
    }

    /// Ensures a library home folder is set, prompting via NSOpenPanel if needed.
    /// Returns nil if the user cancels.
    @discardableResult
    static func ensureLibraryHome() -> URL? {
        if let existing = libraryHomeURL { return existing }
        let panel = NSOpenPanel()
        panel.title = "Choose Photo Library Folder"
        panel.message = "Filed photos will be organized as <this folder>/<year>/<month>/<location>."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        libraryHomeURL = url
        return url
    }

    /// Lets the user change the library home folder from Preferences.
    static func chooseLibraryHome() {
        let panel = NSOpenPanel()
        panel.title = "Choose Photo Library Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if let existing = libraryHomeURL {
            panel.directoryURL = existing
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        libraryHomeURL = url
    }

    /// Prompts for a free-text session location label via a simple alert + text field.
    static func promptForLocationLabel() {
        let alert = NSAlert()
        alert.messageText = "Session Location Label"
        alert.informativeText = "Optional label appended to the filed path, e.g. \"Yosemite\". Leave blank for none."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = sessionLocationLabel
        alert.accessoryView = field
        let ok = alert.addButton(withTitle: "Set")
        ok.keyEquivalent = "\r"
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\u{1b}"
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        sessionLocationLabel = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Prompts for the click-to-zoom multiplier via a simple alert + text field.
    static func promptForClickZoomFactor() {
        let alert = NSAlert()
        alert.messageText = "Click-to-Zoom Factor"
        alert.informativeText = "How much clicking on the image zooms in, as a multiple of \"fit\" size, e.g. \"2.5\"."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = String(format: "%.2g", clickZoomFactor)
        alert.accessoryView = field
        let ok = alert.addButton(withTitle: "Set")
        ok.keyEquivalent = "\r"
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\u{1b}"
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let value = Double(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)), value > 1 {
            clickZoomFactor = CGFloat(value)
        }
    }
}
