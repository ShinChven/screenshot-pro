import AppKit
import SwiftUI

/// `ScreenshotPro --selftest`：不需要屏幕权限的离线自检
enum SelfTest {
    static func run() -> Bool {
        var ok = true
        ok = check("长截图拼接（带吸顶头部和底栏）", testStitch(offsets: [0, 50, 120, 121, 300, 450, 451, 700], header: 40, footer: 30)) && ok
        ok = check("长截图拼接（无固定区域）", testStitch(offsets: [0, 80, 200, 333, 500], header: 0, footer: 0)) && ok
        ok = check("长截图：静止帧不追加", testStitch(offsets: [0, 0, 0, 90, 90, 200], header: 20, footer: 0)) && ok
        ok = check("标注渲染（离屏）", testRender()) && ok
        ok = check("快门声音效可加载", ShutterSound.isAvailable) && ok
        ok = check("交互：方形马赛克绘制 / 拖动 / 调整大小 / 撤销", testInteraction()) && ok
        ok = check("快捷键显示", Shortcut(keyCode: 19, carbonModifiers: Shortcut.carbonModifiers(from: [.command, .shift])).display == "⇧⌘2") && ok
        print(ok ? "ALL PASSED" : "SOME FAILED")
        return ok
    }

    /// 用合成的鼠标 / 键盘事件驱动遮罩视图
    private static func testInteraction() -> Bool {
        _ = NSApplication.shared
        guard let screen = NSScreen.main else { print("   没有屏幕，跳过"); return true }
        let size = CGSize(width: 800, height: 600)
        var pixels = [UInt8](repeating: 200, count: Int(size.width * size.height) * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) { pixels[i] = UInt8((i / 4) % 251) }
        let image = makeImage(pixels, width: Int(size.width), height: Int(size.height))
        let snap = DisplaySnapshot(screen: screen, frame: CGRect(origin: .zero, size: size), scale: 1, image: image)
        let session = CaptureSession.makeForTesting()
        let view = OverlayView(frame: CGRect(origin: .zero, size: size), snapshot: snap, windows: [], session: session)
        let window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: size.width, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        view.testSetMosaicBrush(false)
        defer { window.orderOut(nil) }

        func mouse(_ type: NSEvent.EventType, _ p: CGPoint, shift: Bool = false) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: p.x, y: size.height - p.y),
                               modifierFlags: shift ? .shift : [], timestamp: 0, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func drag(_ a: CGPoint, _ b: CGPoint) {
            view.mouseDown(with: mouse(.leftMouseDown, a))
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            view.mouseDragged(with: mouse(.leftMouseDragged, mid))
            view.mouseDragged(with: mouse(.leftMouseDragged, b))
            view.mouseUp(with: mouse(.leftMouseUp, b))
        }
        func key(_ chars: String, code: UInt16, cmd: Bool = false, shift: Bool = false) {
            var flags: NSEvent.ModifierFlags = []
            if cmd { flags.insert(.command) }
            if shift { flags.insert(.shift) }
            let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                     windowNumber: window.windowNumber, context: nil, characters: chars,
                                     charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
            view.keyDown(with: e)
        }
        var failures: [String] = []
        func expect(_ cond: Bool, _ msg: String) { if !cond { failures.append(msg) } }

        // 1. 框选区域
        drag(CGPoint(x: 100, y: 100), CGPoint(x: 600, y: 500))
        expect(view.testSelection == CGRect(x: 100, y: 100, width: 500, height: 400), "选区 \(view.testSelection)")

        // 2. 画方形马赛克，自动选中
        key("m", code: 46)
        drag(CGPoint(x: 150, y: 150), CGPoint(x: 250, y: 250))
        expect(view.testAnnotations.count == 1, "马赛克数量 \(view.testAnnotations.count)")
        expect(view.testAnnotations.first?.mosaicBrush == false, "马赛克应为方形")
        expect(view.testAnnotations.first?.rect == CGRect(x: 150, y: 150, width: 100, height: 100), "马赛克区域 \(String(describing: view.testAnnotations.first?.rect))")
        expect(view.testSelectedIndex == 0, "画完应自动选中")

