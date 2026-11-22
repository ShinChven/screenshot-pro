import AppKit

/// 钉在屏幕上的截图（始终置顶，可拖动、缩放、调透明度）
final class PinWindow: NSPanel {
    static private(set) var all: [PinWindow] = []

    let image: CGImage
    let scale: CGFloat
    let baseSize: CGSize

    private init(image: CGImage, scale: CGFloat, frame: CGRect) {
        self.image = image
        self.scale = scale
        baseSize = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isFloatingPanel = true
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = PinView(frame: CGRect(origin: .zero, size: frame.size), pin: self)
    }

    override var canBecomeKey: Bool { true }

    static func pin(_ image: CGImage, scale: CGFloat, frame: CGRect) {
        let w = PinWindow(image: image, scale: scale, frame: frame)
        all.append(w)
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
        w.makeFirstResponder(w.contentView)
        Toast.show(L("已钉在屏幕上：滚轮缩放 · 1–9/0 透明度 · 双击或 Esc 关闭"), duration: 2.2)
    }

    /// 在鼠标所在屏幕中央钉图
    static func pinCentered(_ image: CGImage, scale: CGFloat) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        var size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let maxSize = CGSize(width: screen.visibleFrame.width * 0.8, height: screen.visibleFrame.height * 0.8)
        let k = min(1, maxSize.width / size.width, maxSize.height / size.height)
        size = CGSize(width: size.width * k, height: size.height * k)
        let frame = CGRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2,
                           width: size.width, height: size.height)
        pin(image, scale: scale, frame: frame)
    }

    static func pinClipboard() {
        let pb = NSPasteboard.general
        guard let img = NSImage(pasteboard: pb),
              let rep = img.representations.first,
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Toast.show(L("剪贴板里没有图片"))
            return
        }
        let scale = rep.size.width > 0 ? max(1, CGFloat(cg.width) / rep.size.width) : 1
        pinCentered(cg, scale: scale)
    }

    static func closeAll() {
        for w in all { w.orderOut(nil) }
        all.removeAll()
    }

    func closePin() {
        orderOut(nil)
        PinWindow.all.removeAll { $0 === self }
    }

    func zoom(by factor: CGFloat, anchor: CGPoint) {
        let current = frame
        let minW = max(40, baseSize.width * 0.1), maxW = baseSize.width * 6
        let newW = min(max(current.width * factor, minW), maxW)
        let k = newW / current.width
        guard abs(k - 1) > 0.0001 else { return }
        let newH = current.height * k
        // 以鼠标位置为锚点缩放
        let ax = anchor.x / current.width, ay = anchor.y / current.height
        let origin = CGPoint(x: current.minX + anchor.x - newW * ax, y: current.minY + anchor.y - newH * ay)
        setFrame(CGRect(origin: origin, size: CGSize(width: newW, height: newH)), display: true)
    }

    func resetSize() {
        setFrame(CGRect(x: frame.minX, y: frame.maxY - baseSize.height, width: baseSize.width, height: baseSize.height),
                 display: true)
    }
}

final class PinView: NSView {
    private unowned let pin: PinWindow
    private let nsImage: NSImage

    init(frame: CGRect, pin: PinWindow) {
        self.pin = pin
        nsImage = ImageUtil.nsImage(pin.image, scale: pin.scale)
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .high
        nsImage.draw(in: bounds)
        NSColor.controlAccentColor.withAlphaComponent(window?.isKeyWindow == true ? 0.9 : 0.35).setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        needsDisplay = true
        if event.clickCount == 2 {
            pin.closePin()
            return
        }
        window?.performDrag(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
        let factor = pow(1.005, delta)
        pin.zoom(by: factor, anchor: convert(event.locationInWindow, from: nil))
    }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.keyCode == 53 { pin.closePin(); return }
        if mods.contains(.command) {
            switch chars {
            case "c": copyImage()
            case "s": saveImage()
            case "w": pin.closePin()
            case "0": pin.resetSize()
            default: super.keyDown(with: event)
            }
            return
        }
        if let n = Int(chars), chars.count == 1 {
            pin.alphaValue = n == 0 ? 1 : CGFloat(n) / 10
            return
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(ActionMenuItem("复制", key: "c", modifiers: .command) { [weak self] in self?.copyImage() })
        menu.addItem(ActionMenuItem("另存为…", key: "s", modifiers: .command) { [weak self] in self?.saveImage() })
        menu.addItem(ActionMenuItem("文字识别") { [weak self] in
            guard let self else { return }
            OCRService.run(on: self.pin.image)
        })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("原始大小", key: "0", modifiers: .command) { [weak self] in self?.pin.resetSize() })
        let opacity = NSMenuItem(title: L("透明度"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for v in [100, 80, 60, 40, 20] {
            let item = ActionMenuItem("\(v)%") { [weak self] in self?.pin.alphaValue = CGFloat(v) / 100 }
            item.state = abs(pin.alphaValue * 100 - CGFloat(v)) < 1 ? .on : .off
            sub.addItem(item)
        }
        opacity.submenu = sub
        menu.addItem(opacity)
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("关闭", key: "w", modifiers: .command) { [weak self] in self?.pin.closePin() })
        menu.addItem(ActionMenuItem("关闭所有钉图") { PinWindow.closeAll() })
        return menu
    }

    private func copyImage() {
        Exporter.copy(pin.image, scale: pin.scale)
        Toast.show(L("已复制到剪贴板"))
    }

    private func saveImage() {
        Exporter.saveAs(pin.image, scale: pin.scale)
    }
}
