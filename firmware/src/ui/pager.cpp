// Pager (issue #160).
#include "pager.h"

namespace ui {

namespace {

lv_obj_t* gStatePage = nullptr;
lv_obj_t* gQuotasPage = nullptr;

void setShown(lv_obj_t* page, bool shown) {
    if (page == nullptr || lv_obj_has_flag(page, LV_OBJ_FLAG_HIDDEN) == !shown) return;
    if (shown) {
        lv_obj_remove_flag(page, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_add_flag(page, LV_OBJ_FLAG_HIDDEN);
    }
}

}  // namespace

lv_obj_t* pageCreate() {
    lv_obj_t* screen = lv_screen_active();
    lv_obj_set_style_bg_color(screen, lv_color_black(), 0);
    lv_obj_set_style_pad_all(screen, 0, 0);
    // The touch only navigates (ADR-0013): no object reacts to a press — not
    // the screen, not a page — so LVGL never restyles or redraws on one.
    lv_obj_remove_flag(screen, static_cast<lv_obj_flag_t>(LV_OBJ_FLAG_CLICKABLE |
                                                          LV_OBJ_FLAG_SCROLLABLE));

    lv_obj_t* page = lv_obj_create(screen);
    lv_obj_remove_style_all(page);  // transparent, no border, no padding
    lv_obj_remove_flag(page, static_cast<lv_obj_flag_t>(LV_OBJ_FLAG_CLICKABLE |
                                                        LV_OBJ_FLAG_SCROLLABLE));
    lv_obj_set_size(page, lv_pct(100), lv_pct(100));
    lv_obj_set_style_pad_all(page, kPagePad, 0);
    lv_obj_set_flex_flow(page, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(page, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_row(page, kPageRowGap, 0);
    return page;
}

void pagerBegin(lv_obj_t* statePage, lv_obj_t* quotasPage) {
    gStatePage = statePage;
    gQuotasPage = quotasPage;
    if (gStatePage != nullptr) lv_obj_remove_flag(gStatePage, LV_OBJ_FLAG_HIDDEN);
    if (gQuotasPage != nullptr) lv_obj_add_flag(gQuotasPage, LV_OBJ_FLAG_HIDDEN);
}

void pagerShow(totem::Page page) {
    const bool quotas = page == totem::Page::Quotas;
    // Hide first, then show: never both pages drawn in the same refresh.
    setShown(quotas ? gStatePage : gQuotasPage, false);
    setShown(quotas ? gQuotasPage : gStatePage, true);
}

}  // namespace ui
