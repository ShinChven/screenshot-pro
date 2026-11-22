import AppKit

/// 单块屏幕上的截图遮罩：选区、窗口识别、放大镜、标注
final class OverlayView: NSView, NSTextFieldDelegate {
    private unowned let session: CaptureSession
    let snapshot: DisplaySnapshot
    private let baseImage: NSImage
    private lazy var mosaicImage: NSImage? = ImageUtil.pixelated(snapshot.image, pointSize: bounds.size, scale: scale)
    private lazy var pixels: PixelBuffer? = PixelBuffer(image: snapshot.image)
    private let windowRects: [(id: CGWindowID, rect: CGRect)]
    private var scale: CGFloat { snapshot.scale }

    private enum Phase { case choosing, editing }
    private enum Handle: CaseIterable { case tl, t, tr, r, br, b, bl, l }
    private enum DragOp {
        case none
        case pending(CGPoint, NSEvent.ModifierFlags)
        case newSelection(CGPoint)
        case moveSelection(CGPoint, CGRect)
        case resize(Handle, CGRect)
        case drawing
        case moveAnnotation(Int, CGPoint, Annotation)
        case resizeAnnotation(Int, AnnotationHandle, Annotation)
    }

    /// 选中标注上的控制点：矩形类为 8 个边角点，直线 / 箭头为两个端点
    private enum AnnotationHandle {
        case box(Handle)
        case endpoint(first: Bool)
    }

    private var phase: Phase = .choosing
    private var selection: CGRect = .zero
    private var hover: (id: CGWindowID?, rect: CGRect)?
    private var multi: [(id: CGWindowID, rect: CGRect)] = []
    private var mouse: CGPoint?

    private var annotations: [Annotation] = []
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []
    private var tool: Tool?
    private var style = AnnotationStyle.current
    private var selectedIndex: Int?
    private var drag: DragOp = .none
    private var dragUndoSnapshot: [Annotation]?
    private var draft: Annotation?

    private var textField: NSTextField?
    private var textOrigin: CGPoint = .zero
    private var textOriginal: Annotation?

    private let toolbar = Toolbar()

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    init(frame: CGRect, snapshot: DisplaySnapshot, windows: [WindowEntry], session: CaptureSession) {
        self.session = session
        self.snapshot = snapshot
        baseImage = NSImage(cgImage: snapshot.image, size: frame.size)
        let sf = snapshot.frame
        windowRects = windows.compactMap { w in
            let r = w.frame.intersection(sf)
            guard !r.isNull, r.width > 20, r.height > 20 else { return nil }
            return (w.id, CGRect(x: r.minX - sf.minX, y: sf.maxY - r.maxY, width: r.width, height: r.height))
        }
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        setupToolbar()
    }

    required init?(coder: NSCoder) { fatalError() }

    // 自检用
    var testAnnotations: [Annotation] { annotations }
    var testSelectedIndex: Int? { selectedIndex }
    var testSelection: CGRect { selection }
    func testSetMosaicBrush(_ on: Bool) { style.mosaicBrush = on }

    // MARK: - 坐标

    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    func refreshMouse() {
        guard let window else { return }
        let p = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if bounds.contains(p) {
            mouse = p
            updateHover(p)
            NSCursor.crosshair.set()
        } else {
            mouse = nil
        }
        needsDisplay = true
    }

    private func globalRect(_ r: CGRect) -> CGRect {
        CGRect(x: snapshot.frame.minX + r.minX, y: snapshot.frame.maxY - r.maxY, width: r.width, height: r.height)
    }

    private var isSelecting: Bool {
        if case .newSelection = drag { return true }
        return false
    }

    // MARK: - 状态

    func resetToChoosing(clearMouse: Bool = false) {
        commitText()
        phase = .choosing
        selection = .zero
        annotations.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        selectedIndex = nil
        draft = nil
        tool = nil
        multi.removeAll()
        toolbar.isHidden = true
        if clearMouse { mouse = nil; hover = nil }
        needsDisplay = true
    }

    private func updateHover(_ p: CGPoint) {
        if let w = windowRects.first(where: { $0.rect.contains(p) }) {
            hover = (w.id, w.rect)
        } else {
            hover = (nil, bounds)
        }
    }

    private func enterEditing() {
        phase = .editing
        selection = selection.intersection(bounds).integral
        switch session.mode {
        case .ocr: finish(.ocr)
        case .scroll: finish(.scroll)
        case .normal:
            tool = nil
            refreshToolbar()
            toolbar.isHidden = false
            layoutToolbar()
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(self)
        }
        needsDisplay = true
    }

    // MARK: - 工具栏

