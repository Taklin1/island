// The Instantané as the Totem decodes it (issue #158, contract v1 pinned by
// `firmware/contract/`). Pure logic: no Arduino.h, ArduinoJson only.
#pragma once

#include <cstddef>
#include <cstdint>

namespace totem {

/// Version of the JSON contract (`v`) this firmware understands.
constexpr int kContractVersion = 1;

enum class AggregateState : uint8_t { Idle, Working, Done, Waiting };

/// Raw per-state Session counts.
struct Counts {
    uint32_t waiting = 0;
    uint32_t done = 0;
    uint32_t working = 0;
    uint32_t idle = 0;
};

/// One Quotas window; `present` is false when its key is omitted.
struct QuotaWindow {
    bool present = false;
    int32_t usedPercentage = 0;
    bool hasResetsAt = false;
    /// Whole Unix epoch seconds.
    int64_t resetsAt = 0;
};

struct Snapshot {
    AggregateState state = AggregateState::Idle;
    Counts counts;
    QuotaWindow fiveHour;
    QuotaWindow sevenDay;
    /// Emission stamp, whole Unix epoch seconds. Never used for freshness.
    int64_t sentAt = 0;
    bool shutdown = false;
};

enum class DecodeResult : uint8_t {
    Ok,
    InvalidJson,
    MissingVersion,
    UnsupportedVersion,
    InvalidField,
};

/// Decodes one Instantané. `out` is written only when the result is `Ok`.
DecodeResult decodeSnapshot(const char* json, size_t length, Snapshot& out);

}  // namespace totem