        // 3. 在马赛克内部拖动（工具仍是马赛克）→ 移动而不是新画
        drag(CGPoint(x: 200, y: 200), CGPoint(x: 230, y: 210))
        expect(view.testAnnotations.count == 1, "拖动时不应新建标注")
        expect(view.testAnnotations.first?.rect == CGRect(x: 180, y: 160, width: 100, height: 100), "移动后 \(String(describing: view.testAnnotations.first?.rect))")

        // 4. 拖右下角控制点调整大小
        drag(CGPoint(x: 280, y: 260), CGPoint(x: 330, y: 320))
        expect(view.testAnnotations.first?.rect == CGRect(x: 180, y: 160, width: 150, height: 160), "调整大小后 \(String(describing: view.testAnnotations.first?.rect))")

        // 5. 切到矩形工具，在空白处画一个空心矩形；再拖它的边框移动
        key("r", code: 15)
        drag(CGPoint(x: 400, y: 300), CGPoint(x: 500, y: 380))
        expect(view.testAnnotations.count == 2, "矩形数量 \(view.testAnnotations.count)")
        drag(CGPoint(x: 430, y: 300), CGPoint(x: 450, y: 310))   // 上边框（非控制点）
        expect(view.testAnnotations.count == 2, "拖动矩形边框不应新建")
        expect(view.testAnnotations.last?.rect == CGRect(x: 420, y: 310, width: 100, height: 80), "矩形移动后 \(String(describing: view.testAnnotations.last?.rect))")

        // 6. 箭头端点
        key("a", code: 0)
        drag(CGPoint(x: 120, y: 450), CGPoint(x: 200, y: 450))
        drag(CGPoint(x: 200, y: 450), CGPoint(x: 260, y: 470))
        expect(view.testAnnotations.last?.points.last == CGPoint(x: 260, y: 470), "箭头端点 \(String(describing: view.testAnnotations.last?.points))")

        // 7. 撤销三次：回到只有一个马赛克（调整大小后）
        key("z", code: 6, cmd: true)
        key("z", code: 6, cmd: true)
        key("z", code: 6, cmd: true)
        key("z", code: 6, cmd: true)
        expect(view.testAnnotations.count == 1, "撤销后数量 \(view.testAnnotations.count)")
        expect(view.testAnnotations.first?.rect == CGRect(x: 180, y: 160, width: 150, height: 160), "撤销后马赛克 \(String(describing: view.testAnnotations.first?.rect))")

        // 8. 渲染包含马赛克
        let rendered = view.render(withAnnotations: true)
        expect(rendered?.width == 500 && rendered?.height == 400, "渲染尺寸")

