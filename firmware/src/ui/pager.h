// The Totem's two pages (issue #160): both built once at boot and flipped
// with LV_OBJ_FLAG_HIDDEN — never created or destroyed on a tap (LVGL's
// 64 KB heap). The Halo lives on lv_layer_top(), above both.
#pragma once

#include <lvgl.h>

#include "gesture.h"
#include "halo_layer.h"

namespace ui {

/// Page content stays inside the Halo's edge margin.
constexpr int32_t kPagePad = kHaloInset + 8;
constexpr int32_t kPageRowGap = 8;

/// A full-screen, transparent, non-clickable centred column on the active
/// screen (black), for one page.
lv_obj_t* pageCreate();

/// Registers the pages and shows the state page.
void pagerBegin(lv_obj_t* statePage, lv_obj_t* quotasPage);

/// Shows `page` and hides the other one.
void pagerShow(totem::Page page);

}  // namespace ui
