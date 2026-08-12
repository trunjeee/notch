import SwiftUI

struct NetworkPane: View {
    @ObservedObject var stats: SystemStatsMonitor
    @ObservedObject var privacy: PrivacyMode

    var body: some View {
        PrivacyCover(hidden: privacy.hides(.network, "network"), onReveal: { privacy.toggle("network") }) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    speedSection
                    topAppsSection
                }
                .padding(.vertical, 4)
            }
            .padding(.top, 2)
        }
    }

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatsUI.header("Network")
            HStack(spacing: 14) {
                Label(StatsUI.formatRate(stats.netDownRate), systemImage: "arrow.down")
                    .foregroundStyle(Color.blue)
                Label(StatsUI.formatRate(stats.netUpRate), systemImage: "arrow.up")
                    .foregroundStyle(Color.red)
            }
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
        }
    }

    private var topAppsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatsUI.header("Top Apps")
            if stats.topNetProcesses.isEmpty {
                Text(localized("No active traffic"))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Theme.tertiary)
            } else {
                VStack(spacing: 3) {
                    ForEach(stats.topNetProcesses) { proc in
                        ProcessRow(
                            name: proc.name,
                            value: StatsUI.formatRate(proc.downRate),
                            detail: StatsUI.formatRate(proc.upRate)
                        )
                    }
                }
            }
        }
    }
}
