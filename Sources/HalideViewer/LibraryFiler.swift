import Foundation

enum FileOpMode { case move, copy }

/// Auto-organize filing: <home>/<year>/<month>/<optional location label>/filename,
/// where year/month come from the photo's EXIF capture date.
enum LibraryFiler {

    /// Returns the source URLs that were successfully filed.
    static func file(_ urls: [URL], mode: FileOpMode, into home: URL) -> [URL] {
        var succeeded: [URL] = []
        let label = Preferences.sessionLocationLabel

        for url in urls {
            let date = ImageLoader.exifCaptureDate(url: url)
                ?? (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
                ?? Date()
            let year = String(Calendar.current.component(.year, from: date))
            let month = String(format: "%02d", Calendar.current.component(.month, from: date))

            var destDir = home.appendingPathComponent(year).appendingPathComponent(month)
            if !label.isEmpty {
                destDir.appendPathComponent(label)
            }

            do {
                try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
                let destURL = uniqueDestination(for: url, in: destDir)
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

    /// Appends " 2", " 3", ... before the extension if the destination filename already exists.
    static func uniqueDestination(for sourceURL: URL, in directory: URL) -> URL {
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        var candidate = directory.appendingPathComponent(sourceURL.lastPathComponent)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            candidate = directory.appendingPathComponent(name)
            n += 1
        }
        return candidate
    }
}
