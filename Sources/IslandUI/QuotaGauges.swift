import Foundation
import IslandStore
import SwiftUI

/// Presentation model of one global Quotas gauge (5 h or 7 d window) at the
/// foot of the Extended Island. Pure data + formatting: the SwiftUI layer
/// only lays it out. Gauges only exist for windows the statusline actually
/// reported — an absent window yields no gauge, never a misleading zero.
struct QuotaGauge: Identifiable, Equatable {
    let id: String
    /// French window label ("5 h" / "7 j").
    let windowLabel: String
    /// Rounded percent label ("24 %").
    let percentLabel: String
    /// Gauge fill, clamped to 0…1.
    let fraction: Double
    /// Local reset time ("↺ 17:00"), when known (5 h window).
    let resetLabel: String?

    /// One gauge per reported window, 5 h first.
    static func gauges(for quotas: Quotas) -> [QuotaGauge] {
        var gauges: [QuotaGauge] = []
        if let fiveHour = quotas.fiveHour {
            gauges.append(gauge(id: "five-hour", label: "5 h", window: fiveHour))
        }
        if let sevenDay = quotas.sevenDay {
            gauges.append(gauge(id: "seven-day", label: "7 j", window: sevenDay))
        }
        return gauges
    }

    private static func gauge(id: String, label: String, window: RateLimitWindow) -> QuotaGauge {
        QuotaGauge(
            id: id,
            windowLabel: label,
            percentLabel: "\(Int(window.usedPercentage.rounded())) %",
            fraction: min(1, max(0, window.usedPercentage / 100)),
            resetLabel: window.resetsAt.map { "↺ " + Self.timeFormatter.string(from: $0) }
        )
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

/// Global Quotas gauges at the foot of the Extended panel. Only shown when
/// the statusline reported rate limits (issue #9): before the first API
/// call, the section simply does not exist.
struct QuotaGaugesView: View {
    let gauges: [QuotaGauge]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(gauges) { gauge in
                HStack(spacing: 8) {
                    Text(gauge.windowLabel)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, alignment: .leading)
                    ProgressView(value: gauge.fraction)
                        .progressViewStyle(.linear)
                        .tint(Self.tint(for: gauge.fraction))
                    Text(gauge.percentLabel)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                    if let reset = gauge.resetLabel {
                        Text(reset)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.cyan)
                    }
                }
            }
        }
        .padding(.top, 6)
        .overlay(alignment: .top) {
            Divider().background(.white.opacity(0.15))
        }
    }

    static func tint(for fraction: Double) -> Color {
        switch fraction {
        case ..<0.4: .green
        case ..<0.75: .yellow
        default: .red
        }
    }
}
