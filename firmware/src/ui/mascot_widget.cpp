// Mascot widget (issue #159). Rendered by hand in a draw event rather than
// with lv_image: no PSRAM, so no upscaled bitmaps (~115 KB a frame, twice for
// the grey palette); the 16x16 indexed frames stay in flash.
#include "mascot_widget.h"

#include "sprite_palette.h"
#include "totem_sprites.h"

namespace ui {

namespace {

namespace sprites = totem::sprites;

constexpr auto kGreyPalette = totem::greyPalette();

struct MascotState {
    bool shown = false;
    uint8_t frame = 0;
    bool grey = false;
};

MascotState gState;

void drawMascot(lv_event_t* event) {
    lv_obj_t* mascot = lv_event_get_target_obj(event);
    lv_layer_t* layer = lv_event_get_layer(event);
    lv_area_t origin;
    lv_obj_get_coords(mascot, &origin);

    const uint8_t* pixels = sprites::kFrames[gState.frame];
    const uint32_t* palette = gState.grey ? kGreyPalette.data() : sprites::kPalette;

    lv_draw_fill_dsc_t fill;
    lv_draw_fill_dsc_init(&fill);
    fill.opa = LV_OPA_COVER;
    fill.radius = 0;

    for (int32_t y = 0; y < sprites::kFrameSize; ++y) {
        const int32_t top = origin.y1 + y * kMascotScale;
        const int32_t bottom = top + kMascotScale - 1;
        // Partial rendering redraws in bands: skip rows outside this one.
        if (bottom < layer->_clip_area.y1 || top > layer->_clip_area.y2) continue;
        const uint8_t* row = pixels + y * sprites::kFrameSize;
        int32_t x = 0;
        while (x < sprites::kFrameSize) {
            const uint8_t index = row[x];
            int32_t end = x + 1;
            while (end < sprites::kFrameSize && row[end] == index) ++end;
            if (index != 0) {  // 0 is transparent
                fill.color = lv_color_hex(palette[index]);
                const lv_area_t area = {origin.x1 + x * kMascotScale, top,
                                        origin.x1 + end * kMascotScale - 1, bottom};
                lv_draw_fill(layer, &fill, &area);
            }
            x = end;
        }
    }
}

}  // namespace

lv_obj_t* mascotCreate(lv_obj_t* parent) {
    lv_obj_t* mascot = lv_obj_create(parent);
    lv_obj_remove_style_all(mascot);
    lv_obj_remove_flag(mascot, static_cast<lv_obj_flag_t>(LV_OBJ_FLAG_CLICKABLE |
                                                          LV_OBJ_FLAG_SCROLLABLE));
    lv_obj_set_size(mascot, kMascotSize, kMascotSize);
    lv_obj_add_event_cb(mascot, drawMascot, LV_EVENT_DRAW_MAIN, nullptr);
    return mascot;
}

void mascotShow(lv_obj_t* mascot, uint8_t frame, bool grey) {
    if (frame >= sprites::kFrameCount) return;
    if (gState.shown && frame == gState.frame && grey == gState.grey) return;
    gState.shown = true;
    gState.frame = frame;
    gState.grey = grey;
    lv_obj_invalidate(mascot);
}

}  // namespace ui
