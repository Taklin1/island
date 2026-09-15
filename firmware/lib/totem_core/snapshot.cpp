#include "snapshot.h"

#include <ArduinoJson.h>

#include <cstring>

namespace totem {

namespace {

bool decodeState(JsonVariantConst value, AggregateState& out) {
    const char* text = value.as<const char*>();
    if (!value.is<const char*>() || text == nullptr) return false;
    if (std::strcmp(text, "idle") == 0) { out = AggregateState::Idle; return true; }
    if (std::strcmp(text, "working") == 0) { out = AggregateState::Working; return true; }
    if (std::strcmp(text, "done") == 0) { out = AggregateState::Done; return true; }
    if (std::strcmp(text, "waiting") == 0) { out = AggregateState::Waiting; return true; }
    return false;
}

bool decodeCount(JsonVariantConst value, uint32_t& out) {
    if (!value.is<uint32_t>()) return false;
    out = value.as<uint32_t>();
    return true;
}

bool decodeCounts(JsonVariantConst value, Counts& out) {
    if (!value.is<JsonObjectConst>()) return false;
    return decodeCount(value["waiting"], out.waiting) && decodeCount(value["done"], out.done) &&
           decodeCount(value["working"], out.working) && decodeCount(value["idle"], out.idle);
}

/// An omitted window stays `present = false`; a present one must be whole.
bool decodeWindow(JsonVariantConst value, QuotaWindow& out) {
    out = QuotaWindow{};
    if (value.isUnbound()) return true;
    if (!value.is<JsonObjectConst>()) return false;
    JsonVariantConst used = value["usedPercentage"];
    if (!used.is<int32_t>()) return false;
    out.usedPercentage = used.as<int32_t>();
    JsonVariantConst resetsAt = value["resetsAt"];
    if (!resetsAt.isUnbound()) {
        if (!resetsAt.is<int64_t>()) return false;
        out.hasResetsAt = true;
        out.resetsAt = resetsAt.as<int64_t>();
    }
    out.present = true;
    return true;
}

bool decodeQuotas(JsonVariantConst value, Snapshot& out) {
    out.fiveHour = QuotaWindow{};
    out.sevenDay = QuotaWindow{};
    if (value.isUnbound()) return true;
    if (!value.is<JsonObjectConst>()) return false;
    return decodeWindow(value["fiveHour"], out.fiveHour) &&
           decodeWindow(value["sevenDay"], out.sevenDay);
}

}  // namespace

DecodeResult decodeSnapshot(const char* json, size_t length, Snapshot& out) {
    if (json == nullptr) return DecodeResult::InvalidJson;
    JsonDocument document;
    if (deserializeJson(document, json, length) != DeserializationError::Ok ||
        !document.is<JsonObjectConst>()) {
        return DecodeResult::InvalidJson;
    }
    JsonVariantConst root = document.as<JsonVariantConst>();

    JsonVariantConst version = root["v"];
    if (version.isUnbound()) return DecodeResult::MissingVersion;
    if (!version.is<int>() || version.as<int>() != kContractVersion) {
        return DecodeResult::UnsupportedVersion;
    }

    Snapshot decoded;
    JsonVariantConst sentAt = root["sentAt"];
    JsonVariantConst shutdown = root["shutdown"];
    if (!decodeState(root["state"], decoded.state) ||
        !decodeCounts(root["counts"], decoded.counts) || !decodeQuotas(root["quotas"], decoded) ||
        !sentAt.is<int64_t>() || !shutdown.is<bool>()) {
        return DecodeResult::InvalidField;
    }
    decoded.sentAt = sentAt.as<int64_t>();
    decoded.shutdown = shutdown.as<bool>();

    out = decoded;
    return DecodeResult::Ok;
}

}  // namespace totem
