// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import SwiftUI
import MenuBarVisibilityBridge

/// One Icon Drawer button and one grid of less-used status icons. On macOS 27
/// native visibility removes the originals while AXPress opens their menus.
final class MenuBarOverflowController: NSObject, ObservableObject {
    static let shared = MenuBarOverflowController()
    var onChooseIcons: (() -> Void)?
    @Published var isChoosingIcons = false
    struct OverflowItem: Identifiable {
        let id: String
        let bundle: String
        let name: String
        let icon: NSImage
        let element: AXUIElement
        let frame: CGRect
    }
    @Published private(set) var items: [OverflowItem] = []
    @Published private(set) var availableItems: [OverflowItem] = []
    @Published private(set) var isCollapsed = false
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    private var toggleItem: NSStatusItem?
    private var spacerItem: NSStatusItem?
    private var drawer: MenuBarOverflowPanel?
    private var drawerLocalMonitor: Any?
    private var drawerGlobalMonitor: Any?
    private var lastClickPoint: CGPoint?
    private var arrowAXFrame = CGRect.zero
    private var systemCache: [String: MenuBarOverflowInventory.Record] = [:]
    private var systemMenuTimer: Timer?
    private var wantsDrawerVisible = false
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
            self.closeDrawer()
            if self.usesNativeVisibility, !self.isArranging, !self.configuredBundles.isEmpty {
                self.collectAndHide(useSavedSelection: true, openDrawer: false)
            } else { self.arrangeIcons() }
        })
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self, self.toggleItem != nil, !self.isArranging,
                      !self.configuredBundles.isEmpty else { return }
                self.collectAndHide(useSavedSelection: true, openDrawer: false)
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
                else { collectAndHide(useSavedSelection: true, openDrawer: false, refreshInventory: !usesNativeVisibility || availableItems.isEmpty) }
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
            configureButton()
            if !configuredBundles.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    guard let self, self.toggleItem != nil, !self.isArranging else { return }
                    self.collectAndHide(useSavedSelection: true, openDrawer: false)
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
            let open = menu.addItem(withTitle: "Open Icon Drawer", action: #selector(showDrawer), keyEquivalent: "")
            open.target = self
            menu.addItem(.separator())
            let arrange = menu.addItem(withTitle: "Arrange icons…", action: #selector(arrangeIcons), keyEquivalent: "")
            arrange.target = self
            let save = menu.addItem(withTitle: "Move icons on the left into Icon Drawer", action: #selector(saveArrangement), keyEquivalent: "")
            save.target = self
            save.isEnabled = !isCollapsed && !isBusy
            menu.addItem(.separator())
            let disable = menu.addItem(withTitle: "Turn off Icon Drawer", action: #selector(disable), keyEquivalent: "")
            disable.target = self
            // Explicitly disabled setup actions must stay disabled.
            menu.autoenablesItems = false
            toggleItem?.menu = menu
            toggleItem?.button?.performClick(nil)
            toggleItem?.menu = nil
        } else { showDrawer() }
    }

    @objc private func disable() {
        UserDefaults.standard.set(false, forKey: DefaultsKey.menuBarOverflowEnabled)
        syncEnabled()
    }

    func loadAvailableIcons() {
        collectAndHide(useSavedSelection: true, openDrawer: false)
    }

    func setIncluded(_ bundle: String, included: Bool) {
        var selection = configuredBundles
        if included { selection.insert(bundle) } else { selection.remove(bundle) }
        UserDefaults.standard.set(selection.sorted().joined(separator: ","),
                                  forKey: DefaultsKey.menuBarOverflowBundles)
    }

    func chooseIcons() {
        closeDrawer()
        isChoosingIcons = true
        onChooseIcons?()
    }

    @objc func showDrawer() {
        if drawer?.isVisible == true { closeDrawer(); return }
        wantsDrawerVisible = true
        presentDrawer()
        if !isCollapsed && !isBusy {
            collectAndHide(useSavedSelection: !isArranging, openDrawer: true)
        }
    }

    @objc func arrangeIcons() {
        stopHiding()
        isArranging = true
        message = usesNativeVisibility
            ? "Hold ⌘ and drag the icons you want in Icon Drawer to the left of its arrow. Then choose Move icons into Icon Drawer."
            : "Hold ⌘ and drag icons to the left of the divider, and keep the divider left of the Icon Drawer arrow. Then choose Move icons into Icon Drawer."
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
        collectAndHide(useSavedSelection: false, openDrawer: false)
    }

    func stopHiding() {
        systemMenuTimer?.invalidate()
        systemMenuTimer = nil
        generation += 1
        closeDrawer()
        if let assertion { VSMenuBarVisibilityRelease(assertion) }
        assertion = nil
        spacerItem?.length = 18
        isCollapsed = false
        isBusy = false
    }

    private func collectAndHide(useSavedSelection: Bool, openDrawer: Bool, refreshInventory: Bool = true) {
        systemMenuTimer?.invalidate()
        systemMenuTimer = nil
        guard toggleItem != nil else { return }
        let windowFrame = toggleItem?.button?.window?.frame ?? .zero
        guard AXIsProcessTrusted() else {
            message = "Allow Vorssaint in System Settings → Privacy & Security → Accessibility, then click Icon Drawer again."
            if !requestedPermission {
                requestedPermission = true
                _ = AXIsProcessTrustedWithOptions([
                    kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
                ] as CFDictionary)
            }
            presentDrawer()
            return
        }
        if usesNativeVisibility, !VSMenuBarVisibilityAvailable() {
            message = "Menu bar hiding is unavailable on this macOS version. All icons remain visible."
            presentDrawer()
            return
        }
        if !usesNativeVisibility {
            guard let divider = spacerItem?.button?.window?.frame, divider.maxX <= windowFrame.minX else {
                message = "Command-drag the divider to the left of the Icon Drawer arrow first."
                presentDrawer()
                return
            }
        }
        message = nil
        isBusy = refreshInventory && availableItems.isEmpty
        generation += 1
        let request = generation
        let boundary = spacerItem?.button?.window?.frame.midX ?? windowFrame.midX
        let rtl = NSApp.userInterfaceLayoutDirection == .rightToLeft
        let saved = configuredBundles
        let ownBundle = Bundle.main.bundleIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let native = usesNativeVisibility
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleURL?.pathExtension == "app"
                && $0.bundleIdentifier != MenuBarOverflowInventory.menuBarAgentBundle
                && $0.processIdentifier != ownPID
        }
        var descriptors = apps.compactMap { app -> MenuBarOverflowInventory.Application? in
            guard let bundle = app.bundleIdentifier else { return nil }
            return .init(pid: app.processIdentifier, bundle: bundle, name: app.localizedName ?? bundle)
        }
        if let agent = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.MenuBarAgent" || $0.localizedName == "MenuBarAgent"
        }) {
            descriptors.append(.init(pid: agent.processIdentifier, bundle: MenuBarOverflowInventory.menuBarAgentBundle, name: "System"))
        }
        // Checkbox changes need a new allowlist, not a new inventory. Keep the
        // chooser's image objects, identities and row positions intact.
        let cachedInventory = availableItems.map {
            MenuBarOverflowInventory.Record(identifier: nil, id: $0.id, bundle: $0.bundle, name: $0.name, element: $0.element, frame: $0.frame)
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scannedInventory = refreshInventory ? MenuBarOverflowInventory.read(descriptors) : cachedInventory
            let ownItems = refreshInventory ? MenuBarOverflowInventory.read([.init(pid: ownPID, bundle: ownBundle ?? "", name: "Vorssaint")]) : []
            let actualBoundary = native ? (ownItems.first { $0.identifier == "vorssaint.icon-drawer" }?.frame.midX ?? boundary) : boundary
            let hidden = useSavedSelection ? saved : MenuBarOverflowSupport.hiddenBundles(
                items: scannedInventory.map { .init(bundle: $0.bundle, frame: $0.frame) },
                boundaryX: actualBoundary, rightToLeft: rtl)
            let allowed = MenuBarOverflowSupport.allowedBundles(running: Set(descriptors.map(\.bundle)), selection: hidden, ownBundle: ownBundle)
            DispatchQueue.main.async { [weak self] in
                guard let self, request == self.generation else { return }
                if let arrow = ownItems.first(where: { $0.identifier == "vorssaint.icon-drawer" }) {
                    self.arrowAXFrame = arrow.frame
                }
                if refreshInventory { self.refreshAvailableItems(from: scannedInventory) }
                self.items = self.availableItems.filter { hidden.contains($0.bundle) }
                self.isArranging = false
                if !useSavedSelection {
                    self.lastSelection = hidden
                    UserDefaults.standard.set(hidden.sorted().joined(separator: ","), forKey: DefaultsKey.menuBarOverflowBundles)
                }
                guard !hidden.isEmpty else {
                    let reopen = openDrawer && self.wantsDrawerVisible
                    self.stopHiding()
                    self.wantsDrawerVisible = reopen
                    self.message = "Icon Drawer is empty. Open Settings → Menu bar → Choose icons and select the icons you want here."
                    if openDrawer && self.wantsDrawerVisible { self.presentDrawer() }
                    return
                }
                if !self.usesNativeVisibility {
                    self.spacerItem?.length = min(10_000, max(500, (NSScreen.screens.map { $0.frame.width }.max() ?? 2000) * 2))
                    self.isBusy = false
                    self.isCollapsed = true
                    if openDrawer && self.wantsDrawerVisible { self.presentDrawer() }
                    return
                }
                self.activateVisibility(allowedBundles: allowed, selection: hidden, request: request) { [weak self] activated, error in
                    guard let self else { return }
                    self.isBusy = false
                    if activated {
                        self.isCollapsed = true
                    } else {
                        let reopen = openDrawer && self.wantsDrawerVisible
                        self.stopHiding()
                        self.wantsDrawerVisible = reopen
                        self.message = error?.localizedDescription ?? "Could not move icons into Icon Drawer."
                    }
                    if openDrawer && self.wantsDrawerVisible { self.presentDrawer() }
                }
            }
        }
    }

    private func refreshAvailableItems(from records: [MenuBarOverflowInventory.Record]) {
        // NSImage belongs to the UI thread. Resolve images here,
        // after the background accessibility read has completed.
        let appIcons = Dictionary(NSWorkspace.shared.runningApplications.compactMap { app -> (String, NSImage)? in
            guard let bundle = app.bundleIdentifier, let icon = app.icon else { return nil }
            return (bundle, icon)
        }, uniquingKeysWith: { first, _ in first })
        for record in records where record.bundle.hasPrefix("system:") {
            systemCache[record.bundle] = record
        }
        let inventory = records.filter { !$0.bundle.hasPrefix("system:") }
            + systemCache.values.sorted { $0.name < $1.name }
        let refreshed = inventory.map { record in
            let symbol = MenuBarOverflowSupport.systemControl(selectionKey: record.bundle)?.symbol ?? "app"
            let icon = appIcons[record.bundle] ?? NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage()
            return OverflowItem(id: record.id, bundle: record.bundle, name: record.name,
                                icon: icon, element: record.element, frame: record.frame)
        }
        let byID = Dictionary(refreshed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        availableItems = MenuBarOverflowSupport.stableOrder(previous: availableItems.map(\.id),
            current: refreshed.map(\.id)).compactMap { byID[$0] }
    }

    private func presentDrawer() {
        guard toggleItem != nil else { return }
        let columns = items.count > 9 ? 4 : 3
        let width = CGFloat(columns) * 88 + 28
        let rows = max(1, Int(ceil(Double(items.count) / Double(columns))))
        let height = min(360, max(150, CGFloat(rows) * 72 + (message == nil && !items.isEmpty && AXIsProcessTrusted() ? 110 : 166)))
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
        let panel: MenuBarOverflowPanel
        if let drawer { panel = drawer }
        else {
            panel = MenuBarOverflowPanel(contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Icon Drawer"
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .popUpMenu
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let hosting = NSHostingView(rootView: MenuBarOverflowDrawer(controller: self))
            hosting.frame = CGRect(origin: .zero, size: frame.size)
            hosting.autoresizingMask = [.width, .height]
            // Clip hosted content as well as the glass: NSGlassEffectView does
            // not mask arbitrary content backing layers to its rounded shape.
            hosting.wantsLayer = true
            hosting.layer?.cornerRadius = 18
            hosting.layer?.masksToBounds = true
            panel.contentView = Self.drawerBackdrop(content: hosting)
            drawer = panel
        }
        panel.appearance = NSApp.appearance
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        installDrawerMonitors()
    }

    /// Use the system glass renderer rather than a tinted imitation. Older
    /// systems retain their native popover material and the same geometry.
    private static func drawerBackdrop(content: NSView) -> NSView {
#if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: content.frame)
            glass.style = .regular
            glass.cornerRadius = 18
            glass.wantsLayer = true
            glass.layer?.cornerRadius = 18
            glass.layer?.masksToBounds = true
            glass.contentView = content
            return glass
        }
#endif
        let material = NSVisualEffectView(frame: content.frame)
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 18
        material.layer?.masksToBounds = true
        material.addSubview(content)
        return material
    }

    private func installDrawerMonitors() {
        guard drawerLocalMonitor == nil else { return }
        drawerLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.closeDrawer()
                return nil
            }
            if event.type != .keyDown, self.drawer?.frame.contains(NSEvent.mouseLocation) != true {
                // Let the arrow's own mouse-up toggle the dropdown once.
                if event.window !== self.toggleItem?.button?.window { self.closeDrawer() }
            }
            return event
        }
        drawerGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            let point = NSEvent.mouseLocation
            // On macOS 27 the menu bar belongs to MenuBarAgent, so our arrow's
            // mouse-down is a global event. Leave its mouse-up to toggle once.
            let screen = NSScreen.screens.first { $0.frame.contains(point) }
            let inBar = screen.map { point.y >= $0.frame.maxY - max(33, $0.safeAreaInsets.top) } ?? false
            let anchorX = self.lastClickPoint?.x ?? self.arrowAXFrame.midX
            if inBar && abs(point.x - anchorX) < 24 { return }
            self.closeDrawer()
        }
    }

    private func closeDrawer() {
        wantsDrawerVisible = false
        drawer?.orderOut(nil)
        if let drawerLocalMonitor { NSEvent.removeMonitor(drawerLocalMonitor) }
        if let drawerGlobalMonitor { NSEvent.removeMonitor(drawerGlobalMonitor) }
        drawerLocalMonitor = nil
        drawerGlobalMonitor = nil
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func open(_ item: OverflowItem) {
        closeDrawer()
        if item.bundle.hasPrefix("system:"), usesNativeVisibility {
            openSystemMenu(item)
            return
        }
        // Let the transient drawer relinquish focus before the other app opens
        // its native status menu. No synthetic pointer events or app launches.
        let request = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, request == self.generation else { return }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let result = AXUIElementPerformAction(item.element, kAXPressAction as CFString)
                DispatchQueue.main.async { [weak self] in
                    // Some status menus enter a tracking loop before replying to AXPress.
                    // cannotComplete can mean that the menu opened, so never dismiss
                    // it or reveal the whole bar in response to that timeout.
                    guard let self, request == self.generation,
                          result != .success, result != .cannotComplete else { return }
                    self.stopHiding()
                    self.message = "\(item.name) could not open its menu from Icon Drawer. Its original icon is visible again; click it in the menu bar."
                }
            }
        }
    }

    /// Install a replacement before releasing the old assertion. Obsolete
    /// completions release their handles without changing current UI state.
    private func activateVisibility(allowedBundles: [String], selection: Set<String>, request: Int,
                                    completion: @escaping (Bool, Error?) -> Void) {
        VSMenuBarVisibilityActivate(allowedBundles, MenuBarOverflowSupport.allowedSystemItems(selection: selection)) { [weak self] handle, error in
            guard let self, request == self.generation else {
                if let handle { VSMenuBarVisibilityRelease(handle) }
                return
            }
            if let handle {
                let previous = self.assertion
                self.assertion = handle
                if let previous { VSMenuBarVisibilityRelease(previous) }
                completion(true, nil)
            } else {
                completion(false, error)
            }
        }
    }

    private func openSystemMenu(_ item: OverflowItem) {
        systemMenuTimer?.invalidate()
        generation += 1
        let request = generation
        let selection = configuredBundles.subtracting([item.bundle])
        let allowed = MenuBarOverflowSupport.allowedBundles(
            running: Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }),
            selection: selection, ownBundle: Bundle.main.bundleIdentifier)
        activateVisibility(allowedBundles: allowed, selection: selection, request: request) { [weak self] activated, error in
            guard let self else { return }
            guard activated else {
                self.message = error?.localizedDescription ?? "Could not open \(item.name)."
                return
            }
            let agents = NSWorkspace.shared.runningApplications.filter {
                $0.bundleIdentifier == "com.apple.MenuBarAgent" || $0.localizedName == "MenuBarAgent"
            }.map { MenuBarOverflowInventory.Application(pid: $0.processIdentifier, bundle: MenuBarOverflowInventory.menuBarAgentBundle, name: "System") }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.25) { [weak self] in
                let fresh = MenuBarOverflowInventory.read(agents).first { $0.bundle == item.bundle }
                let result = fresh.map { AXUIElementPerformAction($0.element, kAXPressAction as CFString) } ?? .invalidUIElement
                DispatchQueue.main.async { [weak self] in
                    guard let self, request == self.generation else { return }
                    if result != .success && result != .cannotComplete {
                        self.collectAndHide(useSavedSelection: true, openDrawer: false)
                        self.message = "Could not open \(item.name). Try again from Icon Drawer."
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
                self.collectAndHide(useSavedSelection: true, openDrawer: false)
            }
        }
    }

    private func configureButton() {
        toggleItem?.button?.image = NSImage(systemSymbolName: "chevron.down",
                                            accessibilityDescription: "Icon Drawer menu bar icons")
        toggleItem?.button?.toolTip = "Icon Drawer — open your hidden menu bar icons. Right-click to arrange icons."
        toggleItem?.button?.setAccessibilityLabel("Icon Drawer menu bar icons")
        toggleItem?.button?.setAccessibilityIdentifier("vorssaint.icon-drawer")
    }


}

private final class MenuBarOverflowPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
