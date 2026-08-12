import AppKit
import EventKit

/// Open reminders, from one list, several, or all of them. Access is
/// requested only from the tab's own button — the same rule the calendar
/// tab follows.
@MainActor
final class ReminderStore: ObservableObject {
    enum Access {
        case notRequested
        case granted
        case denied
    }

    struct Item: Identifiable {
        let id: String
        let title: String
        let dueDate: Date?
        let listColor: NSColor
        let reminder: EKReminder
    }

    @Published private(set) var access: Access = .notRequested
    @Published private(set) var items: [Item] = []
    @Published private(set) var lists: [EKCalendar] = []

    private let store = EKEventStore()
    private var observer: Any?

    private static let selectedListsKey = "reminderSelectedListIdentifiers"

    /// Empty means "all lists" — the default, and the state a freshly
    /// deleted list falls back to instead of silently vanishing.
    static var selectedListIdentifiers: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: selectedListsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: selectedListsKey) }
    }

    func start() {
        access = Self.currentAccess()
        guard access == .granted else { return }
        observe()
        loadLists()
        reload()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    func refreshAccess() {
        access = Self.currentAccess()
        guard access == .granted else { return }
        observe()
        loadLists()
        reload()
    }

    func requestAccess() {
        guard Self.currentAccess() == .notRequested else {
            refreshAccess()
            return
        }
        store.requestFullAccessToReminders { [weak self] granted, _ in
            Task { @MainActor in
                guard let self else { return }
                self.access = granted ? .granted : .denied
                guard granted else { return }
                self.observe()
                self.loadLists()
                self.reload()
            }
        }
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return .granted
        case .notDetermined: return .notRequested
        default: return .denied
        }
    }

    private func observe() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.loadLists()
                self?.reload()
            }
        }
    }

    private func loadLists() {
        lists = store.calendars(for: .reminder)
    }

    private func activeCalendars() -> [EKCalendar] {
        let selected = Self.selectedListIdentifiers
        guard !selected.isEmpty else { return lists }
        let matched = lists.filter { selected.contains($0.calendarIdentifier) }
        return matched.isEmpty ? lists : matched
    }

    func setSelectedLists(_ identifiers: Set<String>) {
        Self.selectedListIdentifiers = identifiers
        reload()
    }

    func reload() {
        guard access == .granted else { return }
        let calendars = activeCalendars()
        guard !calendars.isEmpty else {
            items = []
            return
        }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            Task { @MainActor in
                guard let self else { return }
                self.items = (reminders ?? [])
                    .sorted { ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture) }
                    .map { reminder in
                        Item(
                            id: reminder.calendarItemIdentifier,
                            title: reminder.title ?? localized("Untitled"),
                            dueDate: reminder.dueDateComponents?.date,
                            listColor: reminder.calendar.color ?? .systemGray,
                            reminder: reminder
                        )
                    }
            }
        }
    }

    func complete(_ item: Item) {
        item.reminder.isCompleted = true
        try? store.save(item.reminder, commit: true)
        items.removeAll { $0.id == item.id }
    }

    func openRemindersApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Reminders.app"))
    }
}
