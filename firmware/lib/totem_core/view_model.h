// What the Totem state page shows (issue #159), derived from the last
// accepted Instantané. Pure logic: the firmware recomputes nothing, it only
// maps the Mac's aggregated state onto the mascot, the counts and the Halo.
#pragma once

#include <cstdint>

#include "halo.h"
#include "receiver.h"
#include "snapshot.h"

namespace totem {

/// A mascot animation; the value is its row in `sprites::kLoops`.
enum class Animation : uint8_t { Working = 0, Sleeping = 1, Finished = 2, Question = 3 };

/// Mirrors `SpriteAnimation.animation(for:)` in Sources/IslandUI/Sprites.swift.
Animation animationFor(AggregateState state);

struct ViewModel {
    bool connected = false;
    Animation animation = Animation::Sleeping;
    /// Déconnecté: the sleeping mascot is drawn in greys.
    bool grey = true;
    /// Raw per-state counts as sent; all zero (and not shown) when Déconnecté.
    Counts counts;
    HaloColor halo = HaloColor::Off;
};

/// The page for `snapshot` (nullptr when none was ever accepted).
ViewModel makeViewModel(bool connected, const Snapshot* snapshot);

/// The page for the receiver's last accepted Instantané at `nowMs`.
ViewModel viewModelFor(const SnapshotReceiver& receiver, uint32_t nowMs);

/// Which parts of the page must be touched in LVGL after a step.
struct PageUpdate {
    bool link = false;    // CONNECTED / DISCONNECTED
    bool counts = false;  // per-state counts
    bool halo = false;    // Halo colour (on/off included)
    bool mascot = false;  // mascot frame or palette
    bool any() const { return link || counts || halo || mascot; }
};

/// Keeps the last applied view model and the running mascot animation, so
/// the page only touches LVGL on a real difference: an identical Instantané
/// or a heartbeat changes nothing, and the frame index never restarts while
/// the animation stays the same (even across Connecté/Déconnecté).
class PagePresenter {
public:
    /// Applies `next` at `nowMs` (the board's millis()) and says what changed.
    PageUpdate step(const ViewModel& next, uint32_t nowMs);

    /// The last applied view model.
    const ViewModel& view() const { return view_; }
    /// The mascot frame to draw, as an index into `sprites::kFrames`.
    uint8_t frame() const { return frame_; }

private:
    ViewModel view_;
    bool started_ = false;
    uint32_t animationStartMs_ = 0;
    uint8_t frame_ = 0;
};

}  // namespace totem