        for f in failures { print("   \(f)") }
        return failures.isEmpty
    }

    /// `--render-settings <png>`：把设置窗口渲染成图片，用于检查排版
    static func renderSettings(to path: String) -> Bool {
        let host = NSHostingView(rootView: SettingsView(height: 1400))
        host.frame = CGRect(x: 0, y: 0, width: 520, height: 1400)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return false }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }

    private static func check(_ name: String, _ passed: Bool) -> Bool {
        print("\(passed ? "✅" : "❌") \(name)")
        return passed
    }

    // 生成一张「长网页」：header + 内容 + footer，按 offset 取视口
    private static func testStitch(offsets: [Int], header: Int, footer: Int) -> Bool {
        let width = 320, viewport = 600
        let contentRows = viewport - header - footer
        let totalContent = (offsets.max() ?? 0) + contentRows
        var rng = UInt64(42)
        func rand() -> UInt8 {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return UInt8(truncatingIfNeeded: rng >> 33)
        }
        // 内容：每 14 行一个「文字行」，随机色块；中间穿插空白
        var content = [UInt8](repeating: 255, count: totalContent * width * 4)
        var y = 0
        while y < totalContent {
            let lineH = 10
            var x = 8
            while x < width - 8 {
                let w = Int(rand() % 30) + 6
                let g = rand() % 160
                for yy in y..<min(y + lineH, totalContent) {
                    for xx in x..<min(x + w, width) {
                        let i = (yy * width + xx) * 4
                        content[i] = g; content[i + 1] = g &+ 20; content[i + 2] = g &+ 40; content[i + 3] = 255
                    }
                }
                x += w + Int(rand() % 8) + 2
            }
            y += 14 + Int(rand() % 4)
        }
        func fixedRows(_ n: Int, seed: UInt8) -> [UInt8] {
            var d = [UInt8](repeating: 0, count: n * width * 4)
            for i in stride(from: 0, to: d.count, by: 4) {
                let px = (i / 4) % width
                d[i] = seed; d[i + 1] = UInt8(px % 200); d[i + 2] = 200; d[i + 3] = 255
            }
            return d
        }
        let head = fixedRows(header, seed: 30), foot = fixedRows(footer, seed: 90)

        func frame(_ off: Int) -> CGImage {
            var d = head
            d += content[(off * width * 4)..<((off + contentRows) * width * 4)]
            d += foot
            return makeImage(d, width: width, height: viewport)
        }

        let stitcher = ScrollStitcher()
        for off in offsets { _ = stitcher.add(frame(off)) }
        guard let result = stitcher.result() else { return false }

        let expectedRows = header + totalContent + footer
        var expected = head
        expected += content
        expected += foot
        guard result.height == expectedRows, result.width == width else {
            print("   高度 \(result.height)，期望 \(expectedRows)")
            return false
        }
        let actual = readPixels(result)
        var mismatched = 0
        for i in stride(from: 0, to: expected.count, by: 4) where abs(Int(expected[i]) - Int(actual[i])) > 2 { mismatched += 1 }
        if mismatched > 0 { print("   像素不一致：\(mismatched)") }
        return mismatched == 0
    }

    private static func testRender() -> Bool {
        let size = 200
        guard let ctx = ImageUtil.makeContext(width: size, height: size) else { return false }
        ctx.translateBy(x: 0, y: CGFloat(size))
        ctx.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let red = AnnotationStyle.palette[0]
        let rect = Annotation(tool: .rect, color: red, lineWidth: 4, filled: true, points: [CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 40)])
        AnnotationRenderer.draw(rect, number: 0, mosaic: nil, imageRect: .zero, in: ctx)
        let step = Annotation(tool: .step, color: AnnotationStyle.palette[4], lineWidth: 14, points: [CGPoint(x: 150, y: 150)])
        AnnotationRenderer.draw(step, number: 3, mosaic: nil, imageRect: .zero, in: ctx)
        var text = Annotation(tool: .text, color: .black, lineWidth: 0, points: [CGPoint(x: 20, y: 120)])
        text.text = "你好 Hi"
        AnnotationRenderer.draw(text, number: 0, mosaic: nil, imageRect: .zero, in: ctx)
        AnnotationRenderer.draw(Annotation(tool: .arrow, color: red, lineWidth: 4, points: [CGPoint(x: 100, y: 20), CGPoint(x: 180, y: 90)]),
                                number: 0, mosaic: nil, imageRect: .zero, in: ctx)
        NSGraphicsContext.restoreGraphicsState()
        guard let img = ctx.makeImage() else { return false }
        let px = readPixels(img)
        func at(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * size + x) * 4
            return (Int(px[i]), Int(px[i + 1]), Int(px[i + 2]))
        }
        // 视图坐标 (30, 20)（左上原点）应为红色实心矩形
        let r = at(30, 20)
        let blue = at(150 - 10, 150)   // 序号圆内（避开中心数字）
        let empty = at(5, 190)
        let pass = r.0 > 200 && r.1 < 100 && blue.2 > 200 && empty == (0, 0, 0)
        if !pass { print("   red=\(r) blue=\(blue) empty=\(empty)") }
        if let data = ImageUtil.encode(img, scale: 1, format: .png) {
            try? data.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("screenshotpro-selftest.png"))
        }
        return pass
    }

    private static func makeImage(_ rgba: [UInt8], width: Int, height: Int) -> CGImage {
        let provider = CGDataProvider(data: Data(rgba) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    private static func readPixels(_ image: CGImage) -> [UInt8] {
        var d = [UInt8](repeating: 0, count: image.width * image.height * 4)
        d.withUnsafeMutableBytes { ptr in
            let ctx = CGContext(data: ptr.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return d
    }
}
