// What the Totem Quotas page shows (issue #160), derived from the last
// accepted Instantané. Pure logic.
//
// The gauges MUST mirror QuotaGauges.swift (the Extended Island): fill
// clamped to 0…1, green < 40 %, yellow < 75 %, red otherwise, labels "5 h"
// and "7 d", no gauge for an absent window — never a misleading 0 %.
#pragma once

#include <cstddef>
#include <cstdint>

#include "receiver.h"
#include "snapshot.h"

namespace totem {

enum class GaugeColor : uint8_t { Green, Yellow, Red };

/// Window labels (QuotaGauges.swift, ADR-0012).
constexpr const char* kFiveHourLabel = "5 h";
constexpr const char* kSevenDayLabel = "7 d";

/// Threshold colour of a gauge for the whole percent the Mac sent. The Mac
/// thresholds its unrounded percentage: at a boundary (39.6 % shown "40%")
/// the Totem, which only gets the rounded whole percent, may differ by one
/// colour step — the contract carries whole percents only (#156).
GaugeColor gaugeColorFor(int32_t usedPercentage);

/// 0xRRGGBB of a gauge fill: SwiftUI `Color.green` / `.yellow` / `.red`,
/// dark appearance, as the Halo takes the Liseré's dark system colours.
uint32_t gaugeRgb(GaugeColor color);

/// The reset countdown's colour: SwiftUI `Color.cyan`, dark appearance.
constexpr uint32_t kCountdownRgb = 0x64D2FF;

struct GaugeView {
    /// False when the window is absent: no gauge at all.
    bool present = false;
    /// Whole percent as sent (the label, unclamped like the Mac's).
    int32_t percent = 0;
    /// Bar fill in percent, clamped to 0…100.
    uint8_t fill = 0;
    GaugeColor color = GaugeColor::Green;
};

struct QuotaView {
    /// Déconnecté: the gauges and the countdown are dimmed (and frozen).
    bool dimmed = false;
    GaugeView fiveHour;
    GaugeView sevenDay;
    /// The 5 h reset is known.
    bool hasCountdown = false;
    uint32_t countdownSeconds = 0;

    /// False shows "no quotas" instead of the gauges.
    bool hasQuotas() const { return fiveHour.present || sevenDay.present; }
};

/// The Quotas of `snapshot`, `elapsedMs` (millis()) after it was accepted.
/// The countdown is `resetsAt - sentAt` at acceptance, minus the whole
/// seconds elapsed since, never below 0: the Totem has no clock of its own.
QuotaView makeQuotaView(const Snapshot& snapshot, uint32_t elapsedMs);

/// Writes the countdown text (ASCII, without the reset icon) into `out`:
/// "now" at 0, else whole minutes rounded up ("13m", "2h 05m" up to 24 h,
/// then "1d 03h"). Always NUL-terminated, truncated to `size`.
void formatCountdown(uint32_t seconds, char* out, size_t size);

bool operator==(const QuotaView& a, const QuotaView& b);
inline bool operator!=(const QuotaView& a, const QuotaView& b) { return !(a == b); }

/// Keeps what the Quotas page shows. Connecté: the live Quotas of the last
/// accepted Instantané, countdown running down. Déconnecté (CONTEXT.md): the
/// last live Quotas, dimmed and frozen — also after the app's closing
/// Instantané, which carries none; "no quotas" dimmed at boot.
class QuotaPresenter {
public:
    /// Recomputes at `nowMs` (millis()); true when the view changed.
    bool update(const SnapshotReceiver& receiver, uint32_t nowMs);

    const QuotaView& view() const { return view_; }

private:
    QuotaView view_;
    QuotaView lastLive_;
    bool started_ = false;
};

}  // namespace totem
