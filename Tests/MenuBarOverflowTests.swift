// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum MenuBarOverflowTests {
    static func run(_ suite: TestSuite) {
        let allowed = MenuBarOverflowSupport.allowedSystemItems(selection: ["system:7", "example.app", "system:invalid"])
        suite.expect(allowed.count == 255 && !allowed.contains(NSNumber(value: 7))
                     && allowed.contains(NSNumber(value: 2)) && allowed.contains(NSNumber(value: 255)),
                     "only selected system IDs are hidden; clock and future controls stay visible")
        suite.expect(MenuBarOverflowSupport.allowedSystemItems(selection: []).count == 256,
                     "all system controls remain allowed by default")
        typealias Item = MenuBarOverflowSupport.Item
        func item(_ bundle: String, _ x: CGFloat, _ width: CGFloat = 20) -> Item {
            Item(bundle: bundle, frame: CGRect(x: x, y: 0, width: width, height: 24))
        }
        let items = [item("hidden", 10), item("visible", 200),
                     item("multiple", 20), item("multiple", 210),
                     item("boundary", 90), item("com.apple.controlcenter", 5)]
        suite.expect(MenuBarOverflowSupport.hiddenBundles(items: items, boundaryX: 100, rightToLeft: false) == ["hidden"],
                     "only apps whose every icon is entirely inside the hidden section are hidden")
        suite.expect(MenuBarOverflowSupport.hiddenBundles(items: items, boundaryX: 100, rightToLeft: true) == ["visible"],
                     "right-to-left placement reverses the hidden side while keeping mixed apps visible")
        suite.expect(MenuBarOverflowSupport.hiddenBundles(items: [item("unknown", 10, 0)], boundaryX: 100, rightToLeft: false).isEmpty,
                     "unreadable geometry stays visible")
        suite.expect(MenuBarOverflowSupport.hiddenBundles(items: items, boundaryX: .nan, rightToLeft: false).isEmpty,
                     "an invalid boundary never hides apps")
        suite.expect(MenuBarOverflowSupport.hiddenBundles(items: [], boundaryX: 100, rightToLeft: false).isEmpty,
                     "an empty inventory never restricts the bar")
    }
}
