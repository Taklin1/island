#include "halo.h"

namespace totem {

HaloColor haloFor(bool connected, AggregateState state) {
    if (!connected) return HaloColor::Off;
    switch (state) {
        case AggregateState::Waiting: return HaloColor::Orange;
        case AggregateState::Done: return HaloColor::Green;
        case AggregateState::Working:
        case AggregateState::Idle: return HaloColor::Off;
    }
    return HaloColor::Off;
}

uint32_t haloRgb(HaloColor color) {
    switch (color) {
        case HaloColor::Orange: return 0xFF9F0A;
        case HaloColor::Green: return 0x30D158;
        case HaloColor::Off: return 0;
    }
    return 0;
}

uint8_t haloBreathLevel(uint32_t nowMs) {
    const uint32_t half = kHaloBreathPeriodMs / 2;
    const uint32_t phase = nowMs % kHaloBreathPeriodMs;
    // Triangle 0..half..0 over one period, then smoothstep x^2 (3 - 2x).
    const uint64_t x = phase < half ? phase : kHaloBreathPeriodMs - phase;
    const uint64_t eased = x * x * (3u * half - 2u * x);  // scaled by half^3
    const uint64_t scale = static_cast<uint64_t>(half) * half * half;
    const uint32_t depth = 255u - kHaloBreathMin;
    return static_cast<uint8_t>(kHaloBreathMin + (depth * eased + scale / 2) / scale);
}

}  // namespace totem
