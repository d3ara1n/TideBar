import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import TideBarCore
import Darwin

/// 后台文件操作：结果先写入同目录临时文件，完成后独占发布，不覆盖源或竞争者文件。
enum TaskTrayWorker {
    struct Outcome: Sendable {
        let url: URL
        let changed: Bool
    }

    struct Failure: Error, Sendable {
        let key: String
    }

    private static let readableImageTypes = Set(CGImageSourceCopyTypeIdentifiers() as! [String])

    static func accepts(_ url: URL, recipe: TaskTrayRecipe) -> Bool {
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]),
              values.isSymbolicLink != true else { return false }
        if recipe.operation == .removeQuarantine {
            return values.isRegularFile == true || values.isDirectory == true
        }
        guard values.isRegularFile == true,
              let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return readableImageTypes.contains(type.identifier)
    }

    static func run(_ url: URL, recipe: TaskTrayRecipe) throws -> Outcome {
        guard accepts(url, recipe: recipe) else { throw Failure(key: "tray.error.unsupported") }
        switch recipe.operation {
        case .jpeg, .png:
            return Outcome(url: try convert(url, recipe: recipe), changed: true)
        case .removeQuarantine:
            return Outcome(url: url, changed: try removeQuarantine(url))
        }
    }

    private static func convert(_ url: URL, recipe: TaskTrayRecipe) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw Failure(key: "tray.error.image")
        }
        // 单图转换不能悄悄丢弃动画帧或多页文档。
        guard CGImageSourceGetCount(source) == 1 else { throw Failure(key: "tray.error.multiframe") }
        guard var image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Failure(key: "tray.error.image")
        }
        let isJPEG = recipe.operation == .jpeg
        if isJPEG {
            // JPEG 没有透明通道，明确以白色铺底。
            guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                throw Failure(key: "tray.error.image")
            }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let flattened = context.makeImage() else { throw Failure(key: "tray.error.image") }
            image = flattened
        }
        let directory = url.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".tidebar-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let type = isJPEG ? UTType.jpeg.identifier : UTType.png.identifier
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, type as CFString, 1, nil) else {
            throw Failure(key: "tray.error.write")
        }
        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]) ?? [:]
        properties[kCGImageDestinationLossyCompressionQuality as String] = Double(min(100, max(1, recipe.jpegQuality))) / 100
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure(key: "tray.error.write") }
        let stem = url.deletingPathExtension().lastPathComponent
        let suffix = isJPEG ? "jpg" : "png"
        var index = 0
        while true {
            let name = index == 0 ? "\(stem).\(suffix)" : "\(stem) (\(index)).\(suffix)"
            let output = directory.appendingPathComponent(name)
            let result = temporary.withUnsafeFileSystemRepresentation { sourcePath in
                output.withUnsafeFileSystemRepresentation { targetPath in
                    renamex_np(sourcePath!, targetPath!, UInt32(RENAME_EXCL))
                }
            }
            if result == 0 { return output }
            let code = errno
            guard code == EEXIST else { throw posixFailure(code, at: output) }
            index += 1
        }
    }

    private static func removeQuarantine(_ url: URL) throws -> Bool {
        var changed = false
        func remove(_ target: URL) throws {
            let result = target.withUnsafeFileSystemRepresentation {
                removexattr($0!, "com.apple.quarantine", XATTR_NOFOLLOW)
            }
            if result == 0 {
                changed = true
            } else {
                let code = errno
                if code != ENOATTR { throw posixFailure(code, at: target) }
            }
        }
        try remove(url)
        if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
            var enumerationError: Error?
            guard let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.isSymbolicLinkKey],
                options: [], errorHandler: { _, error in
                    enumerationError = error
                    return false
                }) else { throw Failure(key: "tray.error.read") }
            for case let child as URL in enumerator {
                // 不跟随链接修改目录树之外的资源。
                if try child.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }
                try remove(child)
            }
            if let enumerationError { throw enumerationError }
        }
        return changed
    }

    private static func posixFailure(_ code: Int32, at url: URL) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: url.path])
    }
}
