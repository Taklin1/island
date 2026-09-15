// The pixel-art mascot of the state page (issue #159): one exported 16x16
// Sprite frame drawn at x15 (240x240), one filled rectangle per run of
// same-coloured pixels, no image scaling and no antialiasing.
#pragma once

#include <lvgl.h>

#include <cstdint>

namespace ui {

constexpr int32_t kMascotScale = 15;
constexpr int32_t kMascotSize = 16 * kMascotScale;  // 240

/// Creates the mascot widget under `parent` (transparent, not clickable).
lv_obj_t* mascotCreate(lv_obj_t* parent);

/// Shows `frame` (index into sprites::kFrames), in greys when `grey`.
/// Invalidates the mascot's own area only, and only on a change.
void mascotShow(lv_obj_t* mascot, uint8_t frame, bool grey);

}  // namespace ui
