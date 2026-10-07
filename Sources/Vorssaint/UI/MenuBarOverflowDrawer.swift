// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import SwiftUI
import ApplicationServices

/// One compact dropdown: every chosen status icon lives in the same grid.
struct MenuBarOverflowDrawer: View {
    @ObservedObject var controller: MenuBarOverflowController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Icon Drawer")
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 2)
            Divider()
            if controller.isBusy {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading icons…").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !AXIsProcessTrusted() {
                VStack(spacing: 10) {
                    Image(systemName: "lock.open").font(.system(size: 26)).foregroundStyle(.secondary)
                    Text("Allow Accessibility to choose icons and open their menus.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Open Accessibility Settings") { controller.openAccessibilitySettings() }
                        .font(.caption)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !controller.items.isEmpty {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4),
                                             count: controller.items.count > 9 ? 4 : 3), spacing: 6) {
                        ForEach(controller.items) { item in
                            MenuBarOverflowIcon(item: item) { controller.open(item) }
                        }
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "ellipsis.circle").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text("Your less-used icons go here.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
            }
            Divider()
            Button { controller.chooseIcons() } label: {
                Text("Choose Icons…")
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
                .accessibilityLabel("Choose icons for Icon Drawer")
            if let message = controller.message, AXIsProcessTrusted() {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
    }
}

private struct MenuBarOverflowIcon: View {
    let item: MenuBarOverflowController.OverflowItem
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(nsImage: item.icon).resizable().scaledToFit().frame(width: 28, height: 28)
                Text(item.name).font(.system(size: 11)).lineLimit(1)
            }
            .frame(maxWidth: .infinity).frame(height: 66)
            .background(hovered ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(item.name)
        .accessibilityLabel(item.name)
    }
}
