import SwiftUI

struct SystemStatsPane: View {
    @ObservedObject var stats: SystemStatsMonitor
    @ObservedObject var privacy: PrivacyMode

    var body: some View {
        PrivacyCover(hidden: privacy.hides(.systemStats, "systemStats"), onReveal: { privacy.toggle("systemStats") }) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    cpuSection
                    memorySection
                }
                .padding(.vertical, 4)
            }
            .padding(.top, 2)
        }
    }

    private var cpuSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatsUI.header("CPU")
            StatsUI.usageBar(
                segments: [
                    (stats.cpuUser, Color.blue),
                    (stats.cpuSystem, Color.red),
                ],
                remainderColor: Theme.surface
            )
            HStack(spacing: 10) {
                StatsUI.legend("User", stats.cpuUser, .blue)
                StatsUI.legend("Sys", stats.cpuSystem, .red)
                StatsUI.legend("Idle", stats.cpuIdle, Theme.tertiary)
            }
            if !stats.topProcesses.isEmpty {
                VStack(spacing: 3) {
                    ForEach(stats.topProcesses.prefix(5)) { proc in
                        ProcessRow(name: proc.name, value: String(format: "%.1f%%", proc.cpuPercent), detail: proc.memDisplay)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                StatsUI.header("Memory")
                Spacer()
                memoryPressureBadge
            }
            let fraction = stats.memTotalBytes > 0 ? Double(stats.memUsedBytes) / Double(stats.memTotalBytes) : 0
            StatsUI.usageBar(segments: [(fraction * 100, Color.purple)], remainderColor: Theme.surface)
            Text("\(StatsUI.formatBytes(stats.memUsedBytes)) / \(StatsUI.formatBytes(stats.memTotalBytes))")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.secondary)
            if !stats.topMemProcesses.isEmpty {
                VStack(spacing: 3) {
                    ForEach(stats.topMemProcesses.prefix(5)) { proc in
                        ProcessRow(name: proc.name, value: proc.memDisplay, detail: "")
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private var memoryPressureBadge: some View {
        let (color, label): (Color, String) = {
            switch stats.memoryPressure {
            case .normal: return (.green, localized("Normal"))
            case .warning: return (.yellow, localized("Warning"))
            case .critical: return (.red, localized("Critical"))
            }
        }()
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.secondary)
        }
    }
}
