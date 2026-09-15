// Brightness levels of the Totem (issue #160). Pure logic: the board writes
// the value to the CO5300 brightness register (0x51) and persists the level
// index in NVS. A long press steps to the next level, cyclically.
#pragma once

#include <cstdint>

namespace totem {

constexpr uint8_t kBrightnessLevelCount = 4;

/// CO5300 0x51 values, dimmest first. The floor stays well above 0 so the
/// Totem never looks switched off. To be tuned on the board.
constexpr uint8_t kBrightnessLevels[kBrightnessLevelCount] = {48, 112, 176, 240};

/// The brightest level: close to the 0xD0 the panel driver's init sequence
/// has shown so far (#158).
constexpr uint8_t kDefaultBrightnessLevel = kBrightnessLevelCount - 1;

/// A stored level index, or the default when absent or out of range.
constexpr uint8_t storedBrightnessLevel(uint8_t stored) {
    return stored < kBrightnessLevelCount ? stored : kDefaultBrightnessLevel;
}

/// The register value of `level` (out of range reads as the default).
constexpr uint8_t brightnessFor(uint8_t level) {
    return kBrightnessLevels[storedBrightnessLevel(level)];
}

/// The level after `level`: the brightest wraps round to the floor.
constexpr uint8_t nextBrightnessLevel(uint8_t level) {
    return static_cast<uint8_t>((storedBrightnessLevel(level) + 1) % kBrightnessLevelCount);
}

}  // namespace totem
