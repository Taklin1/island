// The Totem's `config.json` (issue #158): Wi-Fi credentials and the shared
// `X-Island-Token`, read from LittleFS so a change needs no rebuild.
#pragma once

#include <cstddef>
#include <string>

namespace totem {

struct TotemConfig {
    std::string ssid;
    std::string password;
    std::string token;
};

enum class ConfigResult : unsigned char {
    Ok,
    InvalidJson,
    MissingSsid,
    MissingToken,
};

/// Parses `config.json`. `out` is written only when the result is `Ok`.
ConfigResult parseConfig(const char* json, size_t length, TotemConfig& out);

}  // namespace totem
