// The Totem Quotas page (issue #160): the 5 h and 7 d gauges as in the
// Extended Island, the 5 h reset countdown, "no quotas" when the Mac sends
// none; dimmed and frozen when Déconnecté.
#pragma once

#include <lvgl.h>

#include "quota_view.h"

namespace ui {

/// Builds the page once, hidden; returns it for the pager.
lv_obj_t* pageQuotasBegin();

/// Shows `view`. Only labels whose text or colour really changed are touched.
void pageQuotasUpdate(const totem::QuotaView& view);

}  // namespace ui
