import Darwin
import Foundation

/// Mirrors the green/yellow/red gauge at the bottom of Activity Monitor's
/// Memory tab — sourced from the same place it is: the kernel's own verdict
/// on whether it's under memory pressure, not a guess derived from the
/// used/total ratio (which stays high on macOS by design, since it uses
/// spare RAM for disk cache rather than leaving it idle).
enum MemoryPressureLevel: Int {
    case normal = 1
    case warning = 2
    case critical = 4
}

struct ProcessUsage: Identifiable, Equatable {
    let id: Int32
    let name: String
    let cpuPercent: Double
    let memDisplay: String
}

struct NetProcessUsage: Identifiable, Equatable {
    let id: Int32
    let name: String
    let downRate: Double // bytes/sec
    let upRate: Double
}

struct MemProcessUsage: Identifiable, Equatable {
    let id: Int32
    let name: String
    let memDisplay: String
    let memBytes: Int64
}

/// Sampling logic, kept free of shared mutable state so it can run freely off
/// the main actor inside a background loop.
///
/// There is no public, stable way to read Apple Silicon GPU load or CPU
/// temperature (the private `IOReport.framework` that tools like Stats use
/// for this is not present on this machine's macOS build at all — checked
/// directly with `dlopen`, it is not in the dyld shared cache under that
/// path). Rather than bolt on a fragile, version-specific reverse-engineered
/// API, everything here is read from `top`/`nettop`: public, shipped
/// commands, stable across macOS versions, and — for `nettop` — the same
/// per-process network accounting Activity Monitor's Network tab itself is
/// built on.
enum SystemStatsSampler {

    struct CPUSample {
        var user = 0.0
        var system = 0.0
        var idle = 100.0
        var memUsedBytes: Int64 = 0
        var processes: [ProcessUsage] = []
    }

    struct NetSnapshotEntry {
        var name: String
        var inBytes: Double
        var outBytes: Double
    }

    struct NetResult {
        var upRate = 0.0
        var downRate = 0.0
        var top: [NetProcessUsage] = []
        var snapshot: [Int32: NetSnapshotEntry] = [:]
    }

