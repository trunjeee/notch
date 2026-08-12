import SwiftUI

struct ReminderPane: View {
    @ObservedObject var reminders: ReminderStore
    @ObservedObject var privacy: PrivacyMode

    var body: some View {
        VStack(spacing: 0) {
            switch reminders.access {
            case .notRequested, .denied:
                permissionPrompt
            case .granted:
                content
            }
        }
        .padding(.top, 2)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                StatsUI.header("Reminders")
                Spacer()
                listPicker
            }
            .padding(.horizontal, 2)

            if reminders.items.isEmpty {
                Text(localized("Nothing due"))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 3) {
                        ForEach(reminders.items) { item in
                            ReminderRow(item: item, reminders: reminders, privacy: privacy)
                        }
                    }
                }
            }
        }
    }

    private var listPicker: some View {
        let selected = ReminderStore.selectedListIdentifiers
        return Menu {
            Button {
                reminders.setSelectedLists([])
            } label: {
                Label(localized("All Lists"), systemImage: selected.isEmpty ? "checkmark" : "")
            }
            Divider()
            ForEach(reminders.lists, id: \.calendarIdentifier) { list in
                Button {
                    var next = selected
                    if next.contains(list.calendarIdentifier) {
                        next.remove(list.calendarIdentifier)
                    } else {
                        next.insert(list.calendarIdentifier)
                    }
                    reminders.setSelectedLists(next)
                } label: {
                    Label(list.title, systemImage: selected.contains(list.calendarIdentifier) ? "checkmark" : "")
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(Theme.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 20)
    }

    private var permissionPrompt: some View {
        VStack(spacing: 9) {
            Image(systemName: "checklist")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.tertiary)
            Text(localized("See what's due"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondary)
            Text(localized("notchbytrj needs access to Reminders to show this tab."))
                .font(.system(size: 10))
                .foregroundStyle(Theme.tertiary)
                .multilineTextAlignment(.center)
            Button {
                reminders.requestAccess()
            } label: {
                Text(localized("Allow"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.surfaceHover))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }
}

private struct ReminderRow: View {
    let item: ReminderStore.Item
    @ObservedObject var reminders: ReminderStore
    @ObservedObject var privacy: PrivacyMode
    @State private var hovering = false

    private var hidden: Bool { privacy.hides(.reminders, item.id) }

    var body: some View {
        HStack(spacing: 9) {
            Button {
                reminders.complete(item)
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(nsColor: item.listColor))
            }
            .buttonStyle(.plain)

            SpoilerText(
                text: item.title,
                hidden: hidden,
                seed: UInt64(bitPattern: Int64(item.id.hashValue))
            )

            Spacer(minLength: 6)

            if hovering, privacy.covers(.reminders) {
                RevealEye(hidden: hidden) { privacy.toggle(item.id) }
            }

            if let due = item.dueDate {
                Text(due, style: .date)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hovering ? Theme.surfaceHover : Theme.surface)
        )
        .onHover { hovering = $0 }
    }
}
