import SwiftUI

/// Shared building blocks for `SystemStatsPane` and `NetworkPane`.
enum StatsUI {
    static func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(Theme.tertiary)
    }

    static func legend(_ label: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(label) \(Int(value.rounded()))%")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.secondary)
        }
    }

    static func usageBar(segments: [(Double, Color)], remainderColor: Color) -> some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    let (value, color) = segment
                    Rectangle()
                        .fill(color)
                        .frame(width: geo.size.width * max(min(value / 100, 1), 0))
                }
            }
            .frame(width: geo.size.width, height: 6, alignment: .leading)
            .background(remainderColor)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .frame(height: 6)
    }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }

    static func formatRate(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .binary) + "/s"
    }
}

/// Covers a whole tab's content behind a fixed message rather than the
/// per-row dust pattern `SpoilerText` draws — these tabs are numbers and
/// gauges, not lines of text, so there is no natural "row" to seed dust
/// against. One reveal for the whole thing is what Calendar already does
/// for the same reason.
struct PrivacyCover<Content: View>: View {
    let hidden: Bool
    let onReveal: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            content()
                .opacity(hidden ? 0 : 1)
                .allowsHitTesting(!hidden)
            if hidden {
                VStack(spacing: 8) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Theme.tertiary)
                    Button(action: onReveal) {
                        Text(localized("Show"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Theme.surfaceHover))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct ProcessRow: View {
    let name: String
    let value: String
    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            Text(detail)
                .font(.system(size: 9, weight: .regular).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
            Text(value)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.secondary)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 9)
        .frame(height: 20)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.surface)
        )
    }
}