    private static func run(_ path: String, _ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Two samples one second apart: `top`'s %CPU is a rate, and a single
    /// instantaneous sample reads as flat zero for almost everything.
    static func sampleTop(processCount: Int = 8) -> CPUSample {
        let output = run("/usr/bin/top", ["-l", "2", "-s", "1", "-o", "cpu", "-n", "\(processCount)", "-stats", "pid,command,cpu,mem"])
        var result = CPUSample()

        // Take the final "CPU usage:" / "PhysMem:" / process block — the
        // second sample, the only one with a real rate behind it.
        guard let lastBlockStart = output.range(of: "CPU usage:", options: .backwards) else {
            return result
        }
        let block = output[lastBlockStart.lowerBound...]

        if let match = firstMatch(in: String(block), pattern: #"CPU usage:\s*([\d.]+)% user,\s*([\d.]+)% sys,\s*([\d.]+)% idle"#) {
            result.user = Double(match[1]) ?? 0
            result.system = Double(match[2]) ?? 0
            result.idle = Double(match[3]) ?? 100
        }

        if let match = firstMatch(in: String(block), pattern: #"PhysMem:\s*([\d.]+)([GMK])\s*used"#) {
            let value = Double(match[1]) ?? 0
            result.memUsedBytes = Int64(value * unitMultiplier(match[2]))
        }

        if let pidRange = block.range(of: "PID") {
            let rows = block[pidRange.upperBound...]
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for row in rows {
                let parts = row.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard parts.count >= 4, let pid = Int32(parts[0]), let cpu = Double(parts[parts.count - 2]) else { continue }
                var mem = parts[parts.count - 1]
                if let last = mem.last, last == "+" || last == "-" { mem.removeLast() }
                let name = parts[1..<(parts.count - 2)].joined(separator: " ")
                result.processes.append(ProcessUsage(id: pid, name: name, cpuPercent: cpu, memDisplay: mem))
            }
        }

        return result
    }

    /// Memory doesn't need a rate, so a single instantaneous sample is enough
    /// — unlike `sampleTop()`, no second sample a second later.
    static func sampleTopByMemory(processCount: Int = 8) -> [MemProcessUsage] {
        let output = run("/usr/bin/top", ["-l", "1", "-o", "mem", "-n", "\(processCount)", "-stats", "pid,command,mem"])
        var results: [MemProcessUsage] = []
        guard let pidRange = output.range(of: "PID") else { return results }
        let rows = output[pidRange.upperBound...]
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for row in rows {
            let parts = row.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2, let pid = Int32(parts[0]) else { continue }
            var mem = parts[parts.count - 1]
            if let last = mem.last, last == "+" || last == "-" { mem.removeLast() }
            let name = parts[1..<(parts.count - 1)].joined(separator: " ")
            results.append(MemProcessUsage(id: pid, name: name, memDisplay: mem, memBytes: parseMemBytes(mem)))
        }
        return results
    }

    /// `nettop`'s byte counters are cumulative since each process started, not
    /// a rate — the caller supplies the previous snapshot so a delta can be
    /// taken here.
    static func sampleNettop(previous: [Int32: NetSnapshotEntry], previousTime: Date, topCount: Int = 5) -> NetResult {
        var result = NetResult()
        let now = Date()
        let elapsed = max(now.timeIntervalSince(previousTime), 0.001)

        let output = run("/usr/bin/nettop", ["-P", "-x", "-l", "1", "-J", "bytes_in,bytes_out"])
        var current: [Int32: NetSnapshotEntry] = [:]
        var rates: [NetProcessUsage] = []

        for line in output.split(separator: "\n").dropFirst() {
            guard let match = firstMatch(in: String(line), pattern: #"^(.+)\.(\d+)\s+(\d+)\s+(\d+)\s*$"#) else { continue }
            let name = match[1].trimmingCharacters(in: .whitespaces)
            guard let pid = Int32(match[2]), let inBytes = Double(match[3]), let outBytes = Double(match[4]) else { continue }
            current[pid] = NetSnapshotEntry(name: name, inBytes: inBytes, outBytes: outBytes)

            if let prior = previous[pid] {
                let down = max(inBytes - prior.inBytes, 0) / elapsed
                let up = max(outBytes - prior.outBytes, 0) / elapsed
                result.downRate += down
                result.upRate += up
                if down + up > 1 {
                    rates.append(NetProcessUsage(id: pid, name: name, downRate: down, upRate: up))
                }
            }
        }

        result.snapshot = current
        result.top = Array(rates.sorted { ($0.downRate + $0.upRate) > ($1.downRate + $1.upRate) }.prefix(topCount))
        return result
    }

    static func sampleMemoryPressure() -> MemoryPressureLevel {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0)
        guard result == 0 else { return .normal }
        return MemoryPressureLevel(rawValue: Int(value)) ?? .normal
    }

    private static func unitMultiplier(_ unit: String) -> Double {
        switch unit {
        case "G": return 1_073_741_824
        case "M": return 1_048_576
        case "K": return 1_024
        default: return 1
        }
    }

    private static func parseMemBytes(_ text: String) -> Int64 {
        guard let match = firstMatch(in: text, pattern: #"^([\d.]+)([KMGT]?)$"#) else { return 0 }
        let value = Double(match[1]) ?? 0
        let multiplier: Double
        switch match[2] {
        case "T": multiplier = 1_099_511_627_776
        case "G": multiplier = 1_073_741_824
        case "M": multiplier = 1_048_576
        case "K": multiplier = 1_024
        default: multiplier = 1
        }
        return Int64(value * multiplier)
    }

    private static func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let result = regex.firstMatch(in: text, range: range) else { return nil }
        var groups: [String] = []
        for i in 0..<result.numberOfRanges {
            guard let r = Range(result.range(at: i), in: text) else { groups.append(""); continue }
            groups.append(String(text[r]))
        }
        return groups
    }
}

@MainActor
final class SystemStatsMonitor: ObservableObject {
    @Published private(set) var cpuUser = 0.0
    @Published private(set) var cpuSystem = 0.0
    @Published private(set) var cpuIdle = 100.0
    @Published private(set) var memUsedBytes: Int64 = 0
    @Published private(set) var memoryPressure: MemoryPressureLevel = .normal
    let memTotalBytes: Int64 = Int64(ProcessInfo.processInfo.physicalMemory)
    @Published private(set) var netUpRate = 0.0
    @Published private(set) var netDownRate = 0.0
    @Published private(set) var topProcesses: [ProcessUsage] = []
    @Published private(set) var topMemProcesses: [MemProcessUsage] = []
    @Published private(set) var topNetProcesses: [NetProcessUsage] = []

    private var loop: Task<Void, Never>?

    func start() {
        guard loop == nil else { return }
        loop = Task.detached(priority: .utility) { [weak self] in
            var lastNet: [Int32: SystemStatsSampler.NetSnapshotEntry] = [:]
            var lastNetTime = Date()
            while let self, !Task.isCancelled {
                let cpu = SystemStatsSampler.sampleTop()
                let mem = SystemStatsSampler.sampleTopByMemory()
                let pressure = SystemStatsSampler.sampleMemoryPressure()
                let net = SystemStatsSampler.sampleNettop(previous: lastNet, previousTime: lastNetTime)
                lastNet = net.snapshot
                lastNetTime = Date()

                await MainActor.run {
                    self.cpuUser = cpu.user
                    self.cpuSystem = cpu.system
                    self.cpuIdle = cpu.idle
                    self.memUsedBytes = cpu.memUsedBytes
                    self.memoryPressure = pressure
                    self.topProcesses = cpu.processes
                    self.topMemProcesses = mem
                    self.netUpRate = net.upRate
                    self.netDownRate = net.downRate
                    self.topNetProcesses = net.top
                }

                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }
}
