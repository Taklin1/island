// Shared-token check for incoming Instantanés (issue #158, ADR-0014).
#pragma once

namespace totem {

/// True when `presented` (the `X-Island-Token` header) equals the configured
/// token. An empty or missing configured token authorizes nothing.
bool isAuthorized(const char* configured, const char* presented);

}  // namespace totem
