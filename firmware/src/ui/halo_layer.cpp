// Halo layer (issue #159). An inner glow made of kHaloBandCount nested
// borders of decreasing opacity — never a full-screen shadow, whose cache
// would not fit the SRAM. It lives in four strips along the edges (top and
// bottom full width, left and right between them): invalidating the strips
// for a breathing step repaints the screen edges only, never the mascot or
// the counts in the middle.
#include "halo_layer.h"

namespace ui {

namespace {

constexpr uint32_t kBreathTickMs = 100;
/// Breathing levels are coarsened to this step: fewer repaints, a change of
/// ~1 % is not visible anyway.
constexpr uint8_t kBreathStep = 4;

lv_obj_t* gStrips[4] = {nullptr, nullptr, nullptr, nullptr};
totem::HaloColor gColor = totem::HaloColor::Off;
uint8_t gLevel = 255;

uint8_t breathLevelAt(uint32_t nowMs) {
    const uint8_t level = totem::haloBreathLevel(nowMs);
    return level >= 255 - kBreathStep / 2 ? 255 : static_cast<uint8_t>(level / kBreathStep * kBreathStep);
}

void invalidateStrips() {
    for (lv_obj_t* strip : gStrips) lv_obj_invalidate(strip);
}

void drawStrip(lv_event_t* event) {
    if (gColor == totem::HaloColor::Off) return;
    lv_layer_t* layer = lv_event_get_layer(event);
    const int32_t width = lv_display_get_horizontal_resolution(nullptr);
    const int32_t height = lv_display_get_vertical_resolution(nullptr);

    lv_draw_border_dsc_t band;
    lv_draw_border_dsc_init(&band);
    band.color = lv_color_hex(totem::haloRgb(gColor));
    band.width = kHaloBandWidth;
    band.side = LV_BORDER_SIDE_FULL;
    // Each strip draws the whole ring; the layer clips it to the strip, and
    // the strips do not overlap, so no band is painted twice.
    for (uint8_t i = 0; i < totem::kHaloBandCount; ++i) {
        const int32_t inset = i * kHaloBandWidth;
        band.opa = static_cast<lv_opa_t>(totem::kHaloBandOpa[i] * gLevel / 255);
        band.radius = kHaloRadius > inset ? kHaloRadius - inset : 0;
        const lv_area_t ring = {inset, inset, width - 1 - inset, height - 1 - inset};
        lv_draw_border(layer, &band, &ring);
    }
}

void breathe(lv_timer_t*) {
    if (gColor == totem::HaloColor::Off) return;
    const uint8_t level = breathLevelAt(lv_tick_get());
    if (level == gLevel) return;
    gLevel = level;
    invalidateStrips();
}

lv_obj_t* addStrip(lv_obj_t* top, int32_t x, int32_t y, int32_t w, int32_t h) {
    lv_obj_t* strip = lv_obj_create(top);
    lv_obj_remove_style_all(strip);
    lv_obj_remove_flag(strip, static_cast<lv_obj_flag_t>(LV_OBJ_FLAG_CLICKABLE |
                                                         LV_OBJ_FLAG_SCROLLABLE));
    lv_obj_set_pos(strip, x, y);
    lv_obj_set_size(strip, w, h);
    lv_obj_add_flag(strip, LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_event_cb(strip, drawStrip, LV_EVENT_DRAW_MAIN, nullptr);
    return strip;
}

}  // namespace

void haloBegin() {
    lv_obj_t* top = lv_layer_top();
    const int32_t width = lv_display_get_horizontal_resolution(nullptr);
    const int32_t height = lv_display_get_vertical_resolution(nullptr);
    const int32_t t = kHaloInset;
    gStrips[0] = addStrip(top, 0, 0, width, t);                   // top
    gStrips[1] = addStrip(top, 0, height - t, width, t);          // bottom
    gStrips[2] = addStrip(top, 0, t, t, height - 2 * t);          // left
    gStrips[3] = addStrip(top, width - t, t, t, height - 2 * t);  // right
    // Runs on its own clock, whatever the Instantanés do.
    lv_timer_create(breathe, kBreathTickMs, nullptr);
}

void haloSet(totem::HaloColor color) {
    if (color == gColor || gStrips[0] == nullptr) return;
    const bool wasOff = gColor == totem::HaloColor::Off;
    gColor = color;
    if (color == totem::HaloColor::Off) {
        for (lv_obj_t* strip : gStrips) lv_obj_add_flag(strip, LV_OBJ_FLAG_HIDDEN);
        return;
    }
    gLevel = breathLevelAt(lv_tick_get());
    if (wasOff) {
        for (lv_obj_t* strip : gStrips) lv_obj_remove_flag(strip, LV_OBJ_FLAG_HIDDEN);
    } else {
        invalidateStrips();  // orange <-> green
    }
}

}  // namespace ui
