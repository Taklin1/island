// The Totem state page (issue #159): mascot, per-state counts, link and
// address, with the Halo around the screen. Replaces #158's text screen.
#pragma once

#include <cstdint>

#include "view_model.h"

namespace ui {

/// Builds the page and the Halo once; afterwards only changes are drawn.
void pageStateBegin();

/// Replaces the page with a configuration problem (server not started):
/// no mascot, no Halo.
void pageStateShowConfigProblem(const char* problem);

/// Applies `view` at `nowMs` (millis()). Call often (the mascot pace needs
/// ~50 ms): LVGL is only touched where something really changed, so an
/// identical Instantané or a heartbeat never flickers. `ip` is "" without one.
void pageStateUpdate(const totem::ViewModel& view, uint32_t nowMs, const char* ip);

}  // namespace ui
