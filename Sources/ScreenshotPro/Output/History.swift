import AppKit

/// 最近截图历史，保存在 ~/Library/Application Support/ScreenshotPro/History
enum History {
    static let maxItems = 40

    struct Entry {
        let url: URL
        let date: Date
        let scale: CGFloat
        let pixelSize: String

        func thumbnail() -> NSImage? {
            guard let img = NSImage(contentsOf: url) else { return nil }
            let maxSide: CGFloat = 36
            let s = img.size
            guard s.width > 0, s.height > 0 else { return nil }
            let k = min(maxSide / s.width, maxSide / s.height, 1)
            img.size = NSSize(width: max(1, s.width * k), height: max(1, s.height * k))
            return img
        }
    }

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ScreenshotPro/History", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static let queue = DispatchQueue(label: "screenshotpro.history", qos: .utility)

    static func add(_ image: CGImage, scale: CGFloat) {
        queue.async {
            let ms = Int(Date().timeIntervalSince1970 * 1000)
            let name = "\(ms)_\(image.width)x\(image.height)@\(Int(scale))x.png"
            if let data = ImageUtil.encode(image, scale: scale, format: .png) {
                try? data.write(to: directory.appendingPathComponent(name))
            }
            prune()
        }
    }

    static func items(limit: Int = maxItems) -> [Entry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "png" }
            .compactMap(parse)
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { $0 }
    }

    static func load(_ entry: Entry) -> (CGImage, CGFloat)? {
        guard let src = CGImageSourceCreateWithURL(entry.url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return (img, entry.scale)
    }

    static func clear() {
        queue.async {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for f in files { try? FileManager.default.removeItem(at: f) }
        }
    }

    private static func parse(_ url: URL) -> Entry? {
        // 1732250000000_1280x720@2x.png
        let name = url.deletingPathExtension().lastPathComponent
        let parts = name.split(separator: "_")
        guard parts.count == 2, let ms = Double(parts[0]) else { return nil }
        let rest = parts[1].split(separator: "@")
        let size = rest.first.map(String.init)?.replacingOccurrences(of: "x", with: " × ") ?? ""
        var scale: CGFloat = 1
        if rest.count > 1, let s = Double(rest[1].replacingOccurrences(of: "x", with: "")) { scale = CGFloat(s) }
        return Entry(url: url, date: Date(timeIntervalSince1970: ms / 1000), scale: scale, pixelSize: size)
    }

    private static func prune() {
        let all = items(limit: Int.max)
        for entry in all.dropFirst(maxItems) { try? FileManager.default.removeItem(at: entry.url) }
    }
}
