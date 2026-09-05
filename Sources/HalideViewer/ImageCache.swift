import Foundation
import CoreGraphics

/// Boxes a CGImage so it can live in an NSCache (which requires class values).
final class CGImageBox {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

/// Preview-quality cache with background prefetch of neighboring images so
/// arrow-key navigation never blocks on decode.
final class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSURL, CGImageBox>()
    private var inFlight = Set<URL>()
    private let inFlightQueue = DispatchQueue(label: "HalideViewer.ImageCache.inFlight")

    private init() {
        cache.countLimit = 30
    }

    func preview(for url: URL) -> CGImage? {
        cache.object(forKey: url as NSURL)?.image
    }

    func store(_ image: CGImage, for url: URL) {
        cache.setObject(CGImageBox(image), forKey: url as NSURL)
    }

    func prefetch(urls: [URL], maxPixelSize: Int) {
        for url in urls {
            if cache.object(forKey: url as NSURL) != nil { continue }
            let alreadyLoading: Bool = inFlightQueue.sync {
                let loading = inFlight.contains(url)
                if !loading { inFlight.insert(url) }
                return loading
            }
            guard !alreadyLoading else { continue }

            Task.detached(priority: .utility) { [weak self] in
                guard let self else { return }
                defer {
                    self.inFlightQueue.sync { _ = self.inFlight.remove(url) }
                }
                if let image = ImageLoader.loadPreview(url: url, maxPixelSize: maxPixelSize) {
                    self.store(image, for: url)
                }
            }
        }
    }
}
