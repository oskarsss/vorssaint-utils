// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Vector walkthroughs never read windows, clipboard, devices, media metadata
/// or files. Only this opened popover owns an animation clock. Samples remain
/// sharp at every display scale; Reduce Motion supplies a still final frame.
struct FeaturePreview: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var visibility = SettingsWindowVisibility.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var playing = true
    @State private var started = Date()
    @State private var pausedProgress = 0.0
    let feature: AppFeature

    private var discovery: SettingsDiscoveryStrings { .localized(l10n.language) }
    private var hub: FeatureHubStrings { FeatureStrings.hub(l10n.language) }
    private var title: String { feature.hubTitle(l10n.s, hub: hub) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(title, systemImage: feature.symbolName).font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(discovery.text(.closePreview))
            }
            TimelineView(.animation(minimumInterval: 1.0 / 30,
                                    paused: !playing || reduceMotion || !visibility.isVisible)) { context in
                let progress = reduceMotion ? 0.8 : playing
                    ? context.date.timeIntervalSince(started).truncatingRemainder(dividingBy: 6) / 6
                    : pausedProgress
                FeaturePreviewScene(feature: feature, progress: progress)
                    .frame(height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.08)))
                    .accessibilityHidden(true)
            }
            Text(feature.hubDescription(hub))
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                Label(discovery.text(.illustration), systemImage: "sparkles")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !reduceMotion {
                    Button(playing ? discovery.text(.pause) : discovery.text(.play), systemImage: playing ? "pause.fill" : "play.fill") {
                        if playing {
                            pausedProgress = Date().timeIntervalSince(started).truncatingRemainder(dividingBy: 6) / 6
                        } else {
                            started = Date().addingTimeInterval(-pausedProgress * 6)
                        }
                        playing.toggle()
                    }.buttonStyle(.borderless)
                }
            }
            Divider()
            if !feature.permissions.isEmpty {
                Label(feature.permissions.map { $0.name(hub) }.joined(separator: " · "),
                      systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text(discovery.text(.noPermissions))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if feature.isAvailable && feature.hasNavigableSettingsDestination {
                    Button(SettingsDiscoveryStrings.localized(l10n.language).configure) {
                        dismiss()
                        SettingsRouter.shared.request(feature.settingsDestination, sidebarFeature: feature)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 490)
    }
}

private struct FeaturePreviewScene: View {
    let feature: AppFeature
    let progress: Double
    private var action: CGFloat {
        let t = min(max((progress - 0.2) / 0.35, 0), 1)
        return CGFloat(t * t * (3 - 2 * t))
    }
    private var active: Bool { progress > 0.4 }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.03)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "apple.logo")
                    Text("Sample workspace").fontWeight(.medium)
                    Spacer()
                    Image(systemName: "wifi")
                    Text("10:00")
                }
                .font(.system(size: 10)).padding(.horizontal, 13).padding(.vertical, 7)
                .background(Color(nsColor: .windowBackgroundColor))
                GeometryReader { geometry in
                    scene(size: geometry.size)
                }
                Text(caption)
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private func scene(size: CGSize) -> some View {
        switch feature.group {
        case .windowsDock: windows(size: size)
        case .mouseKeyboard: input(size: size)
        case .clipboardFiles: files(size: size)
        case .capture: capture(size: size)
        case .sound: audio(size: size)
        case .energyDisplay: energy(size: size)
        case .dynamicIsland: island(size: size)
        case .monitor: monitor(size: size)
        case .tools, .applications: tool(size: size)
        }
    }

    private func sampleWindow(_ title: String, color: Color = .accentColor) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle().fill([Color.red, .yellow, .green][index]).frame(width: 5, height: 5)
                }
                Text(title).font(.system(size: 9, weight: .medium)).padding(.leading, 5)
                Spacer()
            }
            ForEach(0..<3) { index in
                RoundedRectangle(cornerRadius: 3).fill(color.opacity(index == 0 ? 0.22 : 0.08))
                    .frame(height: 7).padding(.trailing, CGFloat(index * 14))
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(color.opacity(0.2)))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
    }

    private func windows(size: CGSize) -> some View {
        let layout = feature == .windowLayout || feature == .windowMaximizer
        let closes = feature == .autoQuit || feature == .dockClick
        return ZStack {
            sampleWindow("Notes", color: .orange)
                .frame(width: 150, height: 106)
                .position(x: size.width * 0.62, y: size.height * 0.53)
                .opacity(layout ? Double(1 - action) : 1)
            sampleWindow("Browser")
                .frame(width: layout ? 150 + action * (size.width - 186) : 158,
                       height: layout ? 106 + action * 27 : 106)
                .position(x: layout ? size.width * (0.4 + 0.1 * action) : size.width * 0.4,
                          y: size.height * 0.48)
                .scaleEffect(closes ? 1 - action * 0.3 : 1)
                .opacity(closes ? Double(1 - action) : 1)
            if feature == .switcher || feature == .spacesOrder {
                HStack(spacing: 14) {
                    ForEach(["safari", "note.text", "folder"], id: \.self) { icon in
                        Image(systemName: icon).font(.title2)
                            .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(icon == "note.text" && active ? Color.accentColor : .clear, lineWidth: 2))
                    }
                }
                .padding(12).background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                .position(x: size.width / 2, y: size.height / 2).opacity(Double(action))
            }
            if feature == .dockPreview {
                sampleWindow("Window preview").frame(width: 110, height: 78)
                    .position(x: size.width * 0.72, y: size.height * 0.4).opacity(Double(action))
            }
            Image(systemName: "cursorarrow").font(.title3)
                .position(x: size.width * 0.72, y: size.height * (0.8 - 0.35 * action))
        }
    }

    private func input(size: CGSize) -> some View {
        ZStack {
            if [.scrollInverter, .scrollHorizontal, .smoothScroll, .linearScroll].contains(feature) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(0..<9) { index in
                        HStack {
                            RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.25)).frame(width: 20, height: 20)
                            RoundedRectangle(cornerRadius: 3).fill(.secondary.opacity(0.15)).frame(height: 7)
                                .padding(.trailing, CGFloat(index % 3 * 24))
                        }
                    }
                }
                .padding(15).offset(x: feature == .scrollHorizontal ? -action * 50 : 0,
                                    y: feature == .scrollHorizontal ? 0 : -action * 85)
                .frame(width: 230, height: 120, alignment: .top).clipped()
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                .position(x: size.width * 0.44, y: size.height / 2)
                Image(systemName: feature == .scrollHorizontal ? "arrow.left.arrow.right" : "arrow.up.arrow.down")
                    .font(.title).foregroundStyle(Color.accentColor)
                    .position(x: size.width * 0.8, y: size.height / 2)
            } else {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        key(inputExample.0)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        key(active ? inputExample.1 : "…")
                    }
                    Image(systemName: feature.symbolName).font(.system(size: 30))
                        .foregroundStyle(Color.accentColor).scaleEffect(1 + action * 0.15)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var inputExample: (String, String) {
        switch feature {
        case .textSnippets: return (";hello", "Hello!")
        case .superKey: return ("⇪", "⌃ ⌥ ⇧ ⌘")
        case .quitWindowProtection: return ("⌘ Q", "Hold to quit")
        case .keyboardDebounce: return ("A A", "A")
        case .mouseClickDebounce: return ("Click Click", "Click")
        case .mouseNavigation: return ("Side button", "← Back")
        case .mouseButtonShortcuts: return ("Side button", "⌘ C")
        case .middleClick: return ("3 fingers", "Middle click")
        case .focusFollowsMouse: return ("Point at window", "Focus window")
        case .mouseAcceleration: return ("Mouse movement", "Linear movement")
        default: return ("Input", "Action")
        }
    }

    private func key(_ label: String) -> some View {
        Text(label).font(.system(size: 16, weight: .medium, design: .monospaced))
            .padding(12).background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.12)))
    }

    private func files(size: CGSize) -> some View {
        VStack(spacing: 14) {
            if feature == .clipboardHistory || feature == .shelf {
                HStack(spacing: 10) {
                    ForEach(0..<3) { index in
                        VStack(spacing: 8) {
                            Image(systemName: index == 1 ? "photo" : "doc.text").font(.title2)
                            Text(["Sample note", "Sample image", "Sample file"][index]).font(.system(size: 9))
                        }
                        .padding(12).background(.background, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(index == 1 && active ? Color.accentColor : .clear, lineWidth: 2))
                        .offset(y: index == 1 ? -action * 8 : 0)
                    }
                }
                Label(active ? "Ready to paste or drop" : "Copy or drag items", systemImage: feature.symbolName).font(.caption)
            } else {
                Label(fileExample.0, systemImage: "doc.text")
                    .font(.system(size: 12)).opacity(Double(1 - action * 0.5))
                Image(systemName: "arrow.down").foregroundStyle(Color.accentColor)
                Label(fileExample.1, systemImage: feature.symbolName)
                    .font(.system(size: 14, weight: .medium)).opacity(Double(0.3 + action * 0.7))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fileExample: (String, String) {
        switch feature {
        case .urlCleaner: return ("example.com?utm_source=sample", "example.com")
        case .pastePlain: return ("Styled sample text", "Plain sample text")
        case .finderCutPaste: return ("⌘ X · Sample file", "⌘ V · Destination folder")
        case .finderRename: return ("Sample file.txt", "Renamed file.txt")
        case .diskImageInstaller: return ("Sample app.dmg", "Applications / Sample app")
        default: return ("Sample document", "Destination folder")
        }
    }

    private func capture(size: CGSize) -> some View {
        ZStack {
            if feature == .cameraPreview {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.15))
                    Image(systemName: "person.crop.rectangle.fill").font(.system(size: 72))
                        .foregroundStyle(Color.accentColor.opacity(0.65))
                    Label("Fictional camera preview", systemImage: "video.fill")
                        .font(.caption).offset(y: 56)
                }.frame(width: 250, height: 144).scaleEffect(0.85 + action * 0.15)
            } else if feature == .mediaTools {
                HStack(spacing: 25) {
                    key("PNG")
                    Image(systemName: "arrow.right").foregroundStyle(Color.accentColor)
                    key(active ? "WebP" : "…")
                }
            } else {
            sampleWindow("Sample canvas").frame(width: 300, height: 132)
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                .frame(width: 45 + action * 145, height: 28 + action * 58)
                .offset(x: -20, y: -5)
            Label(feature == .screenRecorder ? "00:04" : feature == .screenOCR ? "Sample text" : feature == .colorPicker ? "#6C80F4" : "Sample capture", systemImage: feature.symbolName)
                .font(.system(size: 11, weight: .medium)).padding(8)
                .background(Color(nsColor: .windowBackgroundColor), in: Capsule()).offset(y: 57).opacity(Double(action))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func audio(size: CGSize) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 24) {
                Image(systemName: feature == .musicBlock ? (active ? "music.note" : "play.circle") : feature == .micMute && active ? "mic.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 32)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 8) {
                    Text(feature == .musicBlock ? (active ? "Open the chosen player" : "Block the unwanted player") : feature == .soundOutputSwitcher || feature == .audioPriority ? (active ? "Sample headphones" : "Sample speakers") : "Sample audio").font(.caption)
                    Capsule().fill(.secondary.opacity(0.15)).frame(width: 190, height: 6)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color.accentColor).frame(width: feature == .micMute ? 150 * (1 - action) : 70 + action * 85, height: 6)
                        }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func energy(size: CGSize) -> some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.12 + Double(action) * 0.3))
                    .frame(width: 190, height: 105)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.5), lineWidth: 3))
                Image(systemName: feature.symbolName).font(.system(size: 30)).foregroundStyle(Color.accentColor)
            }
            Label(feature == .keepAwake ? "Stay awake for 30 minutes" : feature == .bluetoothSleep ? "Bluetooth follows sleep / wake" : "Sample display brightness", systemImage: "display")
                .font(.caption)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func island(size: CGSize) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: feature == .notch ? "music.note" : feature.symbolName)
                    .font(.title2).foregroundStyle(.cyan)
                if active {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(feature == .notchTimer ? "Focus · 24:59" : feature == .notchLyrics ? "A sample lyric line" : "Sample activity")
                            .font(.system(size: 13, weight: .medium))
                        Text(feature == .notchCalendar ? "10:00 · Sample event" : "Dynamic Island")
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Image(systemName: feature == .notchTimer ? "pause.fill" : "chevron.right")
                }
            }
            .foregroundStyle(.white).padding(18)
            .frame(width: 100 + action * 240, height: 55 + action * 33)
            .background(.black, in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
            Image(systemName: "cursorarrow").offset(x: 62 - action * 20)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func monitor(size: CGSize) -> some View {
        HStack(spacing: 20) {
            ZStack {
                Circle().stroke(.secondary.opacity(0.12), lineWidth: 9)
                Circle().trim(from: 0, to: 0.2 + action * 0.45)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                Image(systemName: feature.symbolName).font(.title)
            }.frame(width: 88, height: 88)
            VStack(alignment: .leading, spacing: 8) {
                Text("Sample readings").font(.caption)
                Text(feature == .monitorMemory ? "8.0 GB" : feature == .monitorPower ? "82%" : feature == .connectedDevices ? "Sample USB device" : "\(Int(20 + action * 45))%")
                    .font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(0..<12) { index in
                        RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.4))
                            .frame(width: 7, height: 8 + CGFloat((index * 7) % 23) + action * 10)
                    }
                }.frame(height: 42)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolExample: (String, String, String) {
        switch feature {
        case .quickLauncher: return ("Open the quick panel", "Choose a favorite tool", "square.grid.2x2")
        case .quickToggles: return ("Wi-Fi is on", "Wi-Fi is off", "wifi.slash")
        case .cleaningMode: return ("Lock keyboard and mouse", "Tap Escape 5× to unlock", "lock.open")
        case .cleaner: return ("Review sample cache files", "Free space after cleanup", "internaldrive")
        case .uninstaller: return ("Sample app + related files", "Review and move to Trash", "trash")
        case .homebrew: return ("Sample package 1.0", "Update to package 2.0", "shippingbox")
        case .appUpdates: return ("Sample app 1.0", "Install app 2.0", "arrow.down.app")
        case .wallpaper: return ("Choose a sample picture", "Set desktop wallpaper", "photo")
        case .killProcess: return ("Sample process is running", "Review and end process", "stop.circle")
        case .portManager: return ("Port 3000 is in use", "Inspect its sample process", "network")
        case .scratchpad: return ("Open a quick note", "Write a sample thought", "note.text")
        case .radialMenu: return ("Invoke the radial menu", "Point toward an action", "cursorarrow")
        case .commandBar: return ("Type a command", "Choose the matching action", "command")
        default: return ("Choose a tool", "Sample workflow", feature.symbolName)
        }
    }

    private func tool(size: CGSize) -> some View {
        ZStack {
            if feature == .commandBar || feature == .quickLauncher {
                VStack(alignment: .leading, spacing: 10) {
                    Label(active ? "Sample command" : "Search commands…", systemImage: "magnifyingglass")
                        .font(.callout).padding(9).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                    ForEach(["Open sample app", "Create a sample note", "Find a sample file"], id: \.self) { title in
                        Label(title, systemImage: "arrow.up.right")
                            .font(.caption).padding(7).frame(maxWidth: .infinity, alignment: .leading)
                            .background(title == "Create a sample note" && active ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                }.padding(12).frame(width: 290).background(.background, in: RoundedRectangle(cornerRadius: 12))
            } else if feature == .radialMenu {
                ZStack {
                    Circle().stroke(Color.accentColor.opacity(0.3), lineWidth: 38).frame(width: 100, height: 100)
                    ForEach(0..<4) { index in
                        let angle = Double(index) * .pi / 2
                        Image(systemName: ["folder", "note.text", "safari", "music.note"][index])
                            .foregroundStyle(index == 1 && active ? Color.accentColor : .secondary)
                            .offset(x: cos(angle) * 55, y: sin(angle) * 55)
                    }
                    Image(systemName: "cursorarrow").offset(x: 20 * action, y: 40 * action)
                }.scaleEffect(0.8 + action * 0.2)
            } else if feature == .scratchpad {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Sample note", systemImage: "note.text").font(.caption).foregroundStyle(.secondary)
                    Text(active ? "A thought to remember." : "A thought…").font(.callout)
                    Spacer()
                }.padding(15).frame(width: 260, height: 130).background(.background, in: RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(spacing: 18) {
                    HStack(spacing: 24) {
                        Image(systemName: feature.symbolName).font(.system(size: 34)).foregroundStyle(Color.accentColor)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Image(systemName: toolExample.2).font(.system(size: 34))
                            .foregroundStyle(Color.accentColor).opacity(Double(0.25 + action * 0.75))
                    }
                    Text(active ? toolExample.1 : toolExample.0).font(.callout)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var caption: String {
        switch feature.group {
        case .windowsDock: return active ? "The window or workspace responds" : "Choose a window, shortcut or Dock action"
        case .mouseKeyboard: return active ? "Your input follows the configured behavior" : "Use the configured mouse gesture or key"
        case .clipboardFiles: return active ? "Reuse or organize the sample content" : "Copy, drag or select sample content"
        case .capture: return active ? "Capture, read or edit the selected content" : "Choose the tool and sample area"
        case .sound: return active ? "Apply the chosen audio control" : "Choose an audio control or device"
        case .energyDisplay: return "Control how the sample Mac stays awake or manages its display"
        case .dynamicIsland: return active ? "Activity expands in the island" : "Bring an activity into the island"
        case .monitor: return "Illustrative readings, not measurements from your Mac"
        case .tools, .applications: return "Illustrated workflow — see the description for this tool’s behavior"
        }
    }
}
