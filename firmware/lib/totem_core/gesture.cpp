#include "gesture.h"

namespace totem {

Gesture GestureDetector::step(bool touched, uint32_t nowMs) {
    // Unsigned differences throughout: correct across the millis() wrap.
    switch (phase_) {
        case Phase::Idle:
            if (!touched) return Gesture::None;
            phase_ = Phase::Pressed;
            pressStartMs_ = nowMs;
            longPressFired_ = false;
            return Gesture::None;

        case Phase::Releasing:
            if (!touched) {
                if (nowMs - releaseStartMs_ < kTouchDebounceMs) return Gesture::None;
                phase_ = Phase::Idle;
                // A long press already acted while the finger was down.
                return longPressFired_ ? Gesture::None : Gesture::Tap;
            }
            // A dropped report, not a release: the same press goes on.
            phase_ = Phase::Pressed;
            [[fallthrough]];

        case Phase::Pressed:
            if (!touched) {
                phase_ = Phase::Releasing;
                releaseStartMs_ = nowMs;
                return Gesture::None;
            }
            if (!longPressFired_ && nowMs - pressStartMs_ >= kLongPressMs) {
                longPressFired_ = true;  // once per press, no repeat while held
                return Gesture::LongPress;
            }
            return Gesture::None;
    }
    return Gesture::None;
}

TouchStep TouchNavigator::step(bool touched, uint32_t nowMs) {
    TouchStep step;
    if (touched) {
        lastTouchMs_ = nowMs;  // every touch re-arms the automatic return
    } else if (page_ == Page::Quotas && nowMs - lastTouchMs_ >= kAutoReturnMs) {
        page_ = Page::State;
        step.pageChanged = true;
    }
    switch (detector_.step(touched, nowMs)) {
        case Gesture::Tap:
            page_ = page_ == Page::State ? Page::Quotas : Page::State;
            step.pageChanged = true;
            break;
        case Gesture::LongPress:
            step.brightnessStep = true;
            break;
        case Gesture::None:
            break;
    }
    return step;
}

}  // namespace totem
