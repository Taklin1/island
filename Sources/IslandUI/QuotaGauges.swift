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

    /// Threshold colour of the gauge fill: green < 40 %, yellow < 75 %, red
    /// otherwise. Exposed on the model so the bar is drawn with an explicit
    /// `Color` (a filled shape) rather than a system-control `tint` — the
    /// Extended panel is a non-activating `NSPanel` that never becomes key, so
    /// its material vibrancy would desaturate a control tint until the panel is
    /// clicked (issue #116). An explicit `Color` on a shape is immune to that.
    var thresholdColor: Color {
        switch fraction {
        case ..<0.4: .green
        case ..<0.75: .yellow
        default: .red
        }
    }

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
                    QuotaGaugeBar(fraction: gauge.fraction, color: gauge.thresholdColor)
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
}

/// A gauge bar drawn from explicit shapes: a translucent white track with a
/// `color`-filled capsule clamped to `fraction`. Unlike a `ProgressView`'s
/// `tint`, an explicit `Color` on a filled shape keeps its saturation on the
/// non-activating Extended panel, so threshold colours show immediately
/// without a click (issue #116).
private struct QuotaGaugeBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, proxy.size.width * fraction))
            }
        }
        .frame(height: 4)
    }
}
