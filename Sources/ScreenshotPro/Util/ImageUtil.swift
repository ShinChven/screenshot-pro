import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum ImageUtil {
    static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// 生成整张截图的马赛克版本（用于马赛克标注）
    static func pixelated(_ image: CGImage, pointSize: CGSize, scale: CGFloat, block: CGFloat = 9) -> NSImage? {
        let input = CIImage(cgImage: image)
        let filter = CIFilter.pixellate()
        filter.inputImage = input.clampedToExtent()
        filter.scale = Float(block * scale)
        filter.center = .zero
        guard let output = filter.outputImage?.cropped(to: input.extent),
              let cg = ciContext.createCGImage(output, from: input.extent) else { return nil }
        return NSImage(cgImage: cg, size: pointSize)
    }

    static func resize(_ image: CGImage, factor: CGFloat) -> CGImage? {
        let w = max(1, Int((CGFloat(image.width) * factor).rounded()))
        let h = max(1, Int((CGFloat(image.height) * factor).rounded()))
        guard let ctx = makeContext(width: w, height: h, colorSpace: image.colorSpace) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    static func makeContext(width: Int, height: Int, colorSpace: CGColorSpace? = nil) -> CGContext? {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let space = (colorSpace?.model == .rgb) ? colorSpace! : srgb
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ?? CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    static func encode(_ image: CGImage, scale: CGFloat, format: ImageFormat) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        switch format {
        case .png: return rep.representation(using: .png, properties: [:])
        case .jpg: return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        }
    }

    static func nsImage(_ image: CGImage, scale: CGFloat) -> NSImage {
        NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale))
    }
}

/// 截图的 RGBA 像素副本，用于放大镜取色
final class PixelBuffer {
    let width: Int
    let height: Int
    private var data: [UInt8]

    init?(image: CGImage) {
        width = image.width
        height = image.height
        data = [UInt8](repeating: 0, count: width * height * 4)
        let ok = data.withUnsafeMutableBytes { ptr -> Bool in
            guard let ctx = CGContext(data: ptr.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        if !ok { return nil }
    }

    /// (x, y) 为左上角原点的像素坐标
    func rgb(x: Int, y: Int) -> (r: Int, g: Int, b: Int)? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let i = (y * width + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    func hex(x: Int, y: Int) -> String? {
        guard let c = rgb(x: x, y: y) else { return nil }
        return String(format: "#%02X%02X%02X", c.r, c.g, c.b)
    }
}
