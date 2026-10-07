// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import SwiftUI

struct MenuBarOverflowSettings: View {
    @ObservedObject private var overflow = MenuBarOverflowController.shared
    @AppStorage(DefaultsKey.menuBarOverflowBundles) private var selectedBundles = ""
    @AppStorage(DefaultsKey.menuBarOverflowEnabled) private var enabled = false

    var body: some View {
        SettingsCard(title: "Icon Drawer") {
            SettingsRow(symbol: "chevron.down", title: "Menu bar icons",
                        caption: "Keep less-used icons under one arrow.") {
                Toggle("Icon Drawer", isOn: $enabled)
                    .labelsHidden().toggleStyle(.switch)
            }
            if enabled {
                DisclosureGroup(isExpanded: $overflow.isChoosingIcons) {
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                        GridItem(.flexible(), alignment: .leading)], spacing: 8) {
                        ForEach(overflow.availableItems) { item in
                            HStack(spacing: 8) {
                                Image(nsImage: item.icon).resizable().scaledToFit()
                                    .frame(width: 18, height: 18)
                                Toggle(item.name, isOn: Binding(
                                    get: { selectedBundles.split(separator: ",").contains(Substring(item.bundle)) },
                                    set: { overflow.setIncluded(item.bundle, included: $0) }
                                )).toggleStyle(.checkbox)
                                    .lineLimit(1).help(item.name)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.vertical, 8)
                    Text("Includes system controls and icons behind the camera. Requires Accessibility. On macOS 27, icons from the same app move together.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } label: {
                    HStack {
                        Text("Choose icons")
                        Spacer()
                        if overflow.isBusy && overflow.availableItems.isEmpty { ProgressView().controlSize(.small) }
                        else {
                            Text("\(selectedBundles.split(separator: ",").count) selected")
                                .foregroundStyle(.secondary)
                        }
                    }.font(.callout)
                }
                HStack {
                    Button("Open Icon Drawer") { overflow.showDrawer() }
                    Spacer()
                    Button("Reset arrow position") { overflow.restoreArrow() }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }.font(.caption)
                if let message = overflow.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onChange(of: overflow.isChoosingIcons) { _, expanded in
            if expanded && enabled { overflow.loadAvailableIcons() }
        }
        .onAppear {
            if enabled && overflow.isChoosingIcons { overflow.loadAvailableIcons() }
        }
    }
}
