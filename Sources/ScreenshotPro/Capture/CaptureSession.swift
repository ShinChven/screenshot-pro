import AppKit

final class OverlayWindow: NSWindow {
    init(screenFrame: CGRect) {
        super.init(contentRect: screenFrame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        setFrame(screenFrame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 显示冻结画面的底图（layer-hosting，避免每次重绘整张截图）
final class SnapshotBackgroundView: NSView {
    init(frame: CGRect, image: CGImage, scale: CGFloat) {
        super.init(frame: frame)
        let layer = CALayer()
        layer.contents = image
        layer.contentsGravity = .resize
        layer.contentsScale = scale
        self.layer = layer
        wantsLayer = true
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// 一次截图会话：在每块屏幕上铺一层遮罩，用户选区、标注、输出
final class CaptureSession {
    enum Mode { case normal, ocr, scroll }

    static private(set) var current: CaptureSession?

    let mode: Mode
    private(set) var windows: [OverlayWindow] = []
    private(set) var views: [OverlayView] = []
    private var previousApp: NSRunningApplication?

    private init(mode: Mode) { self.mode = mode }

    /// 仅供自检使用：不截屏、不弹窗口的空会话
    static func makeForTesting() -> CaptureSession { CaptureSession(mode: .normal) }

    static func start(_ mode: Mode) {
        guard current == nil, ScrollCaptureController.current == nil else { return }
        guard Permissions.ensureScreenCapture() else { return }
        let session = CaptureSession(mode: mode)
        current = session
        session.previousApp = NSWorkspace.shared.frontmostApplication
        let windowList = WindowList.onScreen()
        Task { @MainActor in
            do {
                let snaps = try await ScreenCapturer.snapshotAllScreens(showCursor: Settings.shared.showCursor)
                session.present(snaps, windowList)
            } catch {
                current = nil
                Toast.show(L("截图失败：%@", error.localizedDescription))
            }
        }
    }

    private func present(_ snaps: [DisplaySnapshot], _ windowList: [WindowEntry]) {
        let mouse = NSEvent.mouseLocation
        var keyWindow: OverlayWindow?
        for snap in snaps {
            let window = OverlayWindow(screenFrame: snap.frame)
            let bounds = CGRect(origin: .zero, size: snap.frame.size)
            let container = NSView(frame: bounds)
            container.wantsLayer = true
            container.addSubview(SnapshotBackgroundView(frame: bounds, image: snap.image, scale: snap.scale))
            let view = OverlayView(frame: bounds, snapshot: snap, windows: windowList, session: self)
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
            window.contentView = container
            window.orderFrontRegardless()
            window.makeFirstResponder(view)
            windows.append(window)
            views.append(view)
            if snap.frame.contains(mouse) { keyWindow = window }
        }
        NSApp.activate(ignoringOtherApps: true)
        (keyWindow ?? windows.first)?.makeKeyAndOrderFront(nil)
        for v in views { v.refreshMouse() }
    }

    /// 某块屏幕开始选区时，清掉其他屏幕的状态
    func didBeginSelection(in view: OverlayView) {
        for v in views where v !== view { v.resetToChoosing(clearMouse: true) }
    }

    func end(restoreFocus: Bool = true) {
        for w in windows { w.orderOut(nil) }
        // 当前可能还在某个遮罩视图的事件处理中，推迟到下一轮 runloop 再释放
        let retained = (windows, views)
        DispatchQueue.main.async { _ = retained }
        windows.removeAll()
        views.removeAll()
        if Self.current === self { Self.current = nil }
        NSCursor.arrow.set()
        if restoreFocus, let app = previousApp, app != NSRunningApplication.current {
            app.activate(options: [])
        }
    }
}
