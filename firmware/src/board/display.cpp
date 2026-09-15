// LVGL 9 on the CO5300 without PSRAM (issue #158): partial rendering into
// two small internal-RAM buffers, never a full framebuffer.
#include <esp_heap_caps.h>
#include <lvgl.h>

#include "board.h"

namespace board {

namespace {

constexpr int32_t kBufferLines = 20;

Arduino_GFX* gPanel = nullptr;

uint32_t tickMs() { return millis(); }

void flush(lv_display_t* display, const lv_area_t* area, uint8_t* pixels) {
    // RGB565 in LVGL's native order; draw16bitRGBBitmap handles the byte
    // order on the bus, so no extra swap here.
    gPanel->draw16bitRGBBitmap(area->x1, area->y1, reinterpret_cast<uint16_t*>(pixels),
                               lv_area_get_width(area), lv_area_get_height(area));
    lv_display_flush_ready(display);
}

/// The CO5300 only accepts windows starting on even coordinates and
/// spanning an even size: widen every invalidated area to even bounds.
void roundToEvenArea(lv_event_t* event) {
    auto* area = static_cast<lv_area_t*>(lv_event_get_param(event));
    area->x1 &= ~1;
    area->y1 &= ~1;
    area->x2 |= 1;
    area->y2 |= 1;
}

}  // namespace

bool displayBegin(Arduino_GFX* panel) {
    if (panel == nullptr) return false;
    lv_init();
    lv_tick_set_cb(tickMs);

    lv_display_t* display = lv_display_create(kLcdWidth, kLcdHeight);
    const uint32_t bufferBytes =
        kLcdWidth * kBufferLines * lv_color_format_get_size(lv_display_get_color_format(display));
    auto* first = heap_caps_malloc(bufferBytes, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
    auto* second = heap_caps_malloc(bufferBytes, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
    if (first == nullptr || second == nullptr) {
        Serial.println("[display] draw buffers allocation failed");
        return false;
    }
    lv_display_set_buffers(display, first, second, bufferBytes, LV_DISPLAY_RENDER_MODE_PARTIAL);
    lv_display_set_flush_cb(display, flush);
    lv_display_add_event_cb(display, roundToEvenArea, LV_EVENT_INVALIDATE_AREA, nullptr);
    gPanel = panel;  // from here on LVGL may render and flush
    return true;
}

void displayLoop() {
    if (gPanel != nullptr) lv_timer_handler();
}

}  // namespace board
