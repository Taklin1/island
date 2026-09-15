// Freshness of the last accepted Instantané (issue #158): drives Déconnecté.
// Pure logic on an injected `millis()` clock, never on the `sentAt` stamp.
#pragma once

#include <cstdint>

namespace totem {

class Freshness {
public:
    /// Silence after which the Totem shows Déconnecté (ADR-0014, ~30 s).
    static constexpr uint32_t kTimeoutMs = 30000;

    /// Records an accepted Instantané received at `nowMs`: a normal one
    /// (re)connects, a `shutdown` one disconnects at once. Rejected requests
    /// must never call this — only an accepted Instantané refreshes.
    void onAccepted(uint32_t nowMs, bool shutdown);

    /// Déconnecté at boot until the first accepted Instantané, then after
    /// `kTimeoutMs` of silence. Meant to be polled from the main loop (at
    /// least once per 49.7-day millis() cycle) so expiry is latched.
    bool isConnected(uint32_t nowMs) const;

private:
    mutable bool connected_ = false;
    uint32_t lastAcceptedMs_ = 0;
};

}  // namespace totem
