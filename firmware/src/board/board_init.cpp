// Power and panel bring-up (issue #158). Order, rails and registers: see
// board.h for the source of these hardware facts.
#include <Wire.h>
#include <XPowersLib.h>

#include "board.h"

namespace board {

namespace {

XPowersAXP2101 pmu;

constexpr uint16_t kPanelRailMillivolts = 3300;
constexpr uint32_t kResetPulseMs = 100;

bool powerPanelRails() {
    if (!pmu.begin(Wire, kPmuAddress, kI2cSda, kI2cScl)) return false;

    pmu.setALDO1Voltage(kPanelRailMillivolts);
    pmu.setALDO2Voltage(kPanelRailMillivolts);
    pmu.setALDO3Voltage(kPanelRailMillivolts);
    pmu.setALDO4Voltage(kPanelRailMillivolts);
    pmu.enableALDO1();
    pmu.enableALDO2();
    pmu.enableALDO4();

    // ALDO3 doubles as the panel reset line: high, low, high.
    pmu.enableALDO3();
    delay(kResetPulseMs);
    pmu.disableALDO3();
    delay(kResetPulseMs);
    pmu.enableALDO3();
    delay(kResetPulseMs);
    return true;
}

/// Vendor-specific CO5300 registers for this panel, then MADCTL, written
/// after the driver's own init sequence.
void writePanelRegisters(Arduino_DataBus* bus) {
    bus->beginWrite();
    bus->writeC8D8(0xFE, 0x20);  // enter the manufacturer command page
    bus->writeC8D8(0x19, 0x10);
    bus->writeC8D8(0x1C, 0xA0);
    bus->writeC8D8(0xFE, 0x00);  // back to the user command page
    bus->writeC8D8(0x36, 0x30);  // MADCTL: panel orientation
    bus->endWrite();
}

}  // namespace

Arduino_GFX* begin() {
    Wire.begin(kI2cSda, kI2cScl);
    if (!powerPanelRails()) {
        Serial.println("[board] AXP2101 PMU not found");
        return nullptr;
    }

    static Arduino_DataBus* bus =
        new Arduino_ESP32QSPI(kLcdCs, kLcdSclk, kLcdD0, kLcdD1, kLcdD2, kLcdD3);
    static Arduino_GFX* panel =
        new Arduino_CO5300(bus, GFX_NOT_DEFINED, 0, kLcdWidth, kLcdHeight, 0, 0, 0, 0);
    if (!panel->begin()) {
        Serial.println("[board] CO5300 panel init failed");
        return nullptr;
    }
    writePanelRegisters(bus);
    return panel;
}

}  // namespace board
