import SwiftUI

struct PowerPane: View {
    @ObservedObject var power: PowerMonitor
    @ObservedObject var privacy: PrivacyMode

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        PrivacyCover(hidden: privacy.hides(.power, "power"), onReveal: { privacy.toggle("power") }) {
            HStack(alignment: .top, spacing: 14) {
                macColumn
                Divider().frame(maxHeight: .infinity)
                bluetoothColumn
            }
            .padding(.top, 10)
        }
    }

    private var macColumn: some View {
        VStack(spacing: 6) {
            if let battery = power.battery {
                CircularGauge(
                    percentage: battery.percentage,
                    symbol: "laptopcomputer",
                    color: batteryColor(battery.percentage)
                )
                Text("\(battery.percentage)%")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                Text(statusText(battery))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            } else {
                CircularGauge(percentage: 0, symbol: "laptopcomputer", color: Theme.tertiary)
                Text(localized("No data"))
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .frame(width: 84)
    }

    private var bluetoothColumn: some View {
        let connected = power.bluetoothDevices.filter { $0.isConnected }
        return ScrollView(showsIndicators: false) {
            if connected.isEmpty {
                Text(localized("No connected devices"))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(connected) { device in
                        VStack(spacing: 4) {
                            CircularGauge(
                                percentage: device.batteryPercent ?? 0,
                                symbol: device.symbol,
                                color: device.batteryPercent.map(batteryColor) ?? Theme.tertiary
                            )
                            Text(device.name)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(device.batteryPercent.map { "\($0)%" } ?? "—")
                                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func symbol(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("pods") || lower.contains("buds") || lower.contains("headphone") || lower.contains("headset") {
            return "headphones"
        }
        if lower.contains("mouse") { return "computermouse.fill" }
        if lower.contains("keyboard") || lower.contains("kb") { return "keyboard.fill" }
        if lower.contains("trackpad") { return "rectangle.fill" }
        return "antenna.radiowaves.left.and.right"
    }

    private func batteryColor(_ percentage: Int) -> Color {
        switch percentage {
        case ..<20: return .red
        case ..<40: return .yellow
        default: return .green
        }
    }

    private func statusText(_ battery: BatteryInfo) -> String {
        if battery.isCharging, let minutes = battery.timeToFullMinutes, minutes > 0 {
            return localized("%@ to full", formatMinutes(minutes))
        }
        if battery.isCharging { return localized("Charging") }
        if let minutes = battery.timeToEmptyMinutes, minutes > 0 {
            return localized("%@ left", formatMinutes(minutes))
        }
        return battery.isPluggedIn ? localized("Plugged in") : localized("On battery")
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
    }
}

private struct CircularGauge: View {
    let percentage: Int
    let symbol: String
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.surface, lineWidth: 4)
                .padding(3)
            Circle()
                .trim(from: 0, to: max(min(Double(percentage) / 100, 1), 0.02))
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .padding(3)
                .rotationEffect(.degrees(-90))
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(width: 52, height: 52)
        .animation(Theme.contentAnimation, value: percentage)
    }
}
