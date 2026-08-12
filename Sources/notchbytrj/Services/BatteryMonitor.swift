import Foundation
import IOKit.ps

struct BatteryInfo {
    var percentage: Int
    var isCharging: Bool
    var isPluggedIn: Bool
    var timeToEmptyMinutes: Int?
    var timeToFullMinutes: Int?
}

/// The Mac's own battery, via the standard documented Power Sources API —
/// no ambiguity here, unlike the Bluetooth accessory battery readings next
/// to it in the same tab.
enum BatteryMonitor {
    static func read() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any]
        else {
            return nil
        }

        let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
        let percentage = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
        let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
        let powerState = description[kIOPSPowerSourceStateKey] as? String
        let isPluggedIn = powerState == kIOPSACPowerValue

        let timeToEmpty = description[kIOPSTimeToEmptyKey] as? Int
        let timeToFull = description[kIOPSTimeToFullChargeKey] as? Int

        return BatteryInfo(
            percentage: percentage,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            timeToEmptyMinutes: (timeToEmpty ?? -1) >= 0 ? timeToEmpty : nil,
            timeToFullMinutes: (timeToFull ?? -1) >= 0 ? timeToFull : nil
        )
    }
}

@MainActor
final class PowerMonitor: ObservableObject {
    @Published private(set) var battery: BatteryInfo?
    @Published private(set) var bluetoothDevices: [BluetoothDeviceInfo] = []

    private var loop: Task<Void, Never>?

    func start() {
        guard loop == nil else { return }
        loop = Task.detached(priority: .utility) { [weak self] in
            // A read that comes back empty this one tick — a hiccup talking
            // to bluetoothd, not the accessory actually losing its charge —
            // used to flash the gauge to 0% and red before the next good
            // sample arrived. Keeping the last real reading per device until
            // a new one replaces it rides out that kind of blip instead of
            // reporting it as data.
            var lastKnownBattery: [String: Int] = [:]
            while let self, !Task.isCancelled {
                let battery = BatteryMonitor.read()
                let devices = BluetoothMonitor.pairedDevices().map { device -> BluetoothDeviceInfo in
                    if let percent = device.batteryPercent {
                        lastKnownBattery[device.id] = percent
                        return device
                    } else if device.isConnected, let cached = lastKnownBattery[device.id] {
                        return BluetoothDeviceInfo(
                            id: device.id, name: device.name, isConnected: device.isConnected,
                            batteryPercent: cached, symbol: device.symbol
                        )
                    }
                    return device
                }
                await MainActor.run {
                    self.battery = battery
                    self.bluetoothDevices = devices
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }
}
