import SwiftUI

struct QuickActionsPane: View {
    @ObservedObject var store: ShortcutsStore
    @ObservedObject var privacy: PrivacyMode
    @State private var justRan: String?

    var body: some View {
        PrivacyCover(hidden: privacy.hides(.quickActions, "quickActions"), onReveal: { privacy.toggle("quickActions") }) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        StatsUI.header("Quick Actions")
                        Spacer()
                        addMenu
                    }

                    if store.selected.isEmpty {
                        Text(localized("Add a shortcut to get started"))
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    } else {
                        VStack(spacing: 3) {
                            ForEach(store.selected, id: \.self) { name in
                                actionRow(name)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(.top, 2)
        }
    }

    private var addMenu: some View {
        Menu {
            let addable = store.available.filter { !store.selected.contains($0) }
            if addable.isEmpty {
                Text(localized("No more shortcuts"))
            } else {
                ForEach(addable, id: \.self) { name in
                    Button(name) { store.add(name) }
                }
            }
            Divider()
            Button(localized("Refresh List")) { store.refreshAvailable() }
        } label: {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(Theme.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 20)
    }

    private func actionRow(_ name: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: justRan == name ? "checkmark" : "bolt.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(justRan == name ? Color.green : Theme.tertiary)
                .frame(width: 14)

            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)

            Spacer(minLength: 6)

            Button {
                store.remove(name)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.surface)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            store.run(name)
            justRan = name
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if justRan == name { justRan = nil }
            }
        }
    }
}
