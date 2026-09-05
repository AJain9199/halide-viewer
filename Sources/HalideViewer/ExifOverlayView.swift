import AppKit

/// Floating right-side panel listing EXIF fields for the current image.
/// Rows are plain NSTextFields laid out with explicit frames (top-down, via
/// `isFlipped`), matching the rest of the app's non-autolayout style.
final class ExifOverlayView: NSView {

    static let width: CGFloat = 240

    private let labelFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
    private let valueFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    private let rowGap: CGFloat = 10
    private let padding: CGFloat = 16

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        layer?.cornerRadius = 10
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Rebuilds the row subviews for `fields` and returns the height needed
    /// to show them all at `Self.width`.
    @discardableResult
    func update(fields: [ExifField]) -> CGFloat {
        subviews.forEach { $0.removeFromSuperview() }
        guard !fields.isEmpty else { return 0 }

        let rowWidth = Self.width - padding * 2
        let labelHeight = labelFont.pointSize + 2
        let valueHeight = valueFont.pointSize + 4
        var y = padding

        for field in fields {
            let labelField = makeField(field.label.uppercased(), font: labelFont, color: NSColor.white.withAlphaComponent(0.55))
            labelField.frame = NSRect(x: padding, y: y, width: rowWidth, height: labelHeight)
            addSubview(labelField)
            y += labelHeight

            let valueField = makeField(field.value, font: valueFont, color: .white)
            valueField.lineBreakMode = .byTruncatingTail
            valueField.frame = NSRect(x: padding, y: y, width: rowWidth, height: valueHeight)
            addSubview(valueField)
            y += valueHeight + rowGap
        }

        return y - rowGap + padding
    }

    private func makeField(_ string: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: string)
        field.font = font
        field.textColor = color
        return field
    }
}
