import AppKit

/// 截图结果的输出：复制 / 保存 / 记录历史
enum Exporter {
    static func deliver(_ image: CGImage, scale: CGFloat, action: DefaultAction? = nil) {
        var img = image
        var s = scale
        if !Settings.shared.exportRetina, scale > 1, let small = ImageUtil.resize(image, factor: 1 / scale) {
            img = small
            s = 1
        }
        ShutterSound.play()
        History.add(img, scale: s)

        switch action ?? Settings.shared.defaultAction {
        case .copy:
            copy(img, scale: s)
            Toast.show(L("已复制到剪贴板（%ld × %ld）", img.width, img.height))
        case .save:
            if let url = save(img, scale: s) { Toast.show(L("已保存：%@", url.lastPathComponent)) }
        case .copyAndSave:
            copy(img, scale: s)
            if let url = save(img, scale: s) { Toast.show(L("已复制并保存：%@", url.lastPathComponent)) }
        }
    }

    static func copy(_ image: CGImage, scale: CGFloat) {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let pb = NSPasteboard.general
        pb.clearContents()
        if let png = rep.representation(using: .png, properties: [:]) { pb.setData(png, forType: .png) }
        if let tiff = rep.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
    }

    @discardableResult
    static func save(_ image: CGImage, scale: CGFloat, directory: URL? = nil) -> URL? {
        let settings = Settings.shared
        let dir = directory ?? settings.saveDirectoryURL
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
            let base = L("截图 %@", formatter.string(from: Date()))
            let ext = settings.format.rawValue
            var url = dir.appendingPathComponent("\(base).\(ext)")
            var n = 2
            while FileManager.default.fileExists(atPath: url.path) {
                url = dir.appendingPathComponent("\(base) (\(n)).\(ext)")
                n += 1
            }
            guard let data = ImageUtil.encode(image, scale: scale, format: settings.format) else {
                throw NSError(domain: "ScreenshotPro", code: 1, userInfo: [NSLocalizedDescriptionKey: L("编码失败")])
            }
            try data.write(to: url)
            return url
        } catch {
            Toast.show(L("保存失败：%@", error.localizedDescription))
            return nil
        }
    }

    /// 弹出保存面板（钉图里使用）
    static func saveAs(_ image: CGImage, scale: CGFloat) {
        let panel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        panel.nameFieldStringValue = L("截图 %@", formatter.string(from: Date())) + "." + Settings.shared.format.rawValue
        panel.directoryURL = Settings.shared.saveDirectoryURL
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            let format: ImageFormat = url.pathExtension.lowercased().hasPrefix("jp") ? .jpg : .png
            if let data = ImageUtil.encode(image, scale: scale, format: format) {
                do { try data.write(to: url); Toast.show(L("已保存：%@", url.lastPathComponent)) } catch {
                    Toast.show(L("保存失败：%@", error.localizedDescription))
                }
            }
        }
    }
}
