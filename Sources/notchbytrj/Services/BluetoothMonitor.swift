import IOBluetooth
import ObjectiveC

struct BluetoothDeviceInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let isConnected: Bool
    let batteryPercent: Int?
    let symbol: String
}

/// Battery level for a Bluetooth accessory (AirPods, mice, keyboards, ...)
/// has no public API — `IOBluetoothDevice` carries a handful of
/// undocumented battery selectors that Apple's own Bluetooth menu reads
/// internally. Calling an unknown selector blind is how you crash a
/// process: if the real method returns a primitive (`int`) rather than an
/// object, going through `perform(_:)` — which assumes an object return —
/// is undefined behavior. So every selector found here is checked against
/// its actual Objective-C type encoding first, and dispatched through the
/// matching call path (object vs. primitive) rather than assumed.
enum BluetoothMonitor {
    private static let batterySelectorNames = [
        "batteryPercentSingle",
        "batteryPercentCombined",
        "batteryPercentLeft",
        "batteryPercentRight",
        "batteryPercentCase",
        "headsetBattery", // generic (non-Apple) Bluetooth headset battery, via HFP
    ]

    static func pairedDevices() -> [BluetoothDeviceInfo] {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        return devices.map { device in
            BluetoothDeviceInfo(
                id: device.addressString ?? device.name ?? UUID().uuidString,
                name: device.name ?? "?",
                isConnected: device.isConnected(),
                batteryPercent: device.isConnected() ? batteryPercent(for: device) : nil,
                symbol: symbol(for: device)
            )
        }
    }

    /// Bluetooth's own Class of Device field, not the device's (possibly
    /// non-Latin, possibly blank) name — public, documented, no crash risk.
    /// Major class sits in bits 8–12, minor class in bits 2–7 of the 24-bit
    /// field (Bluetooth Core Spec, Assigned Numbers §2.8).
    private static func symbol(for device: IOBluetoothDevice) -> String {
        let classOfDevice = device.classOfDevice
        let major = (classOfDevice >> 8) & 0x1F
        let minor = (classOfDevice >> 2) & 0x3F

        switch major {
        case 0x04: // Audio/Video
            switch minor {
            case 5, 8, 10: return "hifispeaker.fill" // loudspeaker / car audio / hi-fi
            default: return "headphones" // headset, handsfree, headphones, portable audio, ...
            }
        case 0x05: // Peripheral — minor bits 6-7 flag keyboard/pointer
            let hasKeyboard = (minor & 0x30) == 0x10 || (minor & 0x30) == 0x30
            let hasPointer = (minor & 0x30) == 0x20 || (minor & 0x30) == 0x30
            if hasKeyboard, hasPointer { return "keyboard.fill" }
            if hasKeyboard { return "keyboard.fill" }
            if hasPointer { return "computermouse.fill" }
            return "gamecontroller.fill"
        case 0x01: return "desktopcomputer" // Computer
        case 0x02: return "phone.fill" // Phone
        case 0x07: return "applewatch" // Wearable
        default: return "antenna.radiowaves.left.and.right"
        }
    }

    private static func debugLog(_ message: String) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("notchbytrj", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("bluetooth-debug.log")
        let line = "\(Date()): \(message)\n"
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    private static func batteryPercent(for device: IOBluetoothDevice) -> Int? {
        guard let cls = object_getClass(device) else { return nil }

        // Methods can live on a superclass rather than on the exact class
        // `object_getClass` returns — `class_copyMethodList` only reports
        // what's declared directly on the class it's given, so the search
        // has to walk up the hierarchy to see everything the instance
        // actually responds to.
        var found: [String] = []
        var walkClass: AnyClass? = cls
        while let current = walkClass {
            var methodCount: UInt32 = 0
            if let methods = class_copyMethodList(current, &methodCount) {
                for i in 0..<Int(methodCount) {
                    let name = NSStringFromSelector(method_getName(methods[i]))
                    if name.lowercased().contains("battery") { found.append("\(NSStringFromClass(current)).\(name)") }
                }
                free(methods)
            }
            walkClass = class_getSuperclass(current)
        }
        debugLog("battery-like selectors on \(device.name ?? "?"): \(found)")

        for name in batterySelectorNames {
            let selector = NSSelectorFromString(name)
            guard device.responds(to: selector),
                  let method = class_getInstanceMethod(cls, selector),
                  let encoding = method_getTypeEncoding(method)
            else { continue }

            let value = invoke(device, selector, returnEncoding: String(cString: encoding))
            debugLog("\(name) -> \(String(describing: value)) (encoding: \(String(cString: encoding)))")
            guard let value, value >= 0 else { continue }
            return value
        }
        return nil
    }

    /// The type encoding's first character is the return type. Each width
    /// is read through a C function pointer declared with that *exact*
    /// return type — on arm64 the upper bits of the return register are
    /// unspecified for anything narrower than 64 bits, so reading a `char`
    /// return through a function pointer typed as `Int` can pick up
    /// garbage in the bits above it. Declaring the correct width lets the
    /// calling convention handle the extension correctly instead of
    /// guessing at it.
    private static func invoke(_ device: IOBluetoothDevice, _ selector: Selector, returnEncoding: String) -> Int? {
        guard let first = returnEncoding.first,
              let method = class_getInstanceMethod(object_getClass(device)!, selector)
        else { return nil }
        let imp = method_getImplementation(method)

        switch first {
        case "@":
            typealias ObjectGetter = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
            guard let result = unsafeBitCast(imp, to: ObjectGetter.self)(device, selector)?.takeUnretainedValue() as? NSNumber else { return nil }
            return result.intValue
        case "c":
            typealias Getter = @convention(c) (AnyObject, Selector) -> Int8
            return Int(unsafeBitCast(imp, to: Getter.self)(device, selector))
        case "C":
            typealias Getter = @convention(c) (AnyObject, Selector) -> UInt8
            return Int(unsafeBitCast(imp, to: Getter.self)(device, selector))
        case "s":
            typealias Getter = @convention(c) (AnyObject, Selector) -> Int16
            return Int(unsafeBitCast(imp, to: Getter.self)(device, selector))
        case "S":
            typealias Getter = @convention(c) (AnyObject, Selector) -> UInt16
            return Int(unsafeBitCast(imp, to: Getter.self)(device, selector))
        case "i":
            typealias Getter = @convention(c) (AnyObject, Selector) -> Int32
            return Int(unsafeBitCast(imp, to: Getter.self)(device, selector))
        case "I":
            typealias Getter = @convention(c) (AnyObject, Selector) -> UInt32
            return Int(unsafeBitCast(imp, to: Getter.self)(device, selector))
        case "l", "q":
            typealias Getter = @convention(c) (AnyObject, Selector) -> Int64
            return Int(unsafeBitCast(imp, to: Getter.self)(device, selector))
        case "L", "Q":
            typealias Getter = @convention(c) (AnyObject, Selector) -> UInt64
            return Int(unsafeBitCast(imp, to: Getter.self)(device, selector))
        default:
            return nil
        }
    }
}
