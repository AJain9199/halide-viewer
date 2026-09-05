import Foundation
import ImageIO
import CoreImage
import CoreGraphics

/// Fast display path uses ImageIO to pull the embedded full-resolution JPEG
/// preview straight out of a RAW file (no demosaic — near instant). Full RAW
/// decode via CIRAWFilter only happens on demand when the user zooms in.
enum ImageLoader {

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    static func loadPreview(url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Full-resolution decode for pixel-level zoom. Falls back to a
    /// large ImageIO thumbnail for formats CIRAWFilter doesn't handle.
    static func loadFullResolution(url: URL, draft: Bool) -> CGImage? {
        if let filter = CIRAWFilter(imageURL: url) {
            filter.isDraftModeEnabled = draft
            if let output = filter.outputImage,
               let cgImage = ciContext.createCGImage(output, from: output.extent) {
                return cgImage
            }
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 8000,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func exifCaptureDate(url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: raw)
    }
}
