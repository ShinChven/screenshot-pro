// 生成 App 图标：swift scripts/make-icon.swift <输出的 .iconset 目录>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // 背景：圆角方块 + 渐变
    let inset = s * 0.09
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = CGPath(roundedRect: body, cornerWidth: s * 0.2, cornerHeight: s * 0.2, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.03,
                  color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(path)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let colors = [NSColor(srgbRed: 0.18, green: 0.48, blue: 1.0, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.45, green: 0.25, blue: 0.95, alpha: 1).cgColor] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    ctx.restoreGState()

    // 取景框四角
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(s * 0.055)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let f = body.insetBy(dx: s * 0.16, dy: s * 0.16)
    let l = f.width * 0.26
    for (corner, dx, dy) in [(CGPoint(x: f.minX, y: f.minY), 1.0, 1.0), (CGPoint(x: f.maxX, y: f.minY), -1.0, 1.0),
                             (CGPoint(x: f.minX, y: f.maxY), 1.0, -1.0), (CGPoint(x: f.maxX, y: f.maxY), -1.0, -1.0)] {
        ctx.move(to: CGPoint(x: corner.x, y: corner.y + l * dy))
        ctx.addLine(to: corner)
        ctx.addLine(to: CGPoint(x: corner.x + l * dx, y: corner.y))
    }
    ctx.strokePath()

    // 中间的箭头标注
    ctx.setLineWidth(s * 0.05)
    let a = CGPoint(x: f.minX + f.width * 0.3, y: f.minY + f.height * 0.3)
    let b = CGPoint(x: f.maxX - f.width * 0.3, y: f.maxY - f.height * 0.3)
    ctx.move(to: a)
    ctx.addLine(to: b)
    ctx.strokePath()
    let head = s * 0.12
    ctx.move(to: b)
    ctx.addLine(to: CGPoint(x: b.x - head, y: b.y - head * 0.25))
    ctx.addLine(to: CGPoint(x: b.x - head * 0.25, y: b.y - head))
    ctx.closePath()
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: out.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: out.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
print("icon written to \(out.path)")
