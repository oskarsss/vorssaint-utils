import AppKit
import SwiftUI

/// PR-only capture fixture; this file is not part of the proposed app change.
enum NotchGapScreenshots {
    static func capture() {
        MainActor.assumeIsolated {
            let output = URL(fileURLWithPath: "build/notch-gap-screenshots", isDirectory: true)
            try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for enabled in [false, true] {
                let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                             safeAreaTop: 32, cameraWidth: 179, menuBarHeight: 33,
                                             hideMenuBarGap: enabled)
                let renderer = ImageRenderer(content: Scene(geometry: geometry).frame(width: 600, height: 100))
                renderer.scale = 4
                let image = renderer.nsImage!
                let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
                try! bitmap.representation(using: .png, properties: [:])!
                    .write(to: output.appendingPathComponent(enabled ? "gap-hidden.png" : "gap-visible.png"))
            }
        }
    }

    private struct Scene: View {
        let geometry: NotchGeometry
        var body: some View {
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.97, green: 0.95, blue: 0.72),
                                        Color(red: 0.68, green: 0.92, blue: 0.97)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                LinearGradient(colors: [Color(red: 0.29, green: 0.89, blue: 0.91),
                                        Color(red: 0.83, green: 0.98, blue: 0.40)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(height: 33)
                HStack(spacing: 14) {
                    Text("Vorssaint").fontWeight(.semibold)
                    Text("File")
                    Text("Edit")
                    Spacer()
                    Image(systemName: "wifi")
                    Image(systemName: "battery.100percent")
                    Text("16:28")
                }
                .font(.system(size: 12)).foregroundStyle(.black.opacity(0.8))
                .padding(.horizontal, 14).frame(height: 33)
                NotchShape.island(height: geometry.collapsed.height, geometry: geometry)
                    .fill(.black)
                    .frame(width: geometry.collapsed.width, height: geometry.collapsed.height)
            }
        }
    }
}
