import AppKit

/// One-off move/copy to an arbitrary folder chosen via a picker, outside the
/// auto-organize library structure.
enum AdHocFileOps {

    /// Returns the source URLs that were successfully moved/copied.
    static func chooseFolderAndFile(_ urls: [URL], mode: FileOpMode) -> [URL] {
        let panel = NSOpenPanel()
        panel.title = mode == .move ? "Move To…" : "Copy To…"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let dest = panel.url else { return [] }

        var succeeded: [URL] = []
        for url in urls {
            let destURL = LibraryFiler.uniqueDestination(for: url, in: dest)
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
