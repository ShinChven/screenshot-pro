import AppKit

/// 工具栏按钮
final class BarButton: NSButton {
    private let handler: () -> Void

    var isActive = false {
        didSet {
            layer?.backgroundColor = isActive ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        }
    }

    init(symbol: String, tip: String, tint: NSColor = .white, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: CGRect(x: 0, y: 0, width: 30, height: 28))
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let tip = L(tip)
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?.withSymbolConfiguration(config) {
            image = img
            imagePosition = .imageOnly
            title = ""
        } else {
            attributedTitle = NSAttributedString(string: String(tip.prefix(1)),
                                                 attributes: [.foregroundColor: tint, .font: NSFont.systemFont(ofSize: 12)])
        }
        isBordered = false
        contentTintColor = tint
        toolTip = tip
        wantsLayer = true
        layer?.cornerRadius = 6
        refusesFirstResponder = true
        target = self
        action = #selector(fire)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 30).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}

/// 可点击的小圆点（颜色 / 粗细）
final class DotButton: NSView {
    enum Kind { case color(NSColor), size(CGFloat) }

    private let kind: Kind
    private let handler: () -> Void
    var isActive = false { didSet { needsDisplay = true } }

    init(_ kind: Kind, tip: String, handler: @escaping () -> Void) {
        self.kind = kind
        self.handler = handler
        super.init(frame: CGRect(x: 0, y: 0, width: 24, height: 28))
        toolTip = L(tip)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 24).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { handler() }

    override func draw(_ dirtyRect: NSRect) {
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        switch kind {
        case .color(let color):
            let r: CGFloat = 8
            let circle = NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            color.setFill()
            circle.fill()
            NSColor.white.withAlphaComponent(0.35).setStroke()
            circle.lineWidth = 1
            circle.stroke()
            if isActive {
                let ring = NSBezierPath(ovalIn: CGRect(x: c.x - r - 3, y: c.y - r - 3, width: (r + 3) * 2, height: (r + 3) * 2))
                ring.lineWidth = 2
                NSColor.white.setStroke()
                ring.stroke()
            }
        case .size(let d):
            if isActive {
                let bg = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 2), xRadius: 5, yRadius: 5)
                NSColor.controlAccentColor.setFill()
                bg.fill()
            }
            NSColor.white.setFill()
            NSBezierPath(ovalIn: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)).fill()
        }
    }
}

/// 深色圆角底板，吞掉点击，避免穿透到遮罩
final class BarPanel: NSView {
    let stack = NSStackView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.95).cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 5, bottom: 3, right: 5)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }

    func clear() {
        for v in stack.arrangedSubviews {
            stack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
    }

    static func separator() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return v
    }
}

/// 选区下方的标注工具栏 + 样式栏
final class Toolbar: NSView {
    enum Action { case undo, redo, ocr, scroll, pin, save, cancel, done }

    var onTool: ((Tool) -> Void)?
    var onAction: ((Action) -> Void)?
    var onColor: ((Int) -> Void)?
    var onWidth: ((Int) -> Void)?
    var onToggleFill: (() -> Void)?
    var onToggleMosaicMode: (() -> Void)?

