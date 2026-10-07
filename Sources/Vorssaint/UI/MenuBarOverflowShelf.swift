// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import SwiftUI
import ApplicationServices

/// One compact dropdown: every chosen status icon lives in the same grid.
struct MenuBarOverflowShelf: View {
    @ObservedObject var controller: MenuBarOverflowController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Other").font(.headline)
                Spacer()
                Button { controller.chooseIcons() } label: {
                    Image(systemName: "gearshape").frame(width: 24, height: 24)
                }
                .buttonStyle(.plain).help("Choose icons")
                .accessibilityLabel("Choose icons for Other")
            }
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
                            OtherShelfIcon(item: item) { controller.open(item) }
                        }
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "ellipsis.circle").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text("Your less-used icons go here.").font(.caption).foregroundStyle(.secondary)
                    Button("Choose icons…") { controller.chooseIcons() }
                }.frame(maxWidth: .infinity)
            }
            if let message = controller.message, AXIsProcessTrusted() {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
    }
}

private struct OtherShelfIcon: View {
    let item: MenuBarOverflowController.ShelfItem
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(nsImage: item.icon).resizable().scaledToFit().frame(width: 28, height: 28)
                Text(item.name).font(.system(size: 9)).lineLimit(1)
            }
            .frame(maxWidth: .infinity).frame(height: 58)
            .background(hovered ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(item.name)
        .accessibilityLabel(item.name)
    }
}
