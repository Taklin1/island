#include "quota_view.h"

#include <cstdio>

namespace totem {

namespace {

GaugeView gaugeFor(const QuotaWindow& window) {
    GaugeView gauge;
    if (!window.present) return gauge;
    gauge.present = true;
    gauge.percent = window.usedPercentage;
    // MUST mirror QuotaGauges.swift: fraction = min(1, max(0, used / 100)).
    const int32_t clamped = window.usedPercentage < 0     ? 0
                            : window.usedPercentage > 100 ? 100
                                                          : window.usedPercentage;
    gauge.fill = static_cast<uint8_t>(clamped);
    gauge.color = gaugeColorFor(window.usedPercentage);
    return gauge;
}

/// Seconds left before the 5 h reset, as the Mac saw it when sending.
uint32_t secondsLeftWhenSent(const Snapshot& snapshot) {
    const int64_t left = snapshot.fiveHour.resetsAt - snapshot.sentAt;
    if (left <= 0) return 0;
    return left > static_cast<int64_t>(UINT32_MAX) ? UINT32_MAX : static_cast<uint32_t>(left);
}

}  // namespace

// MUST mirror QuotaGauges.swift (`thresholdColor`): green < 40 %, yellow < 75 %,
// red otherwise.
GaugeColor gaugeColorFor(int32_t usedPercentage) {
    if (usedPercentage < 40) return GaugeColor::Green;
    if (usedPercentage < 75) return GaugeColor::Yellow;
    return GaugeColor::Red;
}

uint32_t gaugeRgb(GaugeColor color) {
    switch (color) {
        case GaugeColor::Green: return 0x30D158;
        case GaugeColor::Yellow: return 0xFFD60A;
        case GaugeColor::Red: return 0xFF453A;
    }
    return 0x30D158;
}

QuotaView makeQuotaView(const Snapshot& snapshot, uint32_t elapsedMs) {
    QuotaView view;
    view.fiveHour = gaugeFor(snapshot.fiveHour);
    view.sevenDay = gaugeFor(snapshot.sevenDay);
    if (snapshot.fiveHour.present && snapshot.fiveHour.hasResetsAt) {
        const uint32_t left = secondsLeftWhenSent(snapshot);
        const uint32_t elapsed = elapsedMs / 1000;
        view.hasCountdown = true;
        view.countdownSeconds = left > elapsed ? left - elapsed : 0;
    }
    return view;
}

void formatCountdown(uint32_t seconds, char* out, size_t size) {
    if (out == nullptr || size == 0) return;
    if (seconds == 0) {
        snprintf(out, size, "now");
        return;
    }
    // Rounded up: "2h 13m" until the reset really is under 2h 13m away, so it
    // reads like the Mac's reset time minus its clock's minutes.
    const uint32_t minutes = seconds / 60 + (seconds % 60 != 0 ? 1 : 0);
    if (minutes < 60) {
        snprintf(out, size, "%um", static_cast<unsigned>(minutes));
    } else if (minutes <= 24 * 60) {
        snprintf(out, size, "%uh %02um", static_cast<unsigned>(minutes / 60),
                 static_cast<unsigned>(minutes % 60));
    } else {
        snprintf(out, size, "%ud %02uh", static_cast<unsigned>(minutes / 1440),
                 static_cast<unsigned>(minutes % 1440 / 60));
    }
}

namespace {

bool sameGauge(const GaugeView& a, const GaugeView& b) {
    return a.present == b.present && a.percent == b.percent && a.fill == b.fill &&
           a.color == b.color;
}

}  // namespace

bool operator==(const QuotaView& a, const QuotaView& b) {
    return a.dimmed == b.dimmed && sameGauge(a.fiveHour, b.fiveHour) &&
           sameGauge(a.sevenDay, b.sevenDay) && a.hasCountdown == b.hasCountdown &&
           a.countdownSeconds == b.countdownSeconds;
}

bool QuotaPresenter::update(const SnapshotReceiver& receiver, uint32_t nowMs) {
    QuotaView next;
    if (receiver.isConnected(nowMs) && receiver.hasSnapshot()) {
        // Unsigned difference: correct across the millis() wrap.
        next = makeQuotaView(receiver.snapshot(), nowMs - receiver.acceptedAtMs());
        lastLive_ = next;
    } else {
        next = lastLive_;  // frozen: the last live Quotas, or none at boot
        next.dimmed = true;
    }
    const bool changed = !started_ || next != view_;
    view_ = next;
    started_ = true;
    return changed;
}

}  // namespace totem
