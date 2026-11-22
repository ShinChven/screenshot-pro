import AppKit

enum Tool: String, CaseIterable {
    case rect, ellipse, arrow, line, pen, highlighter, text, mosaic, step

    var key: String {
        switch self {
        case .rect: return "r"
        case .ellipse: return "o"
        case .arrow: return "a"
        case .line: return "l"
        case .pen: return "p"
        case .highlighter: return "h"
        case .text: return "t"
        case .mosaic: return "m"
        case .step: return "n"
        }
    }

    var title: String {
        switch self {
        case .rect: return L("矩形")
        case .ellipse: return L("椭圆")
        case .arrow: return L("箭头")
        case .line: return L("直线")
        case .pen: return L("画笔")
        case .highlighter: return L("荧光笔")
        case .text: return L("文字")
        case .mosaic: return L("马赛克")
        case .step: return L("序号")
        }
    }

    var symbol: String {
        switch self {
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .pen: return "pencil"
        case .highlighter: return "highlighter"
        case .text: return "textformat"
        case .mosaic: return "checkerboard.rectangle"
        case .step: return "1.circle"
        }
    }
}

struct AnnotationStyle {
    static let palette: [NSColor] = [
        NSColor(srgbRed: 0.98, green: 0.23, blue: 0.21, alpha: 1),   // 红
        NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1),   // 橙
        NSColor(srgbRed: 1.00, green: 0.83, blue: 0.00, alpha: 1),   // 黄
        NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1),   // 绿
        NSColor(srgbRed: 0.00, green: 0.48, blue: 1.00, alpha: 1),   // 蓝
        NSColor(srgbRed: 0.69, green: 0.32, blue: 0.87, alpha: 1),   // 紫
        NSColor(srgbRed: 0.10, green: 0.10, blue: 0.10, alpha: 1),   // 黑
        NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1),   // 白
    ]

    var colorIndex: Int
    var widthLevel: Int
    var filled: Bool
    var mosaicBrush: Bool

    var color: NSColor { Self.palette[max(0, min(Self.palette.count - 1, colorIndex))] }
    private var level: Int { max(0, min(2, widthLevel)) }

    func lineWidth(for tool: Tool) -> CGFloat {
        switch tool {
        case .highlighter: return [12, 20, 30][level]
        case .mosaic: return [16, 28, 44][level]
        case .step: return [11, 14, 18][level]          // 序号圆半径
        default: return [2, 4, 7][level]
        }
    }

    var fontSize: CGFloat { [16, 22, 32][level] }

    static var current: AnnotationStyle {
        let s = Settings.shared
        return AnnotationStyle(colorIndex: s.colorIndex, widthLevel: s.widthLevel, filled: s.filled,
                               mosaicBrush: s.mosaicBrush)
    }

    func save() {
        let s = Settings.shared
        s.colorIndex = colorIndex
        s.widthLevel = widthLevel
        s.filled = filled
        s.mosaicBrush = mosaicBrush
    }
}

/// 一个标注。坐标为遮罩视图坐标（左上原点，单位 pt）
struct Annotation {
    var tool: Tool
    var color: NSColor
    var lineWidth: CGFloat
    var filled = false
    var mosaicBrush = false
    var points: [CGPoint]
    var text = ""
    var fontSize: CGFloat = 22

    var isFreehand: Bool { tool == .pen || tool == .highlighter || (tool == .mosaic && mosaicBrush) }

    var rect: CGRect {
        guard let a = points.first, let b = points.last else { return .zero }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    static func font(_ size: CGFloat) -> NSFont { .systemFont(ofSize: size, weight: .semibold) }

    var textAttributes: [NSAttributedString.Key: Any] {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 1.5
        return [.font: Self.font(fontSize), .foregroundColor: color, .shadow: shadow]
    }

    var isValid: Bool {
        switch tool {
        case .text: return !text.isEmpty
        case .step: return true
        default:
            if isFreehand { return points.count > 1 }
            guard let a = points.first, let b = points.last else { return false }
            return hypot(a.x - b.x, a.y - b.y) > 3
        }
    }

    var bounds: CGRect {
        switch tool {
        case .text:
            let size = (text as NSString).size(withAttributes: textAttributes)
            return CGRect(origin: points.first ?? .zero, size: size)
        case .step:
            let p = points.first ?? .zero
            return CGRect(x: p.x - lineWidth, y: p.y - lineWidth, width: lineWidth * 2, height: lineWidth * 2)
        case .mosaic where !mosaicBrush:
            return rect
        default:
            if isFreehand {
                let xs = points.map(\.x), ys = points.map(\.y)
                guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .zero }
                return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                    .insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
            }
            return rect.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
        }
    }

    func hitTest(_ p: CGPoint) -> Bool {
        let tolerance = max(6, lineWidth / 2 + 3)
        switch tool {
        case .line, .arrow:
            guard let a = points.first, let b = points.last else { return false }
            return Self.distance(p, a, b) <= tolerance
        case .rect, .ellipse:
            if filled { return bounds.insetBy(dx: -3, dy: -3).contains(p) }
            let outer = rect.insetBy(dx: -tolerance, dy: -tolerance)
            let inner = rect.insetBy(dx: tolerance, dy: tolerance)
            return outer.contains(p) && (inner.isEmpty || !inner.contains(p))
        case .pen, .highlighter:
            guard points.count > 1 else { return false }
            for i in 1..<points.count where Self.distance(p, points[i - 1], points[i]) <= tolerance { return true }
            return false
        default:
            return bounds.insetBy(dx: -4, dy: -4).contains(p)
        }
    }

