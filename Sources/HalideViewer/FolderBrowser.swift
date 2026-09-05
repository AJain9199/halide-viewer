import Foundation

/// Enumerates sibling image files next to an opened file and tracks
/// browsing position + which files are flagged as keepers within this session.
final class FolderBrowser {

    static let supportedExtensions: Set<String> = [
        "nef", "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff",
        "cr2", "cr3", "arw", "dng", "orf", "rw2", "raf"
    ]

    private(set) var files: [URL]
    private(set) var currentIndex: Int
    private(set) var flagged: Set<URL> = []

    init?(openingFile url: URL) {
        let folder = url.deletingLastPathComponent()
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let images = entries.filter { entry in
            FolderBrowser.supportedExtensions.contains(entry.pathExtension.lowercased())
        }.sorted { a, b in
            a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }

        guard !images.isEmpty else { return nil }
        self.files = images

        if let idx = images.firstIndex(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
            self.currentIndex = idx
        } else {
            // File itself wasn't in the supported set (unlikely) or was filtered out; fall back to first.
            self.files = ([url] + images)
            self.currentIndex = 0
        }
    }

    var currentURL: URL? {
        guard files.indices.contains(currentIndex) else { return nil }
        return files[currentIndex]
    }

    var count: Int { files.count }

    @discardableResult
    func advance(by delta: Int) -> URL? {
        guard !files.isEmpty else { return nil }
        let newIndex = currentIndex + delta
        guard files.indices.contains(newIndex) else { return currentURL }
        currentIndex = newIndex
        return currentURL
    }

    func url(offsetFromCurrent offset: Int) -> URL? {
        let idx = currentIndex + offset
        guard files.indices.contains(idx) else { return nil }
        return files[idx]
    }

    func toggleFlag(_ url: URL) -> Bool {
        if flagged.contains(url) {
            flagged.remove(url)
            return false
        } else {
            flagged.insert(url)
            return true
        }
    }

    func isFlagged(_ url: URL) -> Bool {
        flagged.contains(url)
    }

    /// Files to act on for a batch filing operation: the flagged set if
    /// non-empty, otherwise just the current file.
    var filingTargets: [URL] {
        if !flagged.isEmpty {
            return files.filter { flagged.contains($0) }
        } else if let current = currentURL {
            return [current]
        }
        return []
    }

    /// Remove a file from the browsing list after it has been deleted/moved,
    /// keeping the current position sensible. Returns the URL now being shown, if any.
    @discardableResult
    func remove(_ url: URL) -> URL? {
        flagged.remove(url)
        guard let idx = files.firstIndex(of: url) else { return currentURL }
        files.remove(at: idx)
        if files.isEmpty {
            currentIndex = 0
            return nil
        }
        if idx < currentIndex || (idx == currentIndex && currentIndex == files.count) {
            currentIndex = max(0, currentIndex - 1)
        } else if idx == currentIndex {
            currentIndex = min(currentIndex, files.count - 1)
        }
        return currentURL
    }

    /// Remove several files at once (batch filing), keeping the current
    /// position sensible. Returns the URL now being shown, if any.
    @discardableResult
    func remove(_ urls: [URL]) -> URL? {
        let removeSet = Set(urls)
        flagged.subtract(removeSet)
        let currentlyShown = currentURL
        files.removeAll { removeSet.contains($0) }
        if files.isEmpty {
            currentIndex = 0
            return nil
        }
        if let shown = currentlyShown, let idx = files.firstIndex(of: shown) {
            currentIndex = idx
        } else {
            currentIndex = min(currentIndex, files.count - 1)
        }
        return currentURL
    }
}
