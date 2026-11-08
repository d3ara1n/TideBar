import AppKit

/// 图层只持有显示尺寸的位图；原始图标的表示尺寸不决定常驻图形内存预算。
@MainActor
enum IconRaster {
    static let maximumPixelSide = 512

    static func makeImage(_ image: NSImage, side: CGFloat, scale: CGFloat) -> CGImage? {
        guard side.isFinite, side > 0, scale.isFinite, scale > 0 else { return nil }
        let pixels = Int(min(CGFloat(maximumPixelSide), ceil(side * min(scale, 4))))
        guard pixels > 0, let context = makeContext(pixels: pixels) else { return nil }
        return autoreleasepool {
            context.scaleBy(x: CGFloat(pixels) / side, y: CGFloat(pixels) / side)
            context.interpolationQuality = .high
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            let size = image.size
            guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
            let ratio = min(side / size.width, side / size.height)
            let width = size.width * ratio, height = size.height * ratio
            image.draw(in: NSRect(x: (side - width) / 2, y: (side - height) / 2,
                                  width: width, height: height),
                       from: .zero, operation: .copy, fraction: 1,
                       respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
            return context.makeImage()
        }
    }

    static func tint(_ image: CGImage, color: NSColor) -> CGImage? {
        guard image.width == image.height, image.width <= maximumPixelSide,
              let context = makeContext(pixels: image.width) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(image, in: rect)
        context.setBlendMode(.sourceAtop)
        context.setFillColor(color.cgColor)
        context.fill(rect)
        return context.makeImage()
    }

    private static func makeContext(pixels: Int) -> CGContext? {
        CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                  bytesPerRow: pixels * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}
