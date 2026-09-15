// The POST /snapshot gate (issue #158): what the HTTP server hands over, what
// status it answers, and the last accepted Instantané with its freshness.
// Pure logic, so the validation order is tested natively.
#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

#include "freshness.h"
#include "snapshot.h"

namespace totem {

/// Largest accepted Instantané body (a nominal one is ~220 bytes).
constexpr size_t kMaxSnapshotBytes = 2048;

class SnapshotReceiver {
public:
    explicit SnapshotReceiver(const char* configuredToken);

    /// Validates one POST /snapshot and returns the HTTP status to answer.
    uint16_t receive(const char* presentedToken, const char* body, size_t bodyLength,
                     uint32_t nowMs);

    bool hasSnapshot() const { return hasSnapshot_; }
    /// The last accepted Instantané; meaningful only when `hasSnapshot()`.
    const Snapshot& snapshot() const { return snapshot_; }
    bool isConnected(uint32_t nowMs) const { return freshness_.isConnected(nowMs); }

private:
    std::string token_;
    Snapshot snapshot_;
    bool hasSnapshot_ = false;
    Freshness freshness_;
};

}  // namespace totem