    private func setupToolbar() {
        toolbar.isHidden = true
        addSubview(toolbar)
        toolbar.onTool = { [weak self] t in self?.setTool(self?.tool == t ? nil : t) }
        toolbar.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .undo: self.undo()
            case .redo: self.redo()
            case .ocr: self.finish(.ocr)
            case .scroll: self.finish(.scroll)
            case .pin: self.finish(.pin)
            case .save: self.finish(.save)
            case .cancel: self.session.end()
            case .done: self.finish(.defaultAction)
            }
            self.window?.makeFirstResponder(self)
        }
        toolbar.onColor = { [weak self] i in self?.applyStyle { $0.colorIndex = i } }
        toolbar.onWidth = { [weak self] i in self?.applyStyle { $0.widthLevel = i } }
        toolbar.onToggleFill = { [weak self] in self?.applyStyle { $0.filled.toggle() } }
        toolbar.onToggleMosaicMode = { [weak self] in self?.applyStyle { $0.mosaicBrush.toggle() } }
    }

    private func setTool(_ t: Tool?) {
        commitText()
        tool = t
        selectedIndex = nil
        refreshToolbar()
        layoutToolbar()
        needsDisplay = true
    }

    private func refreshToolbar() {
        let styleTool = tool ?? selectedIndex.map { annotations[$0].tool }
        toolbar.update(tool: tool, styleTool: styleTool, style: style)
    }

    private func applyStyle(_ change: (inout AnnotationStyle) -> Void) {
        change(&style)
        style.save()
        if let i = selectedIndex, i < annotations.count {
            pushUndo()
            var a = annotations[i]
            a.color = style.color
            a.filled = style.filled
            if a.tool == .text { a.fontSize = style.fontSize } else if a.tool != .mosaic || a.mosaicBrush {
                a.lineWidth = style.lineWidth(for: a.tool)
            }
            annotations[i] = a
        }
        if let f = textField {
            f.textColor = style.color
            f.font = Annotation.font(style.fontSize)
            resizeTextField()
        }
        refreshToolbar()
        layoutToolbar()
        needsDisplay = true
        window?.makeFirstResponder(textField ?? self)
    }

    private func layoutToolbar() {
        guard phase == .editing, session.mode == .normal else { toolbar.isHidden = true; return }
        let size = toolbar.preferredSize
        var x = selection.maxX - size.width
        var y = selection.maxY + 8
        if y + size.height > bounds.height - 4 { y = selection.minY - 8 - size.height }
        if y < 4 { y = max(4, selection.maxY - size.height - 8) }
        x = min(max(4, x), bounds.width - size.width - 4)
        toolbar.frame.origin = CGPoint(x: x, y: y)
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let editingLike = phase == .editing || isSelecting
        let focus: CGRect? = editingLike ? selection : (multi.isEmpty ? hover?.rect : nil)

        // 暗色遮罩（选区 / 悬停窗口保持原样）
        ctx.saveGState()
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.42).cgColor)
        ctx.addRect(bounds)
        if let focus, !focus.isEmpty { ctx.addRect(focus) }
        for m in multi { ctx.addRect(m.rect) }
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()

        let accent = NSColor.controlAccentColor.cgColor

        // 多窗口选择
        for (i, m) in multi.enumerated() {
            ctx.setStrokeColor(accent)
            ctx.setLineWidth(3)
            ctx.stroke(m.rect.insetBy(dx: 1.5, dy: 1.5))
            drawBadge("\(i + 1)", at: CGPoint(x: m.rect.minX + 18, y: m.rect.minY + 18), in: ctx)
        }

        if phase == .choosing, !isSelecting, multi.isEmpty, let h = hover {
            ctx.setStrokeColor(accent)
            ctx.setLineWidth(h.id == nil ? 4 : 3)
            ctx.stroke(h.rect.insetBy(dx: 1.5, dy: 1.5))
        }

        if editingLike, !selection.isEmpty {
            ctx.saveGState()
            ctx.clip(to: selection)
            drawAnnotations(in: ctx)
            ctx.restoreGState()

            if let i = selectedIndex, i < annotations.count {
                let handles = annotationHandles(annotations[i])
                ctx.saveGState()
                if handles.isEmpty {
                    ctx.setStrokeColor(NSColor.white.cgColor)
                    ctx.setLineWidth(1)
                    ctx.setLineDash(phase: 0, lengths: [4, 3])
                    ctx.stroke(annotations[i].bounds.insetBy(dx: -4, dy: -4))
                } else {
                    if case .box = handles[0].0 {
                        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
                        ctx.setLineWidth(1)
                        ctx.setLineDash(phase: 0, lengths: [4, 3])
                        ctx.stroke(annotations[i].rect)
                        ctx.setLineDash(phase: 0, lengths: [])
                    }
                    for (_, r) in handles {
                        ctx.setFillColor(NSColor.white.cgColor)
                        ctx.fill(r)
                        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
                        ctx.setLineWidth(1.5)
                        ctx.stroke(r)
                    }
                }
                ctx.restoreGState()
            }

            ctx.setStrokeColor(accent)
            ctx.setLineWidth(1.5)
            ctx.stroke(selection.insetBy(dx: -0.75, dy: -0.75))
            if phase == .editing { drawHandles(in: ctx) }
            drawSizeLabel(in: ctx)
        }

        if (phase == .choosing || isSelecting), Settings.shared.showMagnifier, let m = mouse {
            drawMagnifier(at: m, in: ctx)
        }

        if phase == .choosing, !isSelecting, mouse != nil {
            let hint = multi.isEmpty
                ? L("拖拽框选 · 单击选择窗口 · ⌥单击截取独立窗口 · ⌘单击多选窗口 · Esc 退出")
                : L("已选 %ld 个窗口 · 继续 ⌘单击添加 · ↩ 合成截图 · Esc 取消", multi.count)
            drawHint(hint, in: ctx)
        }
    }

    private func drawAnnotations(in ctx: CGContext) {
        // 只有用到马赛克时才生成整屏马赛克图
        let needsMosaic = draft?.tool == .mosaic || annotations.contains { $0.tool == .mosaic }
        let mosaic = needsMosaic ? mosaicImage : nil
        var step = 0
        for a in annotations {
            if a.tool == .step { step += 1 }
            AnnotationRenderer.draw(a, number: step, mosaic: mosaic, imageRect: bounds, in: ctx)
        }
        if let d = draft {
            AnnotationRenderer.draw(d, number: step + 1, mosaic: mosaic, imageRect: bounds, in: ctx)
        }
    }

    private func handleRects() -> [(Handle, CGRect)] {
        let r = selection, s: CGFloat = 8
        func box(_ x: CGFloat, _ y: CGFloat) -> CGRect { CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s) }
        return [
            (.tl, box(r.minX, r.minY)), (.t, box(r.midX, r.minY)), (.tr, box(r.maxX, r.minY)),
            (.r, box(r.maxX, r.midY)), (.br, box(r.maxX, r.maxY)), (.b, box(r.midX, r.maxY)),
            (.bl, box(r.minX, r.maxY)), (.l, box(r.minX, r.midY)),
        ]
    }

    private func drawHandles(in ctx: CGContext) {
        for (_, r) in handleRects() {
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: r)
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: r)
        }
    }

    private var exportScale: CGFloat { Settings.shared.exportRetina ? scale : 1 }

    private func drawSizeLabel(in ctx: CGContext) {
        let w = Int((selection.width * exportScale).rounded()), h = Int((selection.height * exportScale).rounded())
        let text = "\(w) × \(h)"
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                                                    .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        var origin = CGPoint(x: selection.minX, y: selection.minY - size.height - 10)
        if origin.y < 2 { origin.y = selection.minY + 4; origin.x += 4 }
        let box = CGRect(x: origin.x, y: origin.y, width: size.width + 12, height: size.height + 6)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        ctx.addPath(CGPath(roundedRect: box, cornerWidth: 4, cornerHeight: 4, transform: nil))
        ctx.fillPath()
        (text as NSString).draw(at: CGPoint(x: box.minX + 6, y: box.minY + 3), withAttributes: attrs)
    }

    private func drawBadge(_ text: String, at c: CGPoint, in ctx: CGContext) {
        let r: CGFloat = 12
        ctx.setFillColor(NSColor.controlAccentColor.cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .bold),
                                                    .foregroundColor: NSColor.white]
        let s = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: CGPoint(x: c.x - s.width / 2, y: c.y - s.height / 2), withAttributes: attrs)
    }

    private func drawHint(_ text: String, in ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium),
                                                    .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        let box = CGRect(x: bounds.midX - size.width / 2 - 14, y: 36, width: size.width + 28, height: size.height + 12)
        if let m = mouse, box.insetBy(dx: -20, dy: -20).contains(m) { return }
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.7).cgColor)
        ctx.addPath(CGPath(roundedRect: box, cornerWidth: box.height / 2, cornerHeight: box.height / 2, transform: nil))
        ctx.fillPath()
        (text as NSString).draw(at: CGPoint(x: box.minX + 14, y: box.minY + 6), withAttributes: attrs)
    }

    private func drawMagnifier(at p: CGPoint, in ctx: CGContext) {
        let cells = 15, cell: CGFloat = 8
        let size = CGFloat(cells) * cell
        let infoH: CGFloat = 50
        var origin = CGPoint(x: p.x + 22, y: p.y + 26)
        if origin.x + size > bounds.width - 4 { origin.x = p.x - 22 - size }
        if origin.y + size + infoH > bounds.height - 4 { origin.y = p.y - 26 - size - infoH }
        let box = CGRect(origin: origin, size: CGSize(width: size, height: size))

        let px = Int(p.x * scale), py = Int(p.y * scale)
        let half = cells / 2
        let src = CGRect(x: px - half, y: py - half, width: cells, height: cells)
        let imgBounds = CGRect(x: 0, y: 0, width: snapshot.image.width, height: snapshot.image.height)

        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: box, cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.clip()
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(box)
        let clipped = src.intersection(imgBounds)
        if !clipped.isNull, let crop = snapshot.image.cropping(to: clipped) {
            let dest = CGRect(x: box.minX + (clipped.minX - src.minX) * cell, y: box.minY + (clipped.minY - src.minY) * cell,
                              width: clipped.width * cell, height: clipped.height * cell)
            ctx.interpolationQuality = .none
            ctx.saveGState()
            ctx.translateBy(x: dest.minX, y: dest.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(crop, in: CGRect(origin: .zero, size: dest.size))
            ctx.restoreGState()
        }
        // 十字线
        ctx.setFillColor(NSColor.systemBlue.withAlphaComponent(0.25).cgColor)
        ctx.fill(CGRect(x: box.minX, y: box.minY + CGFloat(half) * cell, width: size, height: cell))
        ctx.fill(CGRect(x: box.minX + CGFloat(half) * cell, y: box.minY, width: cell, height: size))
        let center = CGRect(x: box.minX + CGFloat(half) * cell, y: box.minY + CGFloat(half) * cell, width: cell, height: cell)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(center)
        ctx.restoreGState()

        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
        ctx.setLineWidth(1.5)
        ctx.addPath(CGPath(roundedRect: box, cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.strokePath()

        let info = CGRect(x: box.minX, y: box.maxY + 4, width: size, height: infoH)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.8).cgColor)
        ctx.addPath(CGPath(roundedRect: info, cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.fillPath()
        let hex = pixels?.hex(x: px, y: py) ?? "--"
        if let c = pixels?.rgb(x: px, y: py) {
            ctx.setFillColor(NSColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1).cgColor)
            ctx.fill(CGRect(x: info.minX + 8, y: info.minY + 22, width: 12, height: 12))
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.6).cgColor)
            ctx.stroke(CGRect(x: info.minX + 8, y: info.minY + 22, width: 12, height: 12))
        }
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                                                    .foregroundColor: NSColor.white.withAlphaComponent(0.85)]
        let big: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
                                                  .foregroundColor: NSColor.white]
        ("\(Int(p.x)), \(Int(p.y)) pt" as NSString).draw(at: CGPoint(x: info.minX + 8, y: info.minY + 5), withAttributes: small)
        (hex as NSString).draw(at: CGPoint(x: info.minX + 26, y: info.minY + 20), withAttributes: big)
        (L("C 复制 · ⇧C RGB") as NSString).draw(at: CGPoint(x: info.minX + 8, y: info.minY + 35), withAttributes: small)
    }

    // MARK: - 鼠标

    override func mouseMoved(with event: NSEvent) {
        let p = point(event)
        mouse = p
        if phase == .choosing {
            updateHover(p)
            NSCursor.crosshair.set()
            if window?.isKeyWindow == false { window?.makeKeyAndOrderFront(nil) }
        } else {
            updateCursor(at: p)
        }
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }

    override func mouseExited(with event: NSEvent) {
        mouse = nil
        if phase == .choosing { hover = nil }
        needsDisplay = true
    }

    private func updateCursor(at p: CGPoint) {
        if toolbar.frame.contains(p) { NSCursor.arrow.set(); return }
        if let h = annotationHandle(at: p) {
            switch h {
            case .box(.l), .box(.r): NSCursor.resizeLeftRight.set()
            case .box(.t), .box(.b): NSCursor.resizeUpDown.set()
            default: NSCursor.crosshair.set()
            }
            return
        }
        if selection.contains(p), hitAnnotation(p) != nil { NSCursor.openHand.set(); return }
        if tool != nil, selection.contains(p) {
            (tool == .text ? NSCursor.iBeam : NSCursor.crosshair).set()
            return
        }
        if let h = handle(at: p) {
            switch h {
            case .l, .r: NSCursor.resizeLeftRight.set()
            case .t, .b: NSCursor.resizeUpDown.set()
            default: NSCursor.crosshair.set()
            }
            return
        }
        if selection.contains(p) { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
    }

    private func handle(at p: CGPoint) -> Handle? {
        handleRects().first { $0.1.insetBy(dx: -5, dy: -5).contains(p) }?.0
    }

    private func annotationHandles(_ a: Annotation) -> [(AnnotationHandle, CGRect)] {
        let s: CGFloat = 8
        func box(_ p: CGPoint) -> CGRect { CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s) }
        switch a.tool {
        case .rect, .ellipse:
            break
        case .mosaic where !a.mosaicBrush:
            break
        case .line, .arrow:
            guard let first = a.points.first, let last = a.points.last else { return [] }
            return [(.endpoint(first: true), box(first)), (.endpoint(first: false), box(last))]
        default:
            return []
        }
        let r = a.rect
        return [
            (.box(.tl), box(CGPoint(x: r.minX, y: r.minY))), (.box(.t), box(CGPoint(x: r.midX, y: r.minY))),
            (.box(.tr), box(CGPoint(x: r.maxX, y: r.minY))), (.box(.r), box(CGPoint(x: r.maxX, y: r.midY))),
            (.box(.br), box(CGPoint(x: r.maxX, y: r.maxY))), (.box(.b), box(CGPoint(x: r.midX, y: r.maxY))),
            (.box(.bl), box(CGPoint(x: r.minX, y: r.maxY))), (.box(.l), box(CGPoint(x: r.minX, y: r.midY))),
        ]
    }

    private func annotationHandle(at p: CGPoint) -> AnnotationHandle? {
        guard let i = selectedIndex, i < annotations.count else { return nil }
        return annotationHandles(annotations[i]).first { $0.1.insetBy(dx: -5, dy: -5).contains(p) }?.0
    }

    private func selectAnnotation(_ i: Int?) {
        selectedIndex = i
        refreshToolbar()
        layoutToolbar()
        needsDisplay = true
    }

    private func hitAnnotation(_ p: CGPoint) -> Int? {
        annotations.indices.reversed().first { annotations[$0].hitTest(p) }
    }

    override func mouseDown(with event: NSEvent) {
        let p = point(event)
        if textField != nil {
            commitText()
            if tool == .text { return }
        }
        window?.makeFirstResponder(self)

        switch phase {
        case .choosing:
            drag = .pending(p, event.modifierFlags.intersection(.deviceIndependentFlagsMask))

        case .editing:
            if event.clickCount == 2, tool == nil {
                if let i = hitAnnotation(p), annotations[i].tool == .text { editText(at: i); return }
                if selection.contains(p) { finish(.defaultAction); return }
            }
            // 1. 选中标注的控制点：调整大小 / 端点
            if let i = selectedIndex, let h = annotationHandle(at: p) {
                dragUndoSnapshot = annotations
                drag = .resizeAnnotation(i, h, annotations[i])
                return
            }
            // 2. 点中已有标注：选中并拖动（无论当前是否选了工具）
            if selection.contains(p), let i = hitAnnotation(p) {
                selectAnnotation(i)
                dragUndoSnapshot = annotations
                drag = .moveAnnotation(i, p, annotations[i])
                NSCursor.closedHand.set()
                return
            }
            // 3. 选了工具：画新标注
            if let t = tool, selection.contains(p), handle(at: p) == nil {
                beginDrawing(t, at: p)
                return
            }
            // 4. 选区边角：调整选区
            if let h = handle(at: p) {
                drag = .resize(h, selection)
                return
            }
            if selectedIndex != nil {
                selectedIndex = nil
                refreshToolbar()
                layoutToolbar()
            }
            if selection.contains(p) {
                drag = .moveSelection(p, selection)
                NSCursor.closedHand.set()
            } else if annotations.isEmpty {
                resetToChoosing()
                updateHover(p)
                drag = .pending(p, [])
            }
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        var p = point(event)
        p.x = min(max(0, p.x), bounds.width)
        p.y = min(max(0, p.y), bounds.height)
        mouse = p

        switch drag {
        case .pending(let s, _):
            if hypot(p.x - s.x, p.y - s.y) > 3 {
                session.didBeginSelection(in: self)
                multi.removeAll()
                drag = .newSelection(s)
                selection = Self.rect(s, p)
            }
        case .newSelection(let s):
            selection = Self.rect(s, p)
        case .moveSelection(let s, let orig):
            var r = orig.offsetBy(dx: p.x - s.x, dy: p.y - s.y)
            r.origin.x = min(max(0, r.origin.x), bounds.width - r.width)
            r.origin.y = min(max(0, r.origin.y), bounds.height - r.height)
            selection = r
            layoutToolbar()
        case .resize(let h, let orig):
            selection = Self.resized(orig, handle: h, to: p)
            layoutToolbar()
        case .drawing:
            guard var d = draft else { break }
            if d.isFreehand {
                if let last = d.points.last, hypot(last.x - p.x, last.y - p.y) >= 1 { d.points.append(p) }
            } else {
                var e = p
                if event.modifierFlags.contains(.shift), let s = d.points.first {
                    e = Self.constrain(from: s, to: p, tool: d.tool)
                }
                d.points[d.points.count - 1] = e
            }
            draft = d
        case .moveAnnotation(let i, let s, let orig):
            var a = orig
            a.move(dx: p.x - s.x, dy: p.y - s.y)
            annotations[i] = a
        case .resizeAnnotation(let i, let h, let orig):
            var a = orig
            switch h {
            case .box(let bh):
                let r = Self.resized(orig.rect, handle: bh, to: p)
                a.points = [r.origin, CGPoint(x: r.maxX, y: r.maxY)]
            case .endpoint(let first):
                let anchor = first ? orig.points.last! : orig.points.first!
                let e = event.modifierFlags.contains(.shift) ? Self.constrain(from: anchor, to: p, tool: orig.tool) : p
                if first { a.points[0] = e } else { a.points[a.points.count - 1] = e }
            }
            annotations[i] = a
        case .none:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let p = point(event)
        switch drag {
        case .pending(_, let mods):
            if mods.contains(.command) {
                toggleMulti(at: p)
            } else if mods.contains(.option) {
                captureIndependentWindow(at: p)
            } else if let h = hover {
                session.didBeginSelection(in: self)
                multi.removeAll()
                selection = h.rect
                enterEditing()
            }
        case .newSelection:
            if selection.width < 4 || selection.height < 4 {
                resetToChoosing()
                updateHover(p)
            } else {
                enterEditing()
            }
        case .drawing:
            if let d = draft, d.isValid {
                pushUndo()
                annotations.append(d)
                // 刚画完的标注自动选中，马上可以拖动 / 调整大小
                selectAnnotation(annotations.count - 1)
            }
            draft = nil
        case .moveAnnotation(let i, _, let orig), .resizeAnnotation(let i, _, let orig):
            if let snap = dragUndoSnapshot, annotations[i].points != orig.points {
                undoStack.append(snap)
                redoStack.removeAll()
            }
            dragUndoSnapshot = nil
            updateCursor(at: p)
        case .moveSelection, .resize:
            selection = selection.integral
            layoutToolbar()
            updateCursor(at: p)
        case .none:
            break
        }
        drag = .none
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        if phase == .editing || !multi.isEmpty {
            resetToChoosing()
            updateHover(point(event))
        } else {
            session.end()
        }
    }

    private func beginDrawing(_ t: Tool, at p: CGPoint) {
        selectedIndex = nil
        switch t {
        case .text:
            startText(at: p, initial: "", original: nil)
        case .step:
            pushUndo()
            annotations.append(Annotation(tool: .step, color: style.color, lineWidth: style.lineWidth(for: .step), points: [p]))
            needsDisplay = true
        default:
            var a = Annotation(tool: t, color: style.color, lineWidth: style.lineWidth(for: t), filled: style.filled,
                               mosaicBrush: style.mosaicBrush, points: [p])
            if !a.isFreehand { a.points.append(p) }
            draft = a
            drag = .drawing
        }
    }

    private static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private static func resized(_ r: CGRect, handle: Handle, to p: CGPoint) -> CGRect {
        var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
        switch handle {
        case .tl: minX = p.x; minY = p.y
        case .t: minY = p.y
        case .tr: maxX = p.x; minY = p.y
        case .r: maxX = p.x
        case .br: maxX = p.x; maxY = p.y
        case .b: maxY = p.y
        case .bl: minX = p.x; maxY = p.y
        case .l: minX = p.x
        }
        return rect(CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: maxY))
    }

    private static func constrain(from s: CGPoint, to p: CGPoint, tool: Tool) -> CGPoint {
        let dx = p.x - s.x, dy = p.y - s.y
        switch tool {
        case .rect, .ellipse, .mosaic:
            let d = max(abs(dx), abs(dy))
            return CGPoint(x: s.x + (dx < 0 ? -d : d), y: s.y + (dy < 0 ? -d : d))
        default:
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let len = hypot(dx, dy)
            return CGPoint(x: s.x + cos(angle) * len, y: s.y + sin(angle) * len)
        }
    }

    // MARK: - 窗口截图

    private func toggleMulti(at p: CGPoint) {
        guard let w = windowRects.first(where: { $0.rect.contains(p) }) else { NSSound.beep(); return }
        session.didBeginSelection(in: self)
        if let i = multi.firstIndex(where: { $0.id == w.id }) { multi.remove(at: i) } else { multi.append(w) }
        needsDisplay = true
    }

    private func captureIndependentWindow(at p: CGPoint) {
        guard let w = windowRects.first(where: { $0.rect.contains(p) }) else { NSSound.beep(); return }
        let shadow = Settings.shared.windowShadow
        session.end()
        Task { @MainActor in
            do {
                let (img, scale) = try await ScreenCapturer.captureWindow(w.id, shadow: shadow)
                Exporter.deliver(img, scale: scale)
            } catch {
                Toast.show(L("窗口截图失败：%@", error.localizedDescription))
            }
        }
    }

    private func captureMulti() {
        let ids = multi.map(\.id)
        let shadow = Settings.shared.windowShadow
        let all = WindowList.onScreen()
        session.end()
        Task { @MainActor in
            do {
                var parts: [(CGImage, CGFloat, CGRect)] = []
                for id in ids {
                    guard let entry = all.first(where: { $0.id == id }) else { continue }
                    let (img, s) = try await ScreenCapturer.captureWindow(id, shadow: shadow)
                    // 图片（可能含阴影）以窗口中心对齐
                    let size = CGSize(width: CGFloat(img.width) / s, height: CGFloat(img.height) / s)
                    let r = CGRect(x: entry.frame.midX - size.width / 2, y: entry.frame.midY - size.height / 2,
                                   width: size.width, height: size.height)
                    parts.append((img, s, r))
                }
                guard !parts.isEmpty else { return }
                let scale = parts.map(\.1).max() ?? 2
                let union = parts.map(\.2).reduce(parts[0].2) { $0.union($1) }
                guard let ctx = ImageUtil.makeContext(width: Int(union.width * scale), height: Int(union.height * scale)) else { return }
                ctx.interpolationQuality = .high
                // ids 顺序为点选顺序；先画后点选的（假设在下层）——按屏幕层级从后往前画
                let order = all.map(\.id)
                let sorted = zip(ids, parts).sorted { (order.firstIndex(of: $0.0) ?? 0) > (order.firstIndex(of: $1.0) ?? 0) }
                for (_, part) in sorted {
                    let r = part.2
                    ctx.draw(part.0, in: CGRect(x: (r.minX - union.minX) * scale, y: (r.minY - union.minY) * scale,
                                                width: r.width * scale, height: r.height * scale))
                }
                if let out = ctx.makeImage() { Exporter.deliver(out, scale: scale) }
            } catch {
                Toast.show(L("多窗口截图失败：%@", error.localizedDescription))
            }
        }
    }

    // MARK: - 键盘

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        switch event.keyCode {
        case 53: // Esc
            if !multi.isEmpty { multi.removeAll(); needsDisplay = true } else { session.end() }
            return
        case 36, 76: // Return / Enter
            if !multi.isEmpty { captureMulti() }
            else if phase == .editing { finish(.defaultAction) }
            else if let h = hover {
                session.didBeginSelection(in: self)
                selection = h.rect
                enterEditing()
                if session.mode == .normal { finish(.defaultAction) }
            }
            return
        case 51, 117: // Delete
            deleteSelected()
            return
        case 123, 124, 125, 126:
            nudge(keyCode: event.keyCode, big: mods.contains(.shift))
            return
        default:
            break
        }

        if mods.contains(.command) {
            switch chars {
            case "c": if phase == .editing { finish(.copy) }
            case "s": if phase == .editing { finish(.save) }
            case "z": mods.contains(.shift) ? redo() : undo()
            default: break
            }
            return
        }

        if phase == .choosing {
            if chars == "c" { copyColor(rgb: mods.contains(.shift)) }
            return
        }

        if let t = Tool.allCases.first(where: { $0.key == chars }) {
            setTool(tool == t ? nil : t)
        }
    }

    private func nudge(keyCode: UInt16, big: Bool) {
        let d: CGFloat = big ? 10 : 1
        var dx: CGFloat = 0, dy: CGFloat = 0
        switch keyCode {
        case 123: dx = -d
        case 124: dx = d
        case 125: dy = d
        default: dy = -d
        }
        if phase == .choosing {
            guard let m = mouse, let primary = NSScreen.screens.first else { return }
            let np = CGPoint(x: min(max(0, m.x + dx), bounds.width - 1),
                             y: min(max(0, m.y + dy), bounds.height - 1))
            let global = CGPoint(x: snapshot.frame.minX + np.x, y: snapshot.frame.maxY - np.y)
            CGWarpMouseCursorPosition(CGPoint(x: global.x, y: primary.frame.height - global.y))
            CGAssociateMouseAndMouseCursorPosition(1)
            mouse = np
            updateHover(np)
        } else if let i = selectedIndex {
            pushUndo()
            annotations[i].move(dx: dx, dy: dy)
        } else {
            var r = selection.offsetBy(dx: dx, dy: dy)
            r.origin.x = min(max(0, r.origin.x), bounds.width - r.width)
            r.origin.y = min(max(0, r.origin.y), bounds.height - r.height)
            selection = r
            layoutToolbar()
        }
        needsDisplay = true
    }

    private func copyColor(rgb: Bool) {
        guard let m = mouse, let px = pixels else { return }
        let x = Int(m.x * scale), y = Int(m.y * scale)
        guard let c = px.rgb(x: x, y: y), let hex = px.hex(x: x, y: y) else { return }
        let text = rgb ? "rgb(\(c.r), \(c.g), \(c.b))" : hex
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        session.end()
        Toast.show(L("已复制颜色 %@", text))
    }

    // MARK: - 撤销

    private func pushUndo() {
        undoStack.append(annotations)
        redoStack.removeAll()
    }

    private func undo() {
        commitText()
        guard let last = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = last
        selectedIndex = nil
        refreshToolbar()
        needsDisplay = true
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        selectedIndex = nil
        refreshToolbar()
        needsDisplay = true
    }

    private func deleteSelected() {
        guard let i = selectedIndex, i < annotations.count else { return }
        pushUndo()
        annotations.remove(at: i)
        selectedIndex = nil
        refreshToolbar()
        layoutToolbar()
        needsDisplay = true
    }

    // MARK: - 文字

    private func startText(at p: CGPoint, initial: String, original: Annotation?) {
        let size = original?.fontSize ?? style.fontSize
        let color = original?.color ?? style.color
        let field = NSTextField(string: initial)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.font = Annotation.font(size)
        field.textColor = color
        field.delegate = self
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.wantsLayer = true
        field.layer?.borderWidth = 1
        field.layer?.borderColor = NSColor.white.withAlphaComponent(0.7).cgColor
        field.layer?.cornerRadius = 3
        field.placeholderAttributedString = NSAttributedString(string: L("输入文字"), attributes: [
            .font: Annotation.font(size), .foregroundColor: color.withAlphaComponent(0.4),
        ])
        addSubview(field)
        textField = field
        textOrigin = p
        textOriginal = original
        resizeTextField()
        window?.makeFirstResponder(field)
    }

    private func resizeTextField() {
        guard let f = textField, let font = f.font else { return }
        let text = f.stringValue.isEmpty ? L("输入文字") : f.stringValue
        let size = (text as NSString).size(withAttributes: [.font: font])
        f.frame = CGRect(x: textOrigin.x - 2, y: textOrigin.y - 1, width: max(60, size.width + 14), height: size.height + 4)
    }

    func controlTextDidChange(_ obj: Notification) { resizeTextField() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { commitText(); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { cancelText(); return true }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitText() }

    private func commitText() {
        guard let f = textField else { return }
        textField = nil
        let text = f.stringValue
        let color = f.textColor ?? style.color
        let size = f.font?.pointSize ?? style.fontSize
        f.removeFromSuperview()
        if !text.isEmpty {
            if textOriginal == nil { pushUndo() }
            var a = Annotation(tool: .text, color: color, lineWidth: 0, points: [textOrigin])
            a.text = text
            a.fontSize = size
            annotations.append(a)
        }
        textOriginal = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func cancelText() {
        guard let f = textField else { return }
        textField = nil
        f.removeFromSuperview()
        if let o = textOriginal {
            annotations.append(o)
            _ = undoStack.popLast()
        }
        textOriginal = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func editText(at i: Int) {
        pushUndo()
        let a = annotations.remove(at: i)
        selectedIndex = nil
        startText(at: a.points[0], initial: a.text, original: a)
        needsDisplay = true
    }

    // MARK: - 输出

    enum FinishAction { case defaultAction, copy, save, pin, ocr, scroll }

    func finish(_ action: FinishAction) {
        commitText()
        guard selection.width >= 1, selection.height >= 1 else { return }
        switch action {
        case .scroll:
            let rect = selection
            let screen = snapshot.screen
            let s = scale
            session.end()
            ScrollCaptureController.start(screen: screen, rectInScreen: rect, scale: s)
        case .ocr:
            guard let img = render(withAnnotations: false) else { return }
            session.end()
            OCRService.run(on: img)
        case .pin:
            guard let img = render(withAnnotations: true) else { return }
            let frame = globalRect(selection)
            let s = scale
            session.end(restoreFocus: false)
            ShutterSound.play()
            PinWindow.pin(img, scale: s, frame: frame)
        case .defaultAction, .copy, .save:
            guard let img = render(withAnnotations: true) else { return }
            let s = scale
            session.end()
            let a: DefaultAction? = action == .copy ? .copy : (action == .save ? .save : nil)
            Exporter.deliver(img, scale: s, action: a)
        }
    }

    /// 以原始像素密度渲染选区（含标注）
    func render(withAnnotations: Bool) -> CGImage? {
        let sel = selection
        let pixelRect = CGRect(x: (sel.minX * scale).rounded(), y: (sel.minY * scale).rounded(),
                               width: (sel.width * scale).rounded(), height: (sel.height * scale).rounded())
            .intersection(CGRect(x: 0, y: 0, width: snapshot.image.width, height: snapshot.image.height))
        guard !pixelRect.isEmpty else { return nil }
        if !withAnnotations || annotations.isEmpty {
            return snapshot.image.cropping(to: pixelRect)
        }
        let pw = Int(pixelRect.width), ph = Int(pixelRect.height)
        guard let ctx = ImageUtil.makeContext(width: pw, height: ph, colorSpace: snapshot.image.colorSpace) else { return nil }
        ctx.interpolationQuality = .high
        ctx.translateBy(x: 0, y: CGFloat(ph))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -pixelRect.minX / scale, y: -pixelRect.minY / scale)
        let g = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = g
        baseImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        drawAnnotations(in: ctx)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
}
