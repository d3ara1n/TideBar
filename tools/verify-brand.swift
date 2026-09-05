import Foundation
import CoreGraphics
import ImageIO

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("brand")
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
var pngCount = 0, pdfCount = 0
for file in files {
    let relative = String(file.path.dropFirst(root.path.count + 1))
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
let outline = try Raster("mono/outline.png")
try require(mono.alpha(512, 288) == 255 && outline.alpha(512, 288) == 0, "Orb fill mismatch")
try require(mono.alpha(512, 480) == 0 && mono.alpha(736, 360) == 0, "Wave cutout is not transparent")
for theme in ["light", "dark"] {
    let full = try Raster("color/\(theme).png")
    let waves = try Raster("composer/\(theme)/waves.png")
    let orb = try Raster("composer/\(theme)/orb.png")
    for offset in stride(from: 0, to: full.bytes.count, by: 4) {
        try require(full.bytes[offset + 3] == mono.bytes[offset + 3], "Color variant geometry differs from primary mark")
        try require(waves.bytes[offset + 3] == 0 || orb.bytes[offset + 3] == 0, "Composer layers overlap")
        for channel in 0..<4 {
            try require(Int(full.bytes[offset + channel]) == Int(waves.bytes[offset + channel]) + Int(orb.bytes[offset + channel]), "Composer layers do not reconstruct the complete mark")
        }
    }
}
try require(pngCount == 12 && pdfCount == 7, "Incomplete export set")
print("Verified \(pngCount) PNGs and \(pdfCount) PDFs: dimensions, transparent backgrounds/cutouts, monochrome template, theme geometry, and exact Composer layer reconstruction.")
