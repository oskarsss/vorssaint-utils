// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

enum MenuBarOverflowSupport {
    /// Keep unknown system controls visible when macOS adds new identifiers.
    /// Only explicitly selected system keys remove an item from the allowlist.
    static func allowedSystemItems(selection: Set<String>) -> [NSNumber] {
        let hidden = Set(selection.filter { $0.hasPrefix("system:") }
            .compactMap { Int($0.dropFirst(7)) })
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
