import CoreGraphics
import Foundation

/// 把连续截取的滚动画面拼接成一张长图。
///
/// 思路：每帧计算「行签名」（每行缩成 N 个灰度采样），
/// 和上一帧比较找出内容向上移动的行数 dy，把新露出的 dy 行追加到结果中。
/// 顶部 / 底部不随滚动变化的区域（吸顶导航栏、底部工具栏）会被识别出来，只保留一份。
final class ScrollStitcher {
    enum Status: Equatable {
        case first
        case unchanged
        case appended(Int)
        case rejected        // 找不到可靠的重叠（滚动太快或方向不对）
    }

    static let maxHeight = 40_000
    static let columns = 96

    struct Signature {
        let height: Int
        let data: [UInt8]   // height × columns
    }

    private(set) var totalHeight = 0
    private(set) var frameCount = 0

    private var first: CGImage?
    private var last: CGImage?
    private var lastSig: Signature?
    private var slices: [CGImage] = []
    private var header = 0
    private var footer = 0
    private var edgesFixed = false

    func add(_ image: CGImage) -> Status {
        let sig = Self.signature(image)
        guard let prev = lastSig, let prevImage = last else {
            first = image
            last = image
            lastSig = sig
            totalHeight = image.height
            frameCount = 1
            return .first
        }
        guard image.width == prevImage.width, image.height == prevImage.height else { return .rejected }
        let h = sig.height

        // 完全没变化
        if Self.meanDiff(prev, 0, sig, 0, rows: h, step: 2) < 0.6 { return .unchanged }

        var top = header, bottom = footer
        if !edgesFixed {
            top = Self.staticRows(prev, sig, fromTop: true)
            bottom = Self.staticRows(prev, sig, fromTop: false)
            // 大部分没动：可能只是光标闪烁 / 小动画，不算滚动
            if top + bottom > h * 6 / 10 { return .unchanged }
            top = min(top, h * 4 / 10)
            bottom = min(bottom, h * 4 / 10)
        }

        guard let (dy, score) = Self.findOffset(prev, sig, top: top, bottom: bottom) else { return .rejected }
        let content = h - top - bottom
        let stillScore = Self.meanDiff(prev, top, sig, top, rows: content, step: 2)
        if stillScore <= score { return .unchanged }
        if score > 10 { return .rejected }

        if !edgesFixed {
            header = top
            footer = bottom
            edgesFixed = true
        }

        // 新露出的行：新帧中 [h - footer - dy, h - footer)
        guard let slice = Self.copyRows(image, from: h - footer - dy, count: dy) else { return .rejected }
        slices.append(slice)
        last = image
        lastSig = sig
        totalHeight += dy
        frameCount += 1
        return .appended(dy)
    }

    func result() -> CGImage? {
        guard let first, let last else { return nil }
        let w = first.width, h = first.height
        let f = edgesFixed ? footer : 0
        let total = (h - f) + slices.reduce(0) { $0 + $1.height } + f
        guard let ctx = CGContext(data: nil, width: w, height: total, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: first.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                ?? CGContext(data: nil, width: w, height: total, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var y = 0   // 从顶部向下累计
        func put(_ img: CGImage) {
            ctx.draw(img, in: CGRect(x: 0, y: total - y - img.height, width: w, height: img.height))
            y += img.height
        }
        if let head = Self.copyRows(first, from: 0, count: h - f) { put(head) }
        for s in slices { put(s) }
        if f > 0, let foot = Self.copyRows(last, from: h - f, count: f) { put(foot) }
        return ctx.makeImage()
    }

    // MARK: - 算法

    static func signature(_ image: CGImage) -> Signature {
        let h = image.height, cols = columns
        var data = [UInt8](repeating: 0, count: cols * h)
        data.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(data: ptr.baseAddress, width: cols, height: h, bitsPerComponent: 8, bytesPerRow: cols,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: cols, height: h))
        }
        return Signature(height: h, data: data)
    }

    @inline(__always)
    private static func rowDiff(_ a: [UInt8], _ ra: Int, _ b: [UInt8], _ rb: Int) -> Int {
        let cols = columns
        var sum = 0
        let ia = ra * cols, ib = rb * cols
        for c in 0..<cols {
            let d = Int(a[ia + c]) - Int(b[ib + c])
            sum += d < 0 ? -d : d
        }
        return sum
    }

    /// 平均每个采样点的差值（0–255）
    static func meanDiff(_ a: Signature, _ startA: Int, _ b: Signature, _ startB: Int, rows: Int, step: Int) -> Double {
        guard rows > 0 else { return 0 }
        var sum = 0, n = 0
        var r = 0
        while r < rows {
            sum += rowDiff(a.data, startA + r, b.data, startB + r)
            n += 1
            r += step
        }
        return Double(sum) / Double(n * columns)
    }

    /// 从顶部（或底部）开始连续不变的行数
    static func staticRows(_ a: Signature, _ b: Signature, fromTop: Bool) -> Int {
        let h = a.height
        var count = 0
        while count < h {
            let r = fromTop ? count : h - 1 - count
            if rowDiff(a.data, r, b.data, r) > columns * 2 { break }
            count += 1
        }
        return count
    }

    /// 在内容区域内寻找使 new[r] ≈ prev[r + dy] 的最佳 dy
    static func findOffset(_ prev: Signature, _ new: Signature, top: Int, bottom: Int) -> (Int, Double)? {
        let h = prev.height
        let content = h - top - bottom
        let minOverlap = max(12, content / 6)
        guard content - minOverlap >= 1 else { return nil }
        let step = max(1, content / 240)
        var bestDy = 0
        var best = Double.infinity

        for dy in 1...(content - minOverlap) {
            let rows = content - dy
            let samples = (rows + step - 1) / step
            let limit = best.isFinite ? Int(best * Double(samples * columns)) : Int.max
            var sum = 0
            var r = 0
            var aborted = false
            while r < rows {
                sum += rowDiff(new.data, top + r, prev.data, top + r + dy)
                if sum > limit { aborted = true; break }
                r += step
            }
            if aborted { continue }
            let score = Double(sum) / Double(samples * columns)
            if score < best {
                best = score
                bestDy = dy
            }
        }
        return bestDy > 0 ? (bestDy, best) : nil
    }

    /// 复制图像的若干行为独立的小图（避免持有整帧）
    static func copyRows(_ image: CGImage, from row: Int, count: Int) -> CGImage? {
        guard count > 0, row >= 0, row + count <= image.height,
              let crop = image.cropping(to: CGRect(x: 0, y: row, width: image.width, height: count)) else { return nil }
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: image.width, height: count, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return crop }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: image.width, height: count))
        return ctx.makeImage() ?? crop
    }
}
