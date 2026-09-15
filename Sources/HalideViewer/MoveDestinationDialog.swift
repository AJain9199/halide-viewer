import AppKit

/// Prompts for a "Move" destination: a dropdown of recently used folders
/// (with a "Choose Folder…" entry to add a new one), pre-selected to the
/// most recently used destination. The very first time, with no history
/// yet, this just opens a folder picker directly.
enum MoveDestinationDialog {

    static func chooseDestination() -> URL? {
        guard !Preferences.recentMoveDestinations.isEmpty else {
            guard let url = AdHocFileOps.chooseFolder(mode: .move) else { return nil }
            Preferences.rememberMoveDestination(url)
            return url
        }

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
        let coordinator = DestinationPopUpCoordinator(popup: popup)
        popup.target = coordinator
        popup.action = #selector(DestinationPopUpCoordinator.selectionChanged(_:))

        let alert = NSAlert()
        alert.messageText = "Move To…"
        alert.informativeText = "Choose a destination folder, or pick a recent one."
        alert.accessoryView = popup
        let move = alert.addButton(withTitle: "Move")
        move.keyEquivalent = "\r"
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\u{1b}"

        guard alert.runModal() == .alertFirstButtonReturn, let destination = coordinator.selected else {
            return nil
        }
        Preferences.rememberMoveDestination(destination)
        return destination
    }
}

/// Backs the destination popup: handles the "Choose Folder…" sentinel item
/// by opening a folder picker inline and inserting the result at the top.
private final class DestinationPopUpCoordinator: NSObject {
    private static let chooseFolderTag = -1

    private let popup: NSPopUpButton
    private var recents: [URL]
    private(set) var selected: URL?

    init(popup: NSPopUpButton) {
        self.popup = popup
        self.recents = Preferences.recentMoveDestinations
        self.selected = recents.first
        super.init()
        rebuild()
    }

    @objc func selectionChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        if item.tag == Self.chooseFolderTag {
            if let url = AdHocFileOps.chooseFolder(mode: .move) {
                recents.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
                recents.insert(url, at: 0)
                selected = url
            }
            rebuild()
        } else {
            selected = recents[item.tag]
        }
    }

    private func rebuild() {
        guard let menu = popup.menu else { return }
        menu.removeAllItems()
        for (index, url) in recents.enumerated() {
            let item = NSMenuItem(title: url.path, action: nil, keyEquivalent: "")
            item.tag = index
            item.toolTip = url.path
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let chooseItem = NSMenuItem(title: "Choose Folder…", action: nil, keyEquivalent: "")
        chooseItem.tag = Self.chooseFolderTag
        menu.addItem(chooseItem)

        if let selected, let index = recents.firstIndex(where: { $0.standardizedFileURL == selected.standardizedFileURL }) {
            popup.selectItem(at: index)
        } else {
            popup.selectItem(at: 0)
        }
    }
}
