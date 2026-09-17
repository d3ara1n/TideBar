import AppKit
import SwiftUI

@MainActor
enum BrandAssets {
    static func menuBarImage() -> NSImage? {
        guard let image = load("TideBarTemplate") else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    static func markImage(for colorScheme: ColorScheme) -> NSImage? {
        load(colorScheme == .dark ? "dark" : "light")
    }

    private static func load(_ name: String) -> NSImage? {
        guard let url = AppResources.bundle.url(forResource: name,
                                               withExtension: "pdf") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

struct BrandMark: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let image = BrandAssets.markImage(for: colorScheme) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            }
        }
    }
}
