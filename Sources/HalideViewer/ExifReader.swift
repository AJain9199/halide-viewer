import Foundation
import ImageIO

struct ExifField {
    let label: String
    let value: String
}

/// Reads a curated subset of EXIF/TIFF metadata for display in the on-screen
/// EXIF panel (see `ExifOverlayView`). Order here is display order.
enum ExifReader {

    static func fields(for url: URL) -> [ExifField] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return []
        }

        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]

        var fields: [ExifField] = []

        if let width = props[kCGImagePropertyPixelWidth] as? Int,
           let height = props[kCGImagePropertyPixelHeight] as? Int {
            fields.append(ExifField(label: "Dimensions", value: "\(width) × \(height)"))
        }
        if let make = tiff?[kCGImagePropertyTIFFMake] as? String {
            fields.append(ExifField(label: "Make", value: make))
        }
        if let model = tiff?[kCGImagePropertyTIFFModel] as? String {
            fields.append(ExifField(label: "Model", value: model))
        }
        if let lens = exif?[kCGImagePropertyExifLensModel] as? String {
            fields.append(ExifField(label: "Lens", value: lens))
        }
        if let focalLength = exif?[kCGImagePropertyExifFocalLength] as? Double {
            fields.append(ExifField(label: "Focal Length", value: "\(Int(focalLength.rounded())) mm"))
        }
        if let fNumber = exif?[kCGImagePropertyExifFNumber] as? Double {
            fields.append(ExifField(label: "Aperture", value: String(format: "f/%.1f", fNumber)))
        }
        if let exposureTime = exif?[kCGImagePropertyExifExposureTime] as? Double {
            fields.append(ExifField(label: "Shutter", value: formatExposureTime(exposureTime)))
        }
        if let iso = (exif?[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first {
            fields.append(ExifField(label: "ISO", value: "\(iso)"))
        }
        if let raw = exif?[kCGImagePropertyExifDateTimeOriginal] as? String,
           let formatted = formatExifDate(raw) {
            fields.append(ExifField(label: "Captured", value: formatted))
        }

        return fields
    }

    private static func formatExposureTime(_ seconds: Double) -> String {
        guard seconds > 0 else { return "0s" }
        if seconds >= 1 {
            return String(format: "%.1fs", seconds)
        }
        return "1/\(Int((1.0 / seconds).rounded()))s"
    }

    private static func formatExifDate(_ raw: String) -> String? {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        guard let date = parser.date(from: raw) else { return nil }

        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .short
        return display.string(from: date)
    }
}