    mutating func move(dx: CGFloat, dy: CGFloat) {
        points = points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
    }

    static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

/// 在当前 NSGraphicsContext（需为 flipped）中绘制标注
enum AnnotationRenderer {
    static func draw(_ a: Annotation, number: Int, mosaic: NSImage?, imageRect: CGRect, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let color = a.color.cgColor

        switch a.tool {
        case .rect:
            if a.filled {
                ctx.setFillColor(color)
                ctx.fill(a.rect)
            } else {
                ctx.setStrokeColor(color)
                ctx.setLineWidth(a.lineWidth)
                ctx.addPath(CGPath(roundedRect: a.rect, cornerWidth: min(2, a.rect.width / 2),
                                   cornerHeight: min(2, a.rect.height / 2), transform: nil))
                ctx.strokePath()
            }
        case .ellipse:
            if a.filled {
                ctx.setFillColor(color)
                ctx.fillEllipse(in: a.rect)
            } else {
                ctx.setStrokeColor(color)
                ctx.setLineWidth(a.lineWidth)
                ctx.strokeEllipse(in: a.rect)
            }
        case .line:
            guard let s = a.points.first, let e = a.points.last else { return }
            ctx.setStrokeColor(color)
            ctx.setLineWidth(a.lineWidth)
            ctx.move(to: s)
            ctx.addLine(to: e)
            ctx.strokePath()
        case .arrow:
            guard let s = a.points.first, let e = a.points.last else { return }
            drawArrow(from: s, to: e, width: a.lineWidth, color: color, in: ctx)
        case .pen:
            ctx.setStrokeColor(color)
            ctx.setLineWidth(a.lineWidth)
            ctx.addPath(smoothPath(a.points))
            ctx.strokePath()
        case .highlighter:
            ctx.setBlendMode(.multiply)
            ctx.setLineCap(.square)
            ctx.setStrokeColor(a.color.withAlphaComponent(0.45).cgColor)
            ctx.setLineWidth(a.lineWidth)
            ctx.addPath(smoothPath(a.points))
            ctx.strokePath()
        case .text:
            guard let p = a.points.first else { return }
            (a.text as NSString).draw(at: p, withAttributes: a.textAttributes)
        case .step:
            guard let p = a.points.first else { return }
            let r = a.lineWidth
            let circle = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: NSColor.black.withAlphaComponent(0.3).cgColor)
            ctx.setFillColor(color)
            ctx.fillEllipse(in: circle)
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(max(1.5, r * 0.12))
            ctx.strokeEllipse(in: circle.insetBy(dx: 0.75, dy: 0.75))
            let isLight = a.color.brightnessComponentSafe > 0.85
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: r * (number >= 10 ? 0.95 : 1.15), weight: .bold),
                .foregroundColor: isLight ? NSColor.black : NSColor.white,
            ]
            let s = "\(number)" as NSString
            let size = s.size(withAttributes: attrs)
            s.draw(at: CGPoint(x: p.x - size.width / 2, y: p.y - size.height / 2), withAttributes: attrs)
        case .mosaic:
            guard let mosaic else { return }
            if a.mosaicBrush {
                let path = smoothPath(a.points).copy(strokingWithWidth: a.lineWidth, lineCap: .round,
                                                     lineJoin: .round, miterLimit: 10)
                ctx.addPath(path)
            } else {
                ctx.addRect(a.rect)
            }
            ctx.clip()
            mosaic.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    static func drawArrow(from s: CGPoint, to e: CGPoint, width w: CGFloat, color: CGColor, in ctx: CGContext) {
        let dx = e.x - s.x, dy = e.y - s.y
        let len = hypot(dx, dy)
        guard len > 1 else { return }
        let ux = dx / len, uy = dy / len
        let head = min(max(12, w * 3.8), len * 0.8)
        let half = head * 0.48
        let base = CGPoint(x: e.x - ux * head, y: e.y - uy * head)
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(w)
        ctx.move(to: s)
        ctx.addLine(to: CGPoint(x: e.x - ux * head * 0.7, y: e.y - uy * head * 0.7))
        ctx.strokePath()
        ctx.setLineWidth(1)
        ctx.move(to: e)
        ctx.addLine(to: CGPoint(x: base.x - uy * half, y: base.y + ux * half))
        ctx.addLine(to: CGPoint(x: base.x + uy * half, y: base.y - ux * half))
        ctx.closePath()
        ctx.drawPath(using: .fillStroke)
    }

    static func smoothPath(_ pts: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = pts.first else { return path }
        path.move(to: first)
        if pts.count < 3 {
            if pts.count == 1 { path.addLine(to: first) } else { path.addLine(to: pts[1]) }
            return path
        }
        for i in 1..<(pts.count - 1) {
            let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2, y: (pts[i].y + pts[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: pts[i])
        }
        path.addLine(to: pts[pts.count - 1])
        return path
    }
}

extension NSColor {
    var brightnessComponentSafe: CGFloat {
        (usingColorSpace(.sRGB) ?? self).brightnessComponent
    }
}
