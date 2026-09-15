// The Halo on lv_layer_top() (issue #159): above every page, so the Quotas
// page (#160) never hides it.
#pragma once

#include <lvgl.h>

#include <cstdint>

#include "halo.h"

namespace ui {

/// Depth of the glow from the screen edge (kHaloBandCount bands).
constexpr int32_t kHaloBandWidth = 6;
constexpr int32_t kHaloThickness = kHaloBandWidth * totem::kHaloBandCount;  // 24
/// Corner radius of the outer band, for the panel's rounded corners. To be
/// tuned on the board; the drawing stays within kHaloInset of each edge.
constexpr int32_t kHaloRadius = 24;
/// Edge margin the Halo may paint: page content must stay inside it, so the
/// breathing never redraws the mascot or the counts.
constexpr int32_t kHaloInset = kHaloThickness > kHaloRadius ? kHaloThickness : kHaloRadius;

/// Builds the four edge strips (hidden) and starts the breathing timer.
void haloBegin();

/// Lights the Halo in `color` or turns it off. No-op when unchanged.
void haloSet(totem::HaloColor color);

}  // namespace ui
