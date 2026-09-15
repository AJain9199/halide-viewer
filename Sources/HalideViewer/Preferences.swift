import AppKit

enum Preferences {
    private static let defaults = UserDefaults.standard
    private static let libraryHomeKey = "libraryHomePath"
    private static let locationLabelKey = "sessionLocationLabel"
    private static let hasPromptedDefaultAppKey = "hasPromptedDefaultApp"
    private static let clickZoomFactorKey = "clickZoomFactor"
    private static let recentMoveDestinationsKey = "recentMoveDestinations"
    private static let maxRecentMoveDestinations = 5
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

    /// Most-recently-used "Move To…" destinations, newest first.
    static var recentMoveDestinations: [URL] {
        get {
            let paths = defaults.stringArray(forKey: recentMoveDestinationsKey) ?? []
            return paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
        }
        set {
            defaults.set(Array(newValue.prefix(maxRecentMoveDestinations)).map(\.path), forKey: recentMoveDestinationsKey)
        }
    }

    /// Promotes `url` to the front of the recent move destinations, adding it if new.
    static func rememberMoveDestination(_ url: URL) {
        var recents = recentMoveDestinations
        recents.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        recents.insert(url, at: 0)
        recentMoveDestinations = recents
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
