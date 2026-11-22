import AppKit
import ScreenCaptureKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

/// 某块屏幕在截图那一刻的画面
struct DisplaySnapshot {
    let screen: NSScreen
    let frame: CGRect      // Cocoa 全局坐标（左下原点）
    let scale: CGFloat
    let image: CGImage
}

/// 屏幕上的一个窗口（Cocoa 全局坐标）
struct WindowEntry {
    let id: CGWindowID
    let frame: CGRect
}

enum CaptureError: LocalizedError {
    case displayNotFound, windowNotFound
    var errorDescription: String? {
        switch self {
        case .displayNotFound: return L("找不到显示器")
        case .windowNotFound: return L("找不到该窗口")
        }
    }
}

enum ScreenCapturer {
    /// 冻结所有屏幕的当前画面
    static func snapshotAllScreens(showCursor: Bool) async throws -> [DisplaySnapshot] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var result: [DisplaySnapshot] = []
        for screen in NSScreen.screens {
            guard let id = screen.displayID,
                  let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            let scale = screen.backingScaleFactor
            config.width = Int(screen.frame.width * scale)
            config.height = Int(screen.frame.height * scale)
            config.showsCursor = showCursor
            config.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            result.append(DisplaySnapshot(screen: screen, frame: screen.frame, scale: scale, image: image))
        }
        if result.isEmpty { throw CaptureError.displayNotFound }
        return result
    }

    /// 截取单个窗口（不受遮挡影响，可包含阴影、透明背景）
    static func captureWindow(_ windowID: CGWindowID, shadow: Bool) async throws -> (CGImage, CGFloat) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let rect = filter.contentRect
        let config = SCStreamConfiguration()
        config.width = max(1, Int(rect.width * scale))
        config.height = max(1, Int(rect.height * scale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = !shadow
        config.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return (image, scale)
    }
}

enum WindowList {
    /// 屏幕上的普通窗口，按从前到后的顺序
    static func onScreen() -> [WindowEntry] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first else { return [] }
        let primaryHeight = primary.frame.height
        let myPID = ProcessInfo.processInfo.processIdentifier
        var result: [WindowEntry] = []
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer >= 0, layer < 20,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != myPID,
                  let number = info[kCGWindowNumber as String] as? UInt32,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.05 { continue }
            if b.width < 40 || b.height < 30 { continue }
            let frame = CGRect(x: b.minX, y: primaryHeight - b.maxY, width: b.width, height: b.height)
            result.append(WindowEntry(id: number, frame: frame))
        }
        return result
    }
}
