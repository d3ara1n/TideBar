// 品牌几何与导出入口；仅使用系统框架，不依赖应用运行。
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct Ink {
    let hex: String
    var cg: CGColor {
        let value = UInt32(hex, radix: 16)!
        return CGColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}
struct Curve {
    let c1: CGPoint
    let c2: CGPoint
    let end: CGPoint
}
struct Wave {
    let start: CGPoint
    let curves: [Curve]
    init(y: CGFloat) {
        start = CGPoint(x: 24, y: y)
        curves = [
            Curve(c1: CGPoint(x: 46, y: y), c2: CGPoint(x: 54, y: y - 20), end: CGPoint(x: 76, y: y - 20)),
            Curve(c1: CGPoint(x: 98, y: y - 20), c2: CGPoint(x: 106, y: y), end: CGPoint(x: 128, y: y)),
            Curve(c1: CGPoint(x: 150, y: y), c2: CGPoint(x: 158, y: y - 20), end: CGPoint(x: 180, y: y - 20)),
            Curve(c1: CGPoint(x: 202, y: y - 20), c2: CGPoint(x: 210, y: y), end: CGPoint(x: 232, y: y)),
        ]
    }
    var path: CGPath {
        let path = CGMutablePath()
        path.move(to: start)
        for curve in curves { path.addCurve(to: curve.end, control1: curve.c1, control2: curve.c2) }
        return path
    }
    var svg: String {
        "M\(point(start))" + curves.map { "C\(point($0.c1)) \(point($0.c2)) \(point($0.end))" }.joined()
    }
}
func n(_ value: CGFloat) -> String { String(format: "%g", Double(value)) }
func point(_ value: CGPoint) -> String { "\(n(value.x)) \(n(value.y))" }

enum Layer { case all, waves, orb }
struct Mark {
    var waveInk = Ink(hex: "000000")
    var orbInk = Ink(hex: "000000")
    var outline = false
    var template = false
    var layer = Layer.all
    var currentColor = false
    var box: CGRect { template ? CGRect(x: 12, y: -2, width: 232, height: 232) : CGRect(x: 0, y: 0, width: 256, height: 256) }
    var lineWidth: CGFloat { template ? 16 : 12 }
    var orbRadius: CGFloat { template ? 42 : 40 }
    var haloRadius: CGFloat { template ? 62 : 60 }
    let waves = [Wave(y: 100), Wave(y: 144), Wave(y: 188)]
    func circle(_ radius: CGFloat) -> CGRect { CGRect(x: 128 - radius, y: 72 - radius, width: radius * 2, height: radius * 2) }

    func svg(size: Int, id: String) -> String {
        let waveColor = currentColor ? "currentColor" : "#\(waveInk.hex)"
        let orbColor = currentColor ? "currentColor" : "#\(orbInk.hex)"
        var body = ""
        if layer != .orb {
            let r = n(haloRadius), diameter = n(haloRadius * 2)
            body += """
            <defs><clipPath id="\(id)"><path clip-rule="evenodd" d="M0 0H256V256H0Z M\(n(128 + haloRadius)) 72a\(r) \(r) 0 1 0-\(diameter) 0a\(r) \(r) 0 1 0 \(diameter) 0Z"/></clipPath></defs>
            <g fill="none" stroke="\(waveColor)" stroke-width="\(n(lineWidth))" stroke-linecap="round">
            """
            for (index, wave) in waves.enumerated() {
                body += "<path d=\"\(wave.svg)\"\(index == 0 ? " clip-path=\"url(#\(id))\"" : "")/>\n"
            }
            body += "</g>\n"
        }
        if layer != .waves {
            body += outline
                ? "<circle cx=\"128\" cy=\"72\" r=\"\(n(orbRadius - 5))\" fill=\"none\" stroke=\"\(orbColor)\" stroke-width=\"10\"/>"
                : "<circle cx=\"128\" cy=\"72\" r=\"\(n(orbRadius))\" fill=\"\(orbColor)\"/>"
        }
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(size)" height="\(size)" viewBox="\(n(box.minX)) \(n(box.minY)) \(n(box.width)) \(n(box.height))" fill="none">
        <title>TideBar\(template ? " Menu Bar Template" : outline ? " — Outline Orb" : " — Solid Orb")</title>
        \(body)
        </svg>

        """
    }
    func draw(in context: CGContext, size: CGFloat) {
        context.saveGState()
        // 使用与 SVG 一致的向下 Y 轴与同一份曲线控制点。
        context.translateBy(x: 0, y: size)
        context.scaleBy(x: size / box.width, y: -size / box.height)
        context.translateBy(x: -box.minX, y: -box.minY)
        if layer != .orb {
            context.setStrokeColor(waveInk.cg)
            context.setLineWidth(lineWidth)
            context.setLineCap(.round)
            for (index, wave) in waves.enumerated() {
                context.saveGState()
                if index == 0 {
                    context.addRect(CGRect(x: 0, y: 0, width: 256, height: 256))
                    context.addEllipse(in: circle(haloRadius))
                    context.clip(using: .evenOdd)
                }
                context.addPath(wave.path)
                context.strokePath()
                context.restoreGState()
            }
        }
        if layer != .waves {
            if outline {
                context.setStrokeColor(orbInk.cg)
                context.setLineWidth(10)
                context.strokeEllipse(in: circle(orbRadius - 5))
            } else {
                context.setFillColor(orbInk.cg)
                context.fillEllipse(in: circle(orbRadius))
            }
        }
        context.restoreGState()
    }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("brand")
func url(_ path: String) throws -> URL {
    let result = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: result.deletingLastPathComponent(), withIntermediateDirectories: true)
    return result
}
func png(_ mark: Mark, path: String, pixels: Int) throws {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                  bytesPerRow: pixels * 4, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw NSError(domain: "BrandExport", code: 1)
    }
    context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    mark.draw(in: context, size: CGFloat(pixels))
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(try url(path) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "BrandExport", code: 2)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "BrandExport", code: 3) }
}
func pdf(_ mark: Mark, path: String, points: Int) throws {
    var box = CGRect(x: 0, y: 0, width: points, height: points)
    guard let context = CGContext(try url(path) as CFURL, mediaBox: &box, [kCGPDFContextTitle: "TideBar"] as CFDictionary) else {
        throw NSError(domain: "BrandExport", code: 4)
    }
    context.beginPDFPage(nil)
    mark.draw(in: context, size: CGFloat(points))
    context.endPDFPage()
    context.closePDF()
}
func export(_ mark: Mark, stem: String, size: Int = 1024, includePDF: Bool = true) throws {
    try mark.svg(size: size, id: stem.replacingOccurrences(of: "/", with: "-") + "-water")
        .write(to: url(stem + ".svg"), atomically: true, encoding: .utf8)
    try png(mark, path: stem + ".png", pixels: size)
    if includePDF { try pdf(mark, path: stem + ".pdf", points: mark.template ? 18 : 256) }
}

for outline in [false, true] {
    let name = outline ? "outline" : "solid"
    for white in [false, true] {
        var mark = Mark()
        mark.outline = outline
        mark.currentColor = !white
        mark.waveInk = Ink(hex: white ? "FFFFFF" : "000000")
        mark.orbInk = mark.waveInk
        try export(mark, stem: "mono/\(name)\(white ? "-white" : "")")
    }
}
for dark in [false, true] {
    let theme = dark ? "dark" : "light"
    var mark = Mark()
    mark.waveInk = Ink(hex: dark ? "65CADD" : "167D9A")
    mark.orbInk = Ink(hex: dark ? "F5D69A" : "F2AE49")
    try export(mark, stem: "color/\(theme)")
    for layer in [Layer.waves, Layer.orb] {
        mark.layer = layer
        try export(mark, stem: "composer/\(theme)/\(layer == .waves ? "waves" : "orb")", includePDF: false)
    }
}
var template = Mark()
template.template = true
try export(template, stem: "menubar/TideBarTemplate", size: 18)
try png(template, path: "menubar/TideBarTemplate@2x.png", pixels: 36)
print("Exported SVG, transparent sRGB PNG, and vector PDF assets to brand/.")
