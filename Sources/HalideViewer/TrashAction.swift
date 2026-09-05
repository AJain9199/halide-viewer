import AppKit

/// Two-tier delete: Trash (recoverable) and permanent, each behind a
/// confirmation dialog where Return confirms and Esc cancels.
enum DeleteAction {

    @discardableResult
    static func confirmAndTrash(_ url: URL) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Move to Trash?"
        alert.informativeText = url.lastPathComponent
        addConfirmCancel(to: alert, confirmTitle: "Move to Trash")

        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return true
        } catch {
            // This volume/location doesn't support a Trash — fall back to permanent delete.
            return confirmAndDeletePermanently(
                url,
                reason: "This location doesn't support the Trash, so the file can only be deleted permanently."
            )
        }
    }

    @discardableResult
    static func confirmAndDeletePermanently(_ url: URL, reason: String? = nil) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Permanently Delete?"
        var info = "\(url.lastPathComponent)\nThis cannot be undone."
        if let reason {
            info = "\(reason)\n\n\(info)"
        }
        alert.informativeText = info
        addConfirmCancel(to: alert, confirmTitle: "Delete Permanently")

        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    private static func addConfirmCancel(to alert: NSAlert, confirmTitle: String) {
        let confirm = alert.addButton(withTitle: confirmTitle)
        confirm.keyEquivalent = "\r"
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\u{1b}"
    }
}
