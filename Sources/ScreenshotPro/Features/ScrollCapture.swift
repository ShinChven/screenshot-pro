import AppKit
import ScreenCaptureKit

/// 长截图：用户自行滚动选区内的内容，程序持续截取并拼接
final class ScrollCaptureController {
    static private(set) var current: ScrollCaptureController?

    private let screen: NSScreen
    private let rect: CGRect          // 屏幕内坐标，左上原点，pt
    private let scale: CGFloat
    private let stitcher = ScrollStitcher()
    private let queue = DispatchQueue(label: "screenshotpro.stitch", qos: .userInitiated)

    private var borderWindow: NSWindow?
    private var panel: NSPanel?
    private var label: NSTextField?
    private var running = true
    private var finishing = false

    private init(screen: NSScreen, rect: CGRect, scale: CGFloat) {
        self.screen = screen
        self.rect = rect
        self.scale = scale
    }

    static func start(screen: NSScreen, rectInScreen: CGRect, scale: CGFloat) {
        guard current == nil else { return }
        let c = ScrollCaptureController(screen: screen, rect: rectInScreen.integral, scale: scale)
        current = c
        c.showChrome()
        Task { @MainActor in await c.run() }
    }

    private var globalRect: CGRect {
        CGRect(x: screen.frame.minX + rect.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: - 界面

    private func showChrome() {
        let border = NSWindow(contentRect: globalRect.insetBy(dx: -4, dy: -4), styleMask: .borderless,
                              backing: .buffered, defer: false)
        border.isOpaque = false
        border.backgroundColor = .clear
        border.ignoresMouseEvents = true
        border.level = .floating
        border.hasShadow = false
        border.isReleasedWhenClosed = false
        border.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        border.contentView = DashedBorderView(frame: CGRect(origin: .zero, size: border.frame.size))
        border.orderFrontRegardless()
        borderWindow = border

        let width: CGFloat = 340, height: CGFloat = 46
        var origin = CGPoint(x: globalRect.maxX - width, y: globalRect.minY - height - 12)
        if origin.y < screen.visibleFrame.minY + 4 { origin.y = globalRect.minY + 12 }
        origin.x = min(max(screen.frame.minX + 4, origin.x), screen.frame.maxX - width - 4)

        let p = NSPanel(contentRect: CGRect(origin: origin, size: CGSize(width: width, height: height)),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let bg = NSView(frame: CGRect(origin: .zero, size: p.frame.size))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.94).cgColor
        bg.layer?.cornerRadius = 10

        let text = NSTextField(labelWithString: L("请滚动选区内的内容（向下）…"))
        text.font = .systemFont(ofSize: 12, weight: .medium)
        text.textColor = .white
        text.frame = CGRect(x: 14, y: 14, width: 200, height: 18)
        text.lineBreakMode = .byTruncatingTail
        bg.addSubview(text)
        label = text

        let cancel = NSButton(title: L("取消"), target: self, action: #selector(cancelTapped))
        cancel.bezelStyle = .rounded
        cancel.frame = CGRect(x: width - 146, y: 8, width: 64, height: 30)
        bg.addSubview(cancel)
        let done = NSButton(title: L("完成"), target: self, action: #selector(doneTapped))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.frame = CGRect(x: width - 78, y: 8, width: 68, height: 30)
        bg.addSubview(done)

        p.contentView = bg
        p.orderFrontRegardless()
        panel = p
    }

    private func update(_ status: ScrollStitcher.Status) {
        let px = stitcher.totalHeight
        switch status {
        case .rejected:
            label?.stringValue = L("⚠️ 滚动太快，请慢一点 · 已拼接 %ld px", px)
            label?.textColor = NSColor(srgbRed: 1, green: 0.8, blue: 0.3, alpha: 1)
        default:
            label?.stringValue = stitcher.frameCount <= 1 ? L("请滚动选区内的内容（向下）…") : L("已拼接 %ld px · %ld 帧", px, stitcher.frameCount)
            label?.textColor = .white
        }
    }

    // MARK: - 截取循环

    @MainActor
    private func run() async {
        try? await Task.sleep(nanoseconds: 200_000_000)  // 等边框窗口出现，便于排除
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let id = screen.displayID, let display = content.displays.first(where: { $0.displayID == id }) else {
                throw CaptureError.displayNotFound
            }
            let pid = ProcessInfo.processInfo.processIdentifier
            let mine = content.windows.filter { $0.owningApplication?.processID == pid }
            let filter = SCContentFilter(display: display, excludingWindows: mine)
            let config = SCStreamConfiguration()
            config.sourceRect = rect
            config.width = Int(rect.width * scale)
            config.height = Int(rect.height * scale)
            config.showsCursor = false
            config.captureResolution = .best

            while running {
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                guard running else { break }
                let status: ScrollStitcher.Status = await withCheckedContinuation { cont in
                    queue.async { cont.resume(returning: self.stitcher.add(image)) }
                }
                update(status)
                if stitcher.totalHeight >= ScrollStitcher.maxHeight {
                    Toast.show(L("已达到最大长度"))
                    finish()
                    break
                }
                try await Task.sleep(nanoseconds: 90_000_000)
            }
        } catch {
            Toast.show(L("长截图失败：%@", error.localizedDescription))
            cancel()
        }
    }

    @objc private func doneTapped() { finish() }
    @objc private func cancelTapped() { cancel() }

    private func finish() {
        guard !finishing else { return }
        finishing = true
        running = false
        label?.stringValue = L("正在拼接…")
        queue.async {
            let result = self.stitcher.result()
            DispatchQueue.main.async {
                self.teardown()
                if let result {
                    Exporter.deliver(result, scale: self.scale)
                } else {
                    Toast.show(L("没有截取到内容"))
                }
            }
        }
    }

    private func cancel() {
        running = false
        teardown()
    }

    private func teardown() {
        borderWindow?.orderOut(nil)
        panel?.orderOut(nil)
        borderWindow = nil
        panel = nil
        if Self.current === self { Self.current = nil }
    }
}

final class DashedBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
        path.lineWidth = 2
        path.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }
}
