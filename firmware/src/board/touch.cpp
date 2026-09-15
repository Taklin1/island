// CST9220/CST9217 touch (issue #160), through SensorLib's TouchDrvCST92xx
// (version pinned in platformio.ini: the API differs between 0.2.x and 0.4.x).
//
// Axes: the controller reports in its own frame; with the panel's MADCTL
// 0x30 (#158, board_init.cpp) display coordinates need X/Y swapped and X
// mirrored. This is a hardware fact observed on this board by the Clawdmeter
// project and recorded in the #160 grilling — no code copied. Recalibrate if
// the MADCTL orientation ever changes.
#include <Wire.h>
#include <touch/TouchDrvCST92xx.h>

#include "board.h"

namespace board {

namespace {

TouchDrvCST92xx gTouch;
bool gTouchReady = false;

}  // namespace

bool touchBegin() {
    gTouch.setPins(kTouchRst, kTouchInt);
    // Same bus and pins as the PMU: Wire is already started by begin().
    if (!gTouch.begin(Wire, kTouchAddress, kI2cSda, kI2cScl)) {
        Serial.println("[touch] CST92xx not found");
        return false;
    }
    gTouch.setMaxCoordinates(kLcdWidth - 1, kLcdHeight - 1);
    gTouch.setSwapXY(true);
    gTouch.setMirrorXY(true, false);
    Serial.printf("[touch] %s ready\n", gTouch.getModelName());
    gTouchReady = true;
    return true;
}

bool touchRead(int32_t& x, int32_t& y) {
    if (!gTouchReady) return false;
    // Polled over I2C at LVGL's input period; the INT line is configured
    // but not relied upon, so a missed edge never loses a release.
    const TouchPoints& points = gTouch.getTouchPoints();
    if (!points.hasPoints()) return false;
    const TouchPoint& point = points.getPoint(0);
    x = point.x;
    y = point.y;
    return true;
}

}  // namespace board
