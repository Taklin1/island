#include "freshness.h"

namespace totem {

void Freshness::onAccepted(uint32_t nowMs, bool shutdown) {
    connected_ = !shutdown;
    lastAcceptedMs_ = nowMs;
}

bool Freshness::isConnected(uint32_t nowMs) const {
    // Unsigned subtraction stays correct across the 49.7-day millis() wrap.
    // Expiry latches: once stale, a later wrap of the difference back under
    // the timeout must not revive a Halo that was never refreshed.
    if (connected_ && nowMs - lastAcceptedMs_ >= kTimeoutMs) connected_ = false;
    return connected_;
}

}  // namespace totem