    private let main = BarPanel()
    private let options = BarPanel()
    private var toolButtons: [Tool: BarButton] = [:]

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        buildMain()
        addSubview(main)
        addSubview(options)
        options.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildMain() {
        for tool in Tool.allCases {
            let b = BarButton(symbol: tool.symbol, tip: "\(tool.title) (\(tool.key.uppercased()))") { [weak self] in
                self?.onTool?(tool)
            }
            toolButtons[tool] = b
            main.stack.addArrangedSubview(b)
        }
        main.stack.addArrangedSubview(BarPanel.separator())
        let actions: [(String, String, Action, NSColor)] = [
            ("arrow.uturn.backward", "撤销（⌘Z）", .undo, .white),
            ("arrow.uturn.forward", "重做（⇧⌘Z）", .redo, .white),
        ]
        for (sym, tip, action, tint) in actions {
            main.stack.addArrangedSubview(BarButton(symbol: sym, tip: tip, tint: tint) { [weak self] in self?.onAction?(action) })
        }
        main.stack.addArrangedSubview(BarPanel.separator())
        let outputs: [(String, String, Action, NSColor)] = [
            ("text.viewfinder", "识别文字（OCR）", .ocr, .white),
            ("arrow.up.and.down.text.horizontal", "长截图（滚动截图）", .scroll, .white),
            ("pin", "钉在屏幕上", .pin, .white),
            ("square.and.arrow.down", "保存（⌘S）", .save, .white),
            ("xmark", "取消（Esc）", .cancel, NSColor(srgbRed: 1, green: 0.4, blue: 0.4, alpha: 1)),
            ("checkmark", "完成（↩）", .done, NSColor(srgbRed: 0.35, green: 0.9, blue: 0.45, alpha: 1)),
        ]
        for (sym, tip, action, tint) in outputs {
            main.stack.addArrangedSubview(BarButton(symbol: sym, tip: tip, tint: tint) { [weak self] in self?.onAction?(action) })
        }
    }

    /// 根据当前工具 / 选中的标注刷新高亮和样式栏
    func update(tool: Tool?, styleTool: Tool?, style: AnnotationStyle) {
        for (t, b) in toolButtons { b.isActive = (t == tool) }
        options.clear()
        if let t = styleTool {
            if t != .mosaic {
                for (i, color) in AnnotationStyle.palette.enumerated() {
                    let dot = DotButton(.color(color), tip: "颜色") { [weak self] in self?.onColor?(i) }
                    dot.isActive = (i == style.colorIndex)
                    options.stack.addArrangedSubview(dot)
                }
                options.stack.addArrangedSubview(BarPanel.separator())
            }
            let label = t == .text ? "字号" : (t == .step ? "大小" : "粗细")
            for (i, d) in [CGFloat(4), 7, 11].enumerated() {
                let dot = DotButton(.size(d), tip: label) { [weak self] in self?.onWidth?(i) }
                dot.isActive = (i == style.widthLevel)
                options.stack.addArrangedSubview(dot)
            }
            if t == .rect || t == .ellipse {
                options.stack.addArrangedSubview(BarPanel.separator())
                let fill = BarButton(symbol: t == .rect ? "square.fill" : "circle.fill", tip: "实心填充") { [weak self] in
                    self?.onToggleFill?()
                }
                fill.isActive = style.filled
                options.stack.addArrangedSubview(fill)
            }
            if t == .mosaic {
                options.stack.addArrangedSubview(BarPanel.separator())
                let rect = BarButton(symbol: "rectangle.dashed", tip: "方形马赛克（可拖动、调整大小）") { [weak self] in
                    if style.mosaicBrush { self?.onToggleMosaicMode?() }
                }
                rect.isActive = !style.mosaicBrush
                let brush = BarButton(symbol: "scribble", tip: "涂抹马赛克") { [weak self] in
                    if !style.mosaicBrush { self?.onToggleMosaicMode?() }
                }
                brush.isActive = style.mosaicBrush
                options.stack.addArrangedSubview(rect)
                options.stack.addArrangedSubview(brush)
            }
        }
        options.isHidden = styleTool == nil
        layoutBars()
    }

    private func layoutBars() {
        let m = main.fittingSize
        let o = options.isHidden ? .zero : options.fittingSize
        let width = max(m.width, o.width)
        main.frame = CGRect(x: width - m.width, y: 0, width: m.width, height: m.height)
        if !options.isHidden {
            options.frame = CGRect(x: width - o.width, y: m.height + 4, width: o.width, height: o.height)
        }
        setFrameSize(CGSize(width: width, height: m.height + (options.isHidden ? 0 : o.height + 4)))
    }

    var preferredSize: CGSize { frame.size }
}
