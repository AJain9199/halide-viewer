import AppKit

/// A small centered overlay with a determinate progress bar, shown while a
/// copy/move `work` closure runs on a background queue, then hidden.
///
/// This is a plain subview of the app's own window rather than a separate
/// `NSPanel` — ordering a whole extra window in/out while the app runs with
/// `NSApp.presentationOptions = [.hideMenuBar, .hideDock]` is expensive (the
/// window server has to reconcile the auto-hidden menu bar/dock against
/// another window coming to front), which made a per-operation panel feel
/// sluggish even for a single fast file. A subview toggle has none of that
/// overhead.
final class ProgressOverlayView: NSView {

    static let width: CGFloat = 320
    static let height: CGFloat = 84

    private let label = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        layer?.cornerRadius = 10
        isHidden = true

        label.frame = NSRect(x: 20, y: Self.height - 38, width: Self.width - 40, height: 18)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingMiddle
        addSubview(label)

        progress.frame = NSRect(x: 20, y: 20, width: Self.width - 40, height: 20)
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        addSubview(progress)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// `work` calls the progress callback it's given once per file, from any thread.
    func run(
        mode: FileOpMode,
        fileCount: Int,
        destinationName: String,
        work: @escaping (_ reportFileComplete: @escaping () -> Void) -> [URL],
        completion: @escaping ([URL]) -> Void
    ) {
        let verb = mode == .move ? "Moving" : "Copying"
        let noun = fileCount == 1 ? "file" : "files"
        label.stringValue = "\(verb) \(fileCount) \(noun) to \(destinationName)…"
        progress.maxValue = Double(max(fileCount, 1))
        progress.doubleValue = 0
        isHidden = false

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var completedCount = 0
            let result = work {
                completedCount += 1
                let count = completedCount
                DispatchQueue.main.async {
                    self?.progress.doubleValue = Double(count)
                }
            }
            DispatchQueue.main.async {
                self?.isHidden = true
                completion(result)
            }
        }
    }
}
