// Brightness persistence (issue #160). `Preferences` is the Arduino core's
// NVS wrapper; only the level index is stored, written on a long press only.
#include "brightness.h"

#include <Arduino.h>
#include <Preferences.h>

#include "board/board.h"
#include "brightness_levels.h"

namespace brightness {

namespace {

constexpr const char* kNamespace = "totem";
constexpr const char* kLevelKey = "brightness";
constexpr uint8_t kNoStoredLevel = 0xFF;

uint8_t gLevel = totem::kDefaultBrightnessLevel;

void apply() {
    board::setBrightness(totem::brightnessFor(gLevel));
    Serial.printf("[brightness] level %u (0x51 = %u)\n", static_cast<unsigned>(gLevel),
                  static_cast<unsigned>(totem::brightnessFor(gLevel)));
}

}  // namespace

void begin() {
    Preferences preferences;
    uint8_t stored = kNoStoredLevel;
    // Read-only: a missing namespace (first boot) just means the default.
    if (preferences.begin(kNamespace, true)) {
        stored = preferences.getUChar(kLevelKey, kNoStoredLevel);
        preferences.end();
    }
    gLevel = totem::storedBrightnessLevel(stored);
    apply();
}

void step() {
    gLevel = totem::nextBrightnessLevel(gLevel);
    apply();
    Preferences preferences;
    if (preferences.begin(kNamespace, false)) {
        preferences.putUChar(kLevelKey, gLevel);
        preferences.end();
    } else {
        Serial.println("[brightness] NVS unavailable: level not stored");
    }
}

}  // namespace brightness
