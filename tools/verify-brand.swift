import Foundation
import CoreGraphics
import ImageIO

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: verify-brand.swift <asset-directory> <bottom-layer,top-layer>")
}
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let layerOrder = CommandLine.arguments[2].split(separator: ",").map(String.init)
func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NSError(domain: "BrandVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
struct Raster {
    let width: Int
    let height: Int
    let bytes: [UInt8]
    init(_ path: String) throws {
        let url = root.appendingPathComponent(path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NSError(domain: "BrandVerification", code: 2)
        }
        width = image.width
        height = image.height
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: width * height * 4))
    }
    func alpha(_ x: Int, _ y: Int) -> UInt8 { bytes[(y * width + x) * 4 + 3] }
}
let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!.allObjects as! [URL]
var pngCount = 0, pdfCount = 0, previewCount = 0
for file in files {
    let relative = String(file.path.dropFirst(root.path.count + 1))
    if file.pathExtension == "png" && relative.hasPrefix("previews/") {
        let raster = try Raster(relative)
        try require(raster.width == 1200 && raster.height == 1200, "Unexpected preview size: \(relative)")
        previewCount += 1
    }
    if file.pathExtension == "png" && !relative.hasPrefix("previews/") {
        let raster = try Raster(relative)
        let expected = relative.contains("@2x") ? 36 : relative.hasPrefix("menubar/") ? 18 : 1024
        try require(raster.width == expected && raster.height == expected, "Unexpected PNG size: \(relative)")
        try require(raster.alpha(0, 0) == 0 && raster.alpha(expected - 1, expected - 1) == 0, "Opaque PNG background: \(relative)")
        try require(stride(from: 3, to: raster.bytes.count, by: 4).contains { raster.bytes[$0] > 0 }, "Empty PNG: \(relative)")
        if relative.hasPrefix("menubar/") {
            try require(stride(from: 0, to: raster.bytes.count, by: 4).allSatisfy {
                raster.bytes[$0] == 0 && raster.bytes[$0 + 1] == 0 && raster.bytes[$0 + 2] == 0
            }, "Template contains color: \(relative)")
        }
        pngCount += 1
    }
    if file.pathExtension == "pdf" {
        guard let document = CGPDFDocument(file as CFURL), let page = document.page(at: 1) else {
            throw NSError(domain: "BrandVerification", code: 3)
        }
        let expected: CGFloat = relative.hasPrefix("menubar/") ? 18 : 256
        try require(document.numberOfPages == 1 && page.getBoxRect(.mediaBox).size == CGSize(width: expected, height: expected), "Unexpected PDF page: \(relative)")
        pdfCount += 1
    }
}
let mono = try Raster("mono/solid.png")
try require(Set(layerOrder) == Set(["waves", "orb"]) && layerOrder.count == 2, "Invalid Composer layer order")
for theme in ["light", "dark"] {
    let full = try Raster("color/\(theme).png")
    let bottom = try Raster("composer/\(theme)/\(layerOrder[0]).png")
    let top = try Raster("composer/\(theme)/\(layerOrder[1]).png")
    for offset in stride(from: 0, to: full.bytes.count, by: 4) {
        try require(full.bytes[offset + 3] == mono.bytes[offset + 3], "Color variant geometry differs from primary mark")
        // 按母版绘制顺序做 source-over；允许抗锯齿与预乘通道舍入误差。
        let remaining = 255 - Int(top.bytes[offset + 3])
        for channel in 0..<4 {
            let composed = Int(top.bytes[offset + channel]) + (Int(bottom.bytes[offset + channel]) * remaining + 127) / 255
            try require(abs(Int(full.bytes[offset + channel]) - composed) <= 2, "Composer layers do not reconstruct the complete mark")
        }
    }
}
try require(pngCount == 12 && pdfCount == 7 && previewCount == 2, "Incomplete export set")
print("Verified \(pngCount) PNGs, \(pdfCount) PDFs and \(previewCount) previews: dimensions, transparent backgrounds, black template, theme geometry and Composer layer reconstruction.")
