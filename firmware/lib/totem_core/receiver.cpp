#include "receiver.h"

#include "auth.h"

namespace totem {

SnapshotReceiver::SnapshotReceiver(const char* configuredToken)
    : token_(configuredToken == nullptr ? "" : configuredToken) {}

uint16_t SnapshotReceiver::receive(const char* presentedToken, const char* body,
                                   size_t bodyLength, uint32_t nowMs) {
    // Order matters (issue #158): an unauthenticated peer learns nothing
    // about the size limit or the contract.
    if (!isAuthorized(token_.c_str(), presentedToken)) return 401;
    // `body` may hold only the first kMaxSnapshotBytes: never read it here.
    if (bodyLength > kMaxSnapshotBytes) return 413;

    Snapshot decoded;
    if (decodeSnapshot(body, bodyLength, decoded) != DecodeResult::Ok) return 400;

    // Only an accepted Instantané replaces the state and refreshes.
    snapshot_ = decoded;
    hasSnapshot_ = true;
    freshness_.onAccepted(nowMs, decoded.shutdown);
    return 204;
}

}  // namespace totem
