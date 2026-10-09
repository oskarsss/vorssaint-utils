// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Focus-state and AX-panel approach adapted from Pelmet, Copyright (C) 2026 Gabriel Faucon.

import AppKit
import ApplicationServices
import Darwin

/// macOS removes its Focus extra for every assessment-mode assertion,
/// regardless of the allowlist. Keep a replacement outside the drawer and
/// open Control Center's native Focus panel, without releasing the assertion.
/// The log-based state and custom AX action approach follows Pelmet (GPL-3.0):
/// https://github.com/fif7y/pelmet/blob/main/Pelmet/Extras/FocusStatus.swift
final class MenuBarOverflowFocus: NSObject {
    private var item: NSStatusItem?
    private var stream: Process?
    private var pending = Data()
    private var revision = 0
    private var enabled = false
    private var mode: MenuBarOverflowSupport.FocusMode?
    private var termination: NSObjectProtocol?
    private let observerKey = "menuBarOverflowFocusObserver"
    private static let predicate = #"process == "donotdisturbd" AND ((category == "ServiceProvider" AND eventMessage BEGINSWITH "Did receive state update") OR (category == "StateProvider" AND eventMessage BEGINSWITH "Calculate DND state for snapshot"))"#

    func start() {
        guard !enabled else { return }
        reapPreviousObserver()
        enabled = true
        if termination == nil {
            termination = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                object: nil, queue: .main) { [weak self] _ in self?.stop() }
        }
        updateIcon()
        let initialRevision = revision
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let process = Self.logProcess(["show", "--last", "7d"])
            let pipe = Pipe()
            process.standardOutput = pipe
            guard (try? process.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.enabled, self.revision == initialRevision else { return }
                self.consume(data)
            }
        }
        startStream()
    }

    func stop() {
        enabled = false
        revision += 1
        (stream?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        if let stream {
            if UserDefaults.standard.string(forKey: observerKey)?.hasPrefix("\(stream.processIdentifier):") == true {
                UserDefaults.standard.removeObject(forKey: observerKey)
            }
            if stream.isRunning { stream.terminate() }
        }
        stream = nil
        pending.removeAll()
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    private static func logProcess(_ arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = arguments + ["--style", "ndjson", "--predicate", predicate]
        process.standardError = FileHandle.nullDevice
        return process
    }

    private func startStream() {
        let process = Self.logProcess(["stream"])
        let pipe = Pipe()
        process.standardOutput = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.enabled else { return }
                self.consume(data)
            }
        }
        process.terminationHandler = { [weak self, weak process] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self, let process, self.enabled, self.stream === process else { return }
                self.startStream()
            }
        }
        do {
            try process.run()
            stream = process
            if let identity = Self.processIdentity(process.processIdentifier) {
                UserDefaults.standard.set(identity, forKey: observerKey)
            }
        }
        catch { pipe.fileHandleForReading.readabilityHandler = nil }
    }

    /// A crash or installer SIGTERM bypasses AppKit's termination notification.
    /// Reap only our recorded log child, with matching process birth time and
    /// user, after it has been orphaned. PID reuse cannot kill another process.
    private func reapPreviousObserver() {
        guard let identity = UserDefaults.standard.string(forKey: observerKey),
              let pid = identity.split(separator: ":").first.flatMap({ Int32($0) }) else { return }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout.size(ofValue: info))
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
           info.pbi_ppid == 1, info.pbi_uid == getuid(), Self.processIdentity(pid) == identity {
            kill(pid, SIGTERM)
        }
        UserDefaults.standard.removeObject(forKey: observerKey)
    }

    private static func processIdentity(_ pid: pid_t) -> String? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout.size(ofValue: info))
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return "\(pid):\(info.pbi_start_tvsec):\(info.pbi_start_tvusec)"
    }

    private func consume(_ data: Data) {
        pending.append(data)
        while let newline = pending.firstIndex(of: 10) {
            let line = pending[..<newline]
            if let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
               (json["userID"] as? Int).map({ $0 == Int(getuid()) }) ?? true,
               let message = json["eventMessage"] as? String {
                if message.hasPrefix("Did receive state update") {
                    revision += 1
                    mode = MenuBarOverflowSupport.focusMode(in: message)
                } else if let start = message.range(of: "activeAssertionUUIDs=(")?.upperBound,
                          let end = message[start...].firstIndex(of: ")"),
                          message[start..<end].allSatisfy(\.isWhitespace) {
                    revision += 1
                    mode = nil
                }
            }
            pending.removeSubrange(...newline)
        }
        // Bound a malformed or truncated log line; no log data is persisted.
        if pending.count > 65_536 { pending.removeAll() }
        updateIcon()
    }

    private func updateIcon() {
        let preferences = UserDefaults(suiteName: "com.apple.controlcenter")
        let visible = mode != nil || preferences?.bool(forKey: "NSStatusItem VisibleCC FocusModes") == true
        guard visible else {
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            return
        }
        if item == nil {
            let identity = "VorssaintOverflowFocus"
            let key = "NSStatusItem Preferred Position " + identity
            if UserDefaults.standard.object(forKey: key) == nil,
               let position = preferences?.object(forKey: "NSStatusItem Preferred Position FocusModes") {
                UserDefaults.standard.set(position, forKey: key)
            }
            let created = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            created.autosaveName = identity
            created.button?.target = self
            created.button?.action = #selector(openFocus)
            created.button?.setAccessibilityIdentifier("vorssaint.preserved-focus")
            item = created
        }
        let name = mode?.name ?? "Focus"
        let image = NSImage(systemSymbolName: mode?.symbol ?? "moon", accessibilityDescription: name)
        image?.isTemplate = true
        item?.button?.image = image
        item?.button?.toolTip = name
        item?.button?.setAccessibilityLabel(name)
    }

    @objc private func openFocus() {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: MenuBarOverflowInventory.menuBarAgentBundle).first,
                  let control = Self.find(AXUIElementCreateApplication(agent.processIdentifier), identifier: "com.apple.menuextra.controlcenter") else { return }
            AXUIElementPerformAction(control, kAXPressAction as CFString)
            // Control Center builds its panel asynchronously. Resolve the
            // localized details action; pressing the tile would toggle DND.
            for _ in 0..<60 {
                guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else { return }
                if let tile = Self.find(AXUIElementCreateApplication(app.processIdentifier), identifier: "module-FocusModes"),
                   let checkbox = Self.find(tile, role: kAXCheckBoxRole) {
                    var actions: CFArray?
                    AXUIElementCopyActionNames(checkbox, &actions)
                    if let details = (actions as? [String])?.first(where: { $0.hasPrefix("Name:") }) {
                        AXUIElementPerformAction(checkbox, details as CFString)
                    }
                    return
                }
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }

    private static func find(_ element: AXUIElement, identifier: String? = nil, role: String? = nil, depth: Int = 0) -> AXUIElement? {
        guard depth < 9 else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.05)
        var value: CFTypeRef?
        let attribute = identifier != nil ? kAXIdentifierAttribute : kAXRoleAttribute
        AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if value as? String == (identifier ?? role) { return element }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        for child in children as? [AXUIElement] ?? [] {
            if let found = find(child, identifier: identifier, role: role, depth: depth + 1) { return found }
        }
        return nil
    }
}
