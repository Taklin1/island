#include "config.h"

#include <ArduinoJson.h>

namespace totem {

namespace {

/// A string member, or "" when it is absent, `null` or not a string.
const char* stringMember(JsonObjectConst object, const char* key) {
    JsonVariantConst value = object[key];
    return value.is<const char*>() ? value.as<const char*>() : "";
}

}  // namespace

ConfigResult parseConfig(const char* json, size_t length, TotemConfig& out) {
    if (json == nullptr) return ConfigResult::InvalidJson;
    JsonDocument document;
    if (deserializeJson(document, json, length) != DeserializationError::Ok ||
        !document.is<JsonObjectConst>()) {
        return ConfigResult::InvalidJson;
    }
    JsonObjectConst root = document.as<JsonObjectConst>();

    TotemConfig parsed;
    parsed.ssid = stringMember(root, "ssid");
    parsed.password = stringMember(root, "password");
    parsed.token = stringMember(root, "token");
    if (parsed.ssid.empty()) return ConfigResult::MissingSsid;
    // An empty token would match the "" WebServer yields for a missing header.
    if (parsed.token.empty()) return ConfigResult::MissingToken;

    out = parsed;
    return ConfigResult::Ok;
}

}  // namespace totem
