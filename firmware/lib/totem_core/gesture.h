// Touch navigation of the Totem (issue #160, ADR-0013): the touch only
// navigates locally — a tap flips the state page and the Quotas page, a long
// press steps the brightness. Nothing is ever sent to the app. Pure logic on
// sampled touch states and an injected millis() clock.
#pragma once

#include <cstdint>

namespace totem {

enum class Page : uint8_t { State, Quotas };

/// A release shorter than this is a glitch of the controller's reports, not
/// the end of the press (anti-bounce).
constexpr uint32_t kTouchDebounceMs = 60;
/// A press held this long is a long press (fired while the finger is still
/// down, once per press); a shorter one is a tap (on release).
constexpr uint32_t kLongPressMs = 600;
/// The Quotas page gives way to the state page after this long without a
/// touch (reco adopted 2026-09-15, to be confirmed on the board).
constexpr uint32_t kAutoReturnMs = 30000;

enum class Gesture : uint8_t { None, Tap, LongPress };

/// Turns sampled touch states into gestures.
class GestureDetector {
public:
    /// Feeds the touch state sampled at `nowMs`; returns the gesture it ends.
    Gesture step(bool touched, uint32_t nowMs);

private:
    enum class Phase : uint8_t { Idle, Pressed, Releasing };
    Phase phase_ = Phase::Idle;
    uint32_t pressStartMs_ = 0;
    uint32_t releaseStartMs_ = 0;
    bool longPressFired_ = false;
};

struct TouchStep {
    bool pageChanged = false;
    bool brightnessStep = false;
};

/// The pages and brightness steps driven by the touch: a tap flips the
/// page, a long press asks for one brightness step, and the Quotas page
/// returns to the state page `kAutoReturnMs` after the last touched sample.
class TouchNavigator {
public:
    /// Feeds the touch state sampled at `nowMs` (millis()). Call regularly,
    /// touched or not: the automatic return is checked here too.
    TouchStep step(bool touched, uint32_t nowMs);
    Page page() const { return page_; }

private:
    GestureDetector detector_;
    Page page_ = Page::State;
    uint32_t lastTouchMs_ = 0;
};

}  // namespace totem
