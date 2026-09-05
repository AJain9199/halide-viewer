import Foundation

/// Uses real Finder tags as the "keeper flag" mechanism so flagged files
/// show up tagged in Finder/Spotlight too.
enum FinderTagging {

    static let flagTagName = "Flagged"

    static func isFlagged(_ url: URL) -> Bool {
        currentTags(url).contains(flagTagName)
    }

    /// Read-modify-write the tag array so other tags the user already has
    /// on the file are preserved.
    @discardableResult
    static func setFlagged(_ flagged: Bool, on url: URL) -> Bool {
        var tags = currentTags(url)
        if flagged {
            if !tags.contains(flagTagName) { tags.append(flagTagName) }
        } else {
            tags.removeAll { $0 == flagTagName }
        }
        do {
            try (url as NSURL).setResourceValue(tags as NSArray, forKey: .tagNamesKey)
            return true
        } catch {
            return false
        }
    }

    private static func currentTags(_ url: URL) -> [String] {
        (try? url.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
    }
}
