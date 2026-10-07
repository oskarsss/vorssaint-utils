// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

enum MenuBarOverflowSupport {
    struct SystemControl: Sendable {
        let id: Int
        let identifier: String
        let name: String
        let symbol: String
        var selectionKey: String { "system:\(id)" }
    }

    // Clock and Control Center remain available as navigation anchors. IDs
    // match MenuBarClientCore's MBSystemItemIdentifier on macOS 27.
    static let systemControls: [SystemControl] = [
        .init(id: 0, identifier: "com.apple.menuextra.battery", name: "Battery", symbol: "battery.100"),
        .init(id: 1, identifier: "com.apple.menuextra.bluetooth", name: "Bluetooth", symbol: "antenna.radiowaves.left.and.right"),
        .init(id: 3, identifier: "com.apple.menuextra.displays", name: "Displays", symbol: "display"),
        .init(id: 4, identifier: "com.apple.menuextra.keyboard", name: "Keyboard", symbol: "keyboard"),
        .init(id: 5, identifier: "com.apple.menuextra.volume", name: "Sound", symbol: "speaker.wave.2"),
        .init(id: 6, identifier: "com.apple.menuextra.wifi", name: "Wi-Fi", symbol: "wifi"),
        .init(id: 7, identifier: "com.apple.menuextra.screen-mirroring", name: "Screen Mirroring", symbol: "rectangle.on.rectangle")
    ]

    static func systemControl(identifier: String?) -> SystemControl? {
        systemControls.first { $0.identifier == identifier }
    }

    static func systemControl(selectionKey: String) -> SystemControl? {
        systemControls.first { $0.selectionKey == selectionKey }
    }

    static func allowedBundles(running: Set<String>, selection: Set<String>, ownBundle: String?) -> [String] {
        var allowed = running.subtracting(selection)
        if let ownBundle { allowed.insert(ownBundle) }
        return allowed.sorted()
    }

    /// Keep unknown system controls visible when macOS adds new identifiers.
    /// Only explicitly selected system keys remove an item from the allowlist.
    static func allowedSystemItems(selection: Set<String>) -> [NSNumber] {
        let hidden = Set(systemControls.filter { selection.contains($0.selectionKey) }.map(\.id))
        return (0...255).filter { !hidden.contains($0) }.map { NSNumber(value: $0) }
    }

    /// Geometry changes when icons hide. Preserve existing chooser rows while
    /// refreshing their data; append new icons and discard departed ones.
    static func stableOrder(previous: [String], current: [String]) -> [String] {
        let present = Set(current)
        var seen = Set<String>()
        return (previous.filter { present.contains($0) } + current).filter { seen.insert($0).inserted }
    }

    struct Item {
        let bundle: String
        let frame: CGRect
    }

    /// Native visibility is per app. An app with any icon in the visible
    /// section stays visible; ambiguous/invalid positions are never hidden.
    static func hiddenBundles(items: [Item], boundaryX: CGFloat, rightToLeft: Bool) -> Set<String> {
        guard boundaryX.isFinite else { return [] }
        return Set(Dictionary(grouping: items, by: \.bundle).compactMap { bundle, items in
            guard !bundle.hasPrefix("com.apple."), items.allSatisfy({ item in
                let frame = item.frame
                guard frame.minX.isFinite, frame.maxX.isFinite, frame.width > 0,
                      frame.height > 0 else { return false }
                return rightToLeft ? frame.minX > boundaryX : frame.maxX < boundaryX
            }) else { return nil }
            return bundle
        })
    }
}
