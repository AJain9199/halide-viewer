import AppKit

/// One-off move/copy to an arbitrary folder, outside the auto-organize
/// library structure. `chooseFolder` picks the destination; `file` performs
/// the operation once a destination is known (shared by the ad hoc picker
/// and `MoveDestinationDialog`'s remembered destinations).
enum AdHocFileOps {

    static func chooseFolder(mode: FileOpMode) -> URL? {
        let panel = NSOpenPanel()
        panel.title = mode == .move ? "Move To…" : "Copy To…"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Returns the source URLs that were successfully moved/copied.
    /// `onFileComplete` fires once per source URL, whether or not it succeeded.
    @discardableResult
    static func file(_ urls: [URL], mode: FileOpMode, to destination: URL, onFileComplete: () -> Void = {}) -> [URL] {
        var succeeded: [URL] = []
        for url in urls {
            defer { onFileComplete() }
            let destURL = LibraryFiler.uniqueDestination(for: url, in: destination)
            do {
                switch mode {
                case .move: try FileManager.default.moveItem(at: url, to: destURL)
                case .copy: try FileManager.default.copyItem(at: url, to: destURL)
                }
                succeeded.append(url)
            } catch {
                continue
            }
        }
        return succeeded
    }
}
