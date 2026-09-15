// Waveshare ESP32-C6-Touch-AMOLED-2.16 support (issue #158).
//
// Hardware facts (pins, addresses, init order, vendor registers) come from the
// board's published pinout and were verified on this exact board during the
// #158 grilling (2026-09-15, recorded in the issue). This HAL is written from
// those facts; no vendor or third-party board code is copied.
#pragma once

#include <Arduino_GFX_Library.h>

namespace board {

// I2C bus shared by the PMU and the touch controller.
constexpr int kI2cSda = 8;
constexpr int kI2cScl = 7;

// AXP2101 PMU: powers the AMOLED panel through ALDO1..ALDO4.
constexpr uint8_t kPmuAddress = 0x34;

// CO5300 AMOLED over QSPI. The panel reset is not wired to the MCU: it is
// pulsed through the ALDO3 rail instead.
constexpr int kLcdCs = 15;
constexpr int kLcdSclk = 0;
constexpr int kLcdD0 = 1;
constexpr int kLcdD1 = 2;
constexpr int kLcdD2 = 3;
constexpr int kLcdD3 = 4;
constexpr int16_t kLcdWidth = 480;
constexpr int16_t kLcdHeight = 480;

// CST9220/CST9217 capacitive touch controller (issue #160), on the I2C bus
// above. Pins and address: the board's published pinout, recorded in the
// #160 grilling.
constexpr uint8_t kTouchAddress = 0x5A;
constexpr int kTouchInt = 5;
constexpr int kTouchRst = 11;

/// Powers the panel and brings the CO5300 up, in the mandatory order
/// (a wrong order gives a black screen with no error). Returns the panel,
/// or nullptr when the PMU or the panel did not answer.
Arduino_GFX* begin();

/// Writes the CO5300 brightness register (0x51, normal mode). No-op before
/// the panel is up. Never the PWR button: a 6-8 s press powers the AXP2101 off.
void setBrightness(uint8_t value);

/// Brings the touch controller up (after `begin()`, which starts the I2C
/// bus). Returns false when it does not answer: the Totem then simply
/// stays on its state page.
bool touchBegin();

/// Samples the controller: true while a finger is down, with its position
/// in display coordinates.
bool touchRead(int32_t& x, int32_t& y);

/// Starts LVGL on `panel` in partial rendering (no full framebuffer: the
/// board has no PSRAM). Returns false when the draw buffers cannot be had.
bool displayBegin(Arduino_GFX* panel);

/// Runs LVGL timers; call from `loop()`.
void displayLoop();

}  // namespace board
