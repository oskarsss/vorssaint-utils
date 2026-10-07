// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import SwiftUI
import MenuBarVisibilityBridge

/// One Shelf button and one shelf of less-used status icons. On macOS 27
/// native visibility removes the originals while AXPress opens their menus.
final class MenuBarOverflowController: NSObject, ObservableObject {
    static let shared = MenuBarOverflowController()
    var onChooseIcons: (() -> Void)?
    @Published var isChoosingIcons = false
    struct ShelfItem: Identifiable {
        let id: String
        let bundle: String
        let name: String
        let icon: NSImage
        let element: AXUIElement
        let frame: CGRect
    }
    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var availableItems: [ShelfItem] = []
    @Published private(set) var isCollapsed = false
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    private var toggleItem: NSStatusItem?
    private var spacerItem: NSStatusItem?
    private var shelf: MenuBarShelfPanel?
    private var shelfLocalMonitor: Any?
    private var shelfGlobalMonitor: Any?
    private var lastClickPoint: CGPoint?
    private var arrowAXFrame = CGRect.zero
    private var systemCache: [String: Record] = [:]
    private var systemMenuTimer: Timer?
    private var wantsShelfVisible = false
    private var assertion: Any?
    private var generation = 0
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var syncScheduled = false
    private var started = false
    private var requestedPermission = false
    private var isArranging = false
    private var lastSelection: Set<String> = []
    private var configuredBundles: Set<String> {
        Set(UserDefaults.standard.string(forKey: DefaultsKey.menuBarOverflowBundles)?
            .split(separator: ",").map(String.init) ?? [])
    }
    private var usesNativeVisibility: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    }

    func start() {
        guard !started else { return }
        started = true
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, !self.syncScheduled else { return }
            self.syncScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.syncScheduled = false
                self?.syncEnabled()
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.closeShelf()
            if self.usesNativeVisibility, !self.isArranging, !self.configuredBundles.isEmpty {
                self.collectAndHide(useSavedSelection: true, openShelf: false)
            } else { self.arrangeIcons() }
        })
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self, self.toggleItem != nil, !self.isArranging,
                      !self.configuredBundles.isEmpty else { return }
                self.collectAndHide(useSavedSelection: true, openShelf: false)
            })
        }
        syncEnabled()
    }

    private func syncEnabled() {
        if UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOverflowEnabled) {
            if toggleItem != nil {
                let selection = configuredBundles
                guard selection != lastSelection else { return }
                lastSelection = selection
                if selection.isEmpty { stopHiding(); items = [] }
                else { collectAndHide(useSavedSelection: true, openShelf: false) }
                return
            }
            lastSelection = configuredBundles
            isArranging = false
            let placement = UserDefaults.standard.integer(forKey: DefaultsKey.menuBarOverflowPlacementGeneration)
            let identity = "VorssaintOverflowToggle" + (placement == 0 ? "" : ".\(placement)")
            let positionKey = "NSStatusItem Preferred Position " + identity
            // A first-time overflow control belongs next to the right-side system
            // controls, where the camera notch cannot swallow it. Later launches
            // preserve the position the user arranged.
            if UserDefaults.standard.object(forKey: positionKey) == nil {
                UserDefaults.standard.set(0, forKey: positionKey)
            }
            let item = NSStatusBar.system.statusItem(withLength: 26)
            item.autosaveName = identity
            item.behavior = []
            item.isVisible = true
            toggleItem = item
            if !usesNativeVisibility {
                let spacer = NSStatusBar.system.statusItem(withLength: 18)
                spacer.autosaveName = "VorssaintOverflowBoundary"
                spacer.behavior = []
                spacer.button?.title = "│"
                spacer.button?.toolTip = "Command-drag less-used icons to the left of this divider."
                spacerItem = spacer
            }
            item.button?.target = self
            item.button?.action = #selector(clicked)
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            message = nil
            updateButton()
            if !configuredBundles.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    guard let self, self.toggleItem != nil, !self.isArranging else { return }
                    self.collectAndHide(useSavedSelection: true, openShelf: false)
                }
            }
        } else if toggleItem != nil {
            stopHiding()
            if let item = toggleItem { NSStatusBar.system.removeStatusItem(item) }
            if let item = spacerItem { NSStatusBar.system.removeStatusItem(item) }
            toggleItem = nil
            spacerItem = nil
            items = []
            isArranging = false
            message = nil
        }
    }

    @objc private func clicked() {
        lastClickPoint = NSEvent.mouseLocation
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let open = menu.addItem(withTitle: "Open Shelf", action: #selector(showShelf), keyEquivalent: "")
            open.target = self
            menu.addItem(.separator())
            let arrange = menu.addItem(withTitle: "Arrange icons…", action: #selector(arrangeIcons), keyEquivalent: "")
            arrange.target = self
            let save = menu.addItem(withTitle: "Move icons on the left into Shelf", action: #selector(saveArrangement), keyEquivalent: "")
            save.target = self
            save.isEnabled = !isCollapsed && !isBusy
            menu.addItem(.separator())
            let disable = menu.addItem(withTitle: "Turn off Shelf", action: #selector(disable), keyEquivalent: "")
            disable.target = self
            // Explicitly disabled setup actions must stay disabled.
            menu.autoenablesItems = false
            toggleItem?.menu = menu
            toggleItem?.button?.performClick(nil)
            toggleItem?.menu = nil
        } else { showShelf() }
    }

    @objc private func disable() {
        UserDefaults.standard.set(false, forKey: DefaultsKey.menuBarOverflowEnabled)
        syncEnabled()
    }

    func loadAvailableIcons() {
        collectAndHide(useSavedSelection: true, openShelf: false)
    }

    func setInShelf(_ bundle: String, included: Bool) {
        var selection = configuredBundles
        if included { selection.insert(bundle) } else { selection.remove(bundle) }
        UserDefaults.standard.set(selection.sorted().joined(separator: ","),
                                  forKey: DefaultsKey.menuBarOverflowBundles)
    }

    func chooseIcons() {
        closeShelf()
        isChoosingIcons = true
        onChooseIcons?()
    }

    @objc func showShelf() {
        if shelf?.isVisible == true { closeShelf(); return }
        wantsShelfVisible = true
        presentShelf()
        if !isCollapsed && !isBusy {
            collectAndHide(useSavedSelection: !isArranging, openShelf: true)
        }
    }

    @objc func arrangeIcons() {
        stopHiding()
        isArranging = true
        message = usesNativeVisibility
            ? "Hold ⌘ and drag the icons you want in Shelf to the left of its arrow. Then choose Move icons into Shelf."
            : "Hold ⌘ and drag icons to the left of the divider, and keep the divider left of the Shelf arrow. Then choose Move icons into Shelf."
    }

    func restoreArrow() {
        stopHiding()
        if let item = toggleItem { NSStatusBar.system.removeStatusItem(item) }
        if let item = spacerItem { NSStatusBar.system.removeStatusItem(item) }
        toggleItem = nil
        spacerItem = nil
        let placement = UserDefaults.standard.integer(forKey: DefaultsKey.menuBarOverflowPlacementGeneration)
        UserDefaults.standard.set(placement + 1, forKey: DefaultsKey.menuBarOverflowPlacementGeneration)
        syncEnabled()
    }

    @objc func saveArrangement() {
        collectAndHide(useSavedSelection: false, openShelf: false)
    }

    func stopHiding() {
        systemMenuTimer?.invalidate()
        systemMenuTimer = nil
        generation += 1
        closeShelf()
        if let assertion { VSMenuBarVisibilityRelease(assertion) }
        assertion = nil
        spacerItem?.length = 18
        isCollapsed = false
        isBusy = false
        updateButton()
    }

    private func collectAndHide(useSavedSelection: Bool, openShelf: Bool) {
        systemMenuTimer?.invalidate()
        systemMenuTimer = nil
        guard toggleItem != nil else { return }
        let windowFrame = toggleItem?.button?.window?.frame ?? .zero
        guard AXIsProcessTrusted() else {
            message = "Allow Vorssaint in System Settings → Privacy & Security → Accessibility, then click Shelf again."
            if !requestedPermission {
                requestedPermission = true
                _ = AXIsProcessTrustedWithOptions([
                    kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
                ] as CFDictionary)
            }
            presentShelf()
            return
        }
        if usesNativeVisibility, !VSMenuBarVisibilityAvailable() {
            message = "Menu bar hiding is unavailable on this macOS version. All icons remain visible."
            presentShelf()
            return
        }
        if !usesNativeVisibility {
            guard let divider = spacerItem?.button?.window?.frame, divider.maxX <= windowFrame.minX else {
                message = "Command-drag the divider to the left of the Shelf arrow first."
                presentShelf()
                return
            }
        }
        message = nil
        isBusy = true
        generation += 1
        let request = generation
        let boundary = spacerItem?.button?.window?.frame.midX ?? windowFrame.midX
        let rtl = NSApp.userInterfaceLayoutDirection == .rightToLeft
        let saved = configuredBundles
        let ownBundle = Bundle.main.bundleIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let native = usesNativeVisibility
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleURL?.pathExtension == "app" && $0.bundleIdentifier != nil
                && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        var descriptors = apps.map { ($0.processIdentifier, $0.bundleIdentifier!, $0.localizedName ?? $0.bundleIdentifier!) }
        if let agent = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.MenuBarAgent" || $0.localizedName == "MenuBarAgent"
        }) {
            descriptors.append((agent.processIdentifier, "com.apple.MenuBarAgent", "System"))
        }
        let appIcons = Dictionary(apps.compactMap { app -> (String, NSImage)? in
            guard let bundle = app.bundleIdentifier, let icon = app.icon else { return nil }
            return (bundle, icon)
        }, uniquingKeysWith: { first, _ in first })
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scannedInventory = MenuBarOverflowController.readInventory(descriptors)
            let ownItems = MenuBarOverflowController.readInventory([(ownPID, ownBundle ?? "", "Vorssaint")])
            let actualBoundary = native ? (ownItems.first { $0.identifier == "vorssaint.menu-bar-shelf" }?.frame.midX ?? boundary) : boundary
            let hidden = useSavedSelection ? saved : MenuBarOverflowSupport.hiddenBundles(
                items: scannedInventory.map { .init(bundle: $0.bundle, frame: $0.frame) },
                boundaryX: actualBoundary, rightToLeft: rtl)
            var allowed = Set(descriptors.map { $0.1 }).subtracting(hidden)
            if let ownBundle { allowed.insert(ownBundle) }
            DispatchQueue.main.async { [weak self] in
                guard let self, request == self.generation else { return }
                self.arrowAXFrame = ownItems.first { $0.identifier == "vorssaint.menu-bar-shelf" }?.frame ?? .zero
                for record in scannedInventory where record.bundle.hasPrefix("system:") {
                    self.systemCache[record.bundle] = record
                }
                let inventory = scannedInventory.filter { !$0.bundle.hasPrefix("system:") }
                    + self.systemCache.values.sorted { $0.name < $1.name }
                self.availableItems = inventory.map { record in
                    ShelfItem(id: record.id, bundle: record.bundle, name: record.name,
                              icon: appIcons[record.bundle] ?? NSImage(systemSymbolName: Self.systemSymbols[record.bundle] ?? "app", accessibilityDescription: nil)!,
                              element: record.element, frame: record.frame)
                }
                self.items = self.availableItems.filter { hidden.contains($0.bundle) }
                self.isArranging = false
                if !useSavedSelection {
                    self.lastSelection = hidden
                    UserDefaults.standard.set(hidden.sorted().joined(separator: ","), forKey: DefaultsKey.menuBarOverflowBundles)
                }
                guard !hidden.isEmpty else {
                    let reopen = openShelf && self.wantsShelfVisible
                    self.stopHiding()
                    self.wantsShelfVisible = reopen
                    self.message = "Shelf is empty. Open Settings → Menu bar → Choose icons and select the icons you want here."
                    if openShelf && self.wantsShelfVisible { self.presentShelf() }
                    return
                }
                if !self.usesNativeVisibility {
                    self.spacerItem?.length = min(10_000, max(500, (NSScreen.screens.map { $0.frame.width }.max() ?? 2000) * 2))
                    self.isBusy = false
                    self.isCollapsed = true
                    self.updateButton()
                    if openShelf && self.wantsShelfVisible { self.presentShelf() }
                    return
                }
                VSMenuBarVisibilityActivate(Array(allowed), MenuBarOverflowSupport.allowedSystemItems(selection: hidden)) { [weak self] handle, error in
                    guard let self, request == self.generation else {
                        if let handle { VSMenuBarVisibilityRelease(handle) }
                        return
                    }
                    self.isBusy = false
                    if let handle {
                        let previous = self.assertion
                        self.assertion = handle
                        if let previous { VSMenuBarVisibilityRelease(previous) }
                        self.isCollapsed = true
                    } else {
                        let reopen = openShelf && self.wantsShelfVisible
                        self.stopHiding()
                        self.wantsShelfVisible = reopen
                        self.message = error?.localizedDescription ?? "Could not move icons into Shelf."
                    }
                    self.updateButton()
                    if openShelf && self.wantsShelfVisible { self.presentShelf() }
                }
            }
        }
    }

    private func presentShelf() {
        guard toggleItem != nil else { return }
        let columns = items.count > 9 ? 4 : 3
        let width = CGFloat(columns) * 64 + 32
        let rows = max(1, Int(ceil(Double(items.count) / Double(columns))))
        let height = min(360, max(150, CGFloat(rows) * 64 + (message == nil && !items.isEmpty && AXIsProcessTrusted() ? 76 : 156)))
        let point = lastClickPoint
        let screen = point.flatMap { point in NSScreen.screens.first { $0.frame.contains(point) } }
            ?? toggleItem?.button?.window?.screen ?? NSScreen.main
        guard let screen else { return }
        let reported = toggleItem?.button?.window?.frame ?? .zero
        let x = point?.x ?? (StatusItemAnchorSupport.isTrustworthyStatusFrame(reported)
            ? reported.midX : screen.visibleFrame.maxX - 120)
        // The dropdown belongs below both the menu bar and the camera housing,
        // including when the menu bar is configured to auto-hide.
        let top = min(screen.visibleFrame.maxY,
                      screen.frame.maxY - max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)) - 6
        let frame = StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: width, height: height),
            anchorMidX: x, anchorTop: top, visibleFrame: screen.visibleFrame)
        let panel: MenuBarShelfPanel
        if let shelf { panel = shelf }
        else {
            panel = MenuBarShelfPanel(contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Shelf"
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .popUpMenu
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: frame.size))
            background.material = .popover
            background.blendingMode = .behindWindow
            background.state = .active
            background.wantsLayer = true
            background.layer?.cornerRadius = 12
            background.layer?.masksToBounds = true
            let hosting = NSHostingView(rootView: MenuBarOverflowShelf(controller: self))
            hosting.frame = background.bounds
            hosting.autoresizingMask = [.width, .height]
            background.addSubview(hosting)
            panel.contentView = background
            shelf = panel
        }
        panel.appearance = NSApp.appearance
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        installShelfMonitors()
    }

    private func installShelfMonitors() {
        guard shelfLocalMonitor == nil else { return }
        shelfLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.closeShelf()
                return nil
            }
            if event.type != .keyDown, self.shelf?.frame.contains(NSEvent.mouseLocation) != true {
                // Let the arrow's own mouse-up toggle the dropdown once.
                if event.window !== self.toggleItem?.button?.window { self.closeShelf() }
            }
            return event
        }
        shelfGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            let point = NSEvent.mouseLocation
            // On macOS 27 the menu bar belongs to MenuBarAgent, so our arrow's
            // mouse-down is a global event. Leave its mouse-up to toggle once.
            let screen = NSScreen.screens.first { $0.frame.contains(point) }
            let inBar = screen.map { point.y >= $0.frame.maxY - max(33, $0.safeAreaInsets.top) } ?? false
            let anchorX = self.lastClickPoint?.x ?? self.arrowAXFrame.midX
            if inBar && abs(point.x - anchorX) < 24 { return }
            self.closeShelf()
        }
    }

    private func closeShelf() {
        wantsShelfVisible = false
        shelf?.orderOut(nil)
        if let shelfLocalMonitor { NSEvent.removeMonitor(shelfLocalMonitor) }
        if let shelfGlobalMonitor { NSEvent.removeMonitor(shelfGlobalMonitor) }
        shelfLocalMonitor = nil
        shelfGlobalMonitor = nil
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func open(_ item: ShelfItem) {
        closeShelf()
        if item.bundle.hasPrefix("system:"), usesNativeVisibility {
            openSystemMenu(item)
            return
        }
        // Let the transient shelf relinquish focus before the other app opens
        // its native status menu. No synthetic pointer events or app launches.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let result = AXUIElementPerformAction(item.element, kAXPressAction as CFString)
                DispatchQueue.main.async { [weak self] in
                    // Some status menus enter a tracking loop before replying to AXPress.
                    // cannotComplete can mean that the menu opened, so never dismiss
                    // it or reveal the whole bar in response to that timeout.
                    guard let self, result != .success, result != .cannotComplete else { return }
                    self.stopHiding()
                    self.message = "\(item.name) could not open its menu from Shelf. Its original icon is visible again; click it in the menu bar."
                }
            }
        }
    }

    private func openSystemMenu(_ item: ShelfItem) {
        systemMenuTimer?.invalidate()
        generation += 1
        let request = generation
        let selection = configuredBundles.subtracting([item.bundle])
        var allowed = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
            .subtracting(selection)
        if let own = Bundle.main.bundleIdentifier { allowed.insert(own) }
        VSMenuBarVisibilityActivate(Array(allowed), MenuBarOverflowSupport.allowedSystemItems(selection: selection)) { [weak self] handle, error in
            guard let self, request == self.generation else {
                if let handle { VSMenuBarVisibilityRelease(handle) }
                return
            }
            guard let handle else {
                self.message = error?.localizedDescription ?? "Could not open \(item.name)."
                return
            }
            let previous = self.assertion
            self.assertion = handle
            if let previous { VSMenuBarVisibilityRelease(previous) }
            let agents = NSWorkspace.shared.runningApplications.filter {
                $0.bundleIdentifier == "com.apple.MenuBarAgent" || $0.localizedName == "MenuBarAgent"
            }.map { ($0.processIdentifier, "com.apple.MenuBarAgent", "System") }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.25) { [weak self] in
                let fresh = Self.readInventory(agents).first { $0.bundle == item.bundle }
                let result = fresh.map { AXUIElementPerformAction($0.element, kAXPressAction as CFString) } ?? .invalidUIElement
                DispatchQueue.main.async { [weak self] in
                    guard let self, request == self.generation else { return }
                    if result != .success && result != .cannotComplete {
                        self.collectAndHide(useSavedSelection: true, openShelf: false)
                        self.message = "Could not open \(item.name). Try again from Shelf."
                    } else { self.waitForSystemMenuToClose(request: request) }
                }
            }
        }
    }

    private func waitForSystemMenuToClose(request: Int) {
        let owners = Set(NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier?.hasPrefix("com.apple.controlcenter") == true || $0.bundleIdentifier == "com.apple.MenuBarAgent"
        }.map { $0.processIdentifier })
        var sawMenu = false
        let started = Date()
        systemMenuTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            guard let self, request == self.generation else { timer.invalidate(); return }
            let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
            let visible = windows.contains { window in
                guard let pid = window[kCGWindowOwnerPID as String] as? Int32, owners.contains(pid),
                      let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                      let width = bounds["Width"], let height = bounds["Height"] else { return false }
                return height > 60 && width > 100 && width < 800
            }
            sawMenu = sawMenu || visible
            if (!visible && sawMenu) || (!sawMenu && Date().timeIntervalSince(started) > 3) {
                timer.invalidate()
                self.systemMenuTimer = nil
                self.collectAndHide(useSavedSelection: true, openShelf: false)
            }
        }
    }

    private func updateButton() {
        toggleItem?.button?.image = NSImage(systemSymbolName: "chevron.down",
                                            accessibilityDescription: "Shelf menu bar icons")
        toggleItem?.button?.toolTip = "Shelf — open the icon shelf. Right-click to arrange icons."
        toggleItem?.button?.setAccessibilityLabel("Shelf menu bar icons")
        toggleItem?.button?.setAccessibilityIdentifier("vorssaint.menu-bar-shelf")
    }

    private struct Record {
        let identifier: String?
        let id: String
        let bundle: String
        let name: String
        let element: AXUIElement
        let frame: CGRect
    }

    private static let systemIdentifiers: [String: (Int, String)] = [
        "com.apple.menuextra.battery": (0, "Battery"),
        "com.apple.menuextra.bluetooth": (1, "Bluetooth"),
        "com.apple.menuextra.displays": (3, "Displays"),
        "com.apple.menuextra.keyboard": (4, "Keyboard"),
        "com.apple.menuextra.volume": (5, "Sound"),
        "com.apple.menuextra.wifi": (6, "Wi-Fi"),
        "com.apple.menuextra.screen-mirroring": (7, "Screen Mirroring")
    ]
    private static let systemSymbols = ["system:0": "battery.100", "system:1": "antenna.radiowaves.left.and.right",
        "system:3": "display", "system:4": "keyboard", "system:5": "speaker.wave.2",
        "system:6": "wifi", "system:7": "rectangle.on.rectangle"]

    private static func menuElements(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 4 else { return [] }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        if role as? String == kAXMenuBarItemRole as String { return [element] }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        return (children as? [AXUIElement] ?? []).flatMap { menuElements($0, depth: depth + 1) }
    }

    private static func readInventory(_ apps: [(pid_t, String, String)]) -> [Record] {
        var records: [Record] = []
        for (pid, bundle, appName) in apps {
            let system = bundle == "com.apple.MenuBarAgent"
            guard system || !bundle.hasPrefix("com.apple.") else { continue }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.1)
            var bar: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &bar) == .success,
                  let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { continue }
            var children: CFTypeRef?
            guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
                  let elements = children as? [AXUIElement] else { continue }
            let candidates = system ? elements.flatMap { menuElements($0) } : elements
            for (index, element) in candidates.enumerated() {
                var position: CFTypeRef?
                var size: CFTypeRef?
                var identifier: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifier)
                let systemInfo = (identifier as? String).flatMap { systemIdentifiers[$0] }
                if system && systemInfo == nil { continue }
                let recordBundle = systemInfo.map { "system:\($0.0)" } ?? bundle
                let name = systemInfo?.1 ?? appName
                var frame = CGRect.zero
                if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
                   AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
                   let position, let size,
                   CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
                    var point = CGPoint.zero
                    var dimensions = CGSize.zero
                    if AXValueGetValue(position as! AXValue, .cgPoint, &point),
                       AXValueGetValue(size as! AXValue, .cgSize, &dimensions) {
                        frame = CGRect(origin: point, size: dimensions)
                    }
                }
                records.append(.init(identifier: identifier as? String, id: "\(recordBundle):\(pid):\(index)", bundle: recordBundle, name: name, element: element, frame: frame))
            }
        }
        return records.sorted { $0.frame.minX < $1.frame.minX }
    }
}

private final class MenuBarShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
