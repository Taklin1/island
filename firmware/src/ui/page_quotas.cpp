// Quotas page (issue #160).
//
// On-screen strings are English ASCII (ADR-0012), what LVGL's built-in
// Montserrat fonts cover; the reset icon is their LV_SYMBOL_REFRESH glyph
// (the Mac's "↺" is not in the font).
//
// Layout (480x480, inside the Halo margin): title, then per window a row
// "5 h ....... 24%", its bar, and for 5 h the countdown line. An absent
// window hides its group; no window at all shows "no quotas" — never 0 %.
// Colours and rules come from lib/totem_core/quota_view.h, which MUST mirror
// Sources/IslandUI/QuotaGauges.swift.
#include "page_quotas.h"

#include <cstdio>
#include <cstring>
#include <initializer_list>

#include "pager.h"

namespace ui {

namespace {

constexpr int32_t kBarHeight = 22;
constexpr int32_t kGroupGap = 28;
/// Déconnecté: every colour is mixed towards black, keeping this much of it.
constexpr uint8_t kDimMix = 90;

constexpr lv_color_t kTitleColor = LV_COLOR_MAKE(0x9A, 0x9A, 0x9A);
/// The state page's DISCONNECTED grey.
constexpr lv_color_t kDisconnectedColor = LV_COLOR_MAKE(0x70, 0x70, 0x70);
constexpr lv_color_t kTextColor = LV_COLOR_MAKE(0xF2, 0xF2, 0xF2);
constexpr lv_color_t kSecondaryColor = LV_COLOR_MAKE(0xB0, 0xB0, 0xB0);
constexpr lv_color_t kTrackColor = LV_COLOR_MAKE(0x2A, 0x2A, 0x2A);

struct Gauge {
    lv_obj_t* group = nullptr;
    lv_obj_t* window = nullptr;   // "5 h" / "7 d"
    lv_obj_t* percent = nullptr;  // "24%"
    lv_obj_t* bar = nullptr;
};

lv_obj_t* gTitle = nullptr;
Gauge gFiveHour;
Gauge gSevenDay;
lv_obj_t* gCountdown = nullptr;
lv_obj_t* gNoQuotas = nullptr;

lv_obj_t* addBox(lv_obj_t* parent) {
    lv_obj_t* box = lv_obj_create(parent);
    lv_obj_remove_style_all(box);
    lv_obj_remove_flag(box, static_cast<lv_obj_flag_t>(LV_OBJ_FLAG_CLICKABLE |
                                                       LV_OBJ_FLAG_SCROLLABLE));
    lv_obj_set_width(box, lv_pct(100));
    return box;
}

lv_obj_t* addLabel(lv_obj_t* parent, const lv_font_t* font, lv_color_t color) {
    lv_obj_t* label = lv_label_create(parent);
    lv_obj_set_style_text_font(label, font, 0);
    lv_obj_set_style_text_color(label, color, 0);
    lv_label_set_long_mode(label, LV_LABEL_LONG_MODE_CLIP);
    lv_label_set_text(label, "");
    return label;
}

void setText(lv_obj_t* label, const char* text) {
    if (strcmp(lv_label_get_text(label), text) != 0) lv_label_set_text(label, text);
}

void setTextColor(lv_obj_t* label, lv_color_t color) {
    if (!lv_color_eq(lv_obj_get_style_text_color(label, LV_PART_MAIN), color)) {
        lv_obj_set_style_text_color(label, color, 0);
    }
}

void setBg(lv_obj_t* obj, lv_part_t part, lv_color_t color) {
    if (!lv_color_eq(lv_obj_get_style_bg_color(obj, part), color)) {
        lv_obj_set_style_bg_color(obj, color, part);
    }
}

void setShown(lv_obj_t* obj, bool shown) {
    if (lv_obj_has_flag(obj, LV_OBJ_FLAG_HIDDEN) == !shown) return;
    if (shown) {
        lv_obj_remove_flag(obj, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_add_flag(obj, LV_OBJ_FLAG_HIDDEN);
    }
}

lv_color_t shade(lv_color_t color, bool dimmed) {
    return dimmed ? lv_color_mix(color, lv_color_black(), kDimMix) : color;
}

Gauge addGauge(lv_obj_t* page, const char* windowLabel) {
    Gauge gauge;
    gauge.group = addBox(page);
    lv_obj_set_height(gauge.group, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(gauge.group, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(gauge.group, kPageRowGap, 0);

    const int32_t line28 = lv_font_montserrat_28.line_height;
    lv_obj_t* row = addBox(gauge.group);
    lv_obj_set_height(row, line28);
    gauge.window = addLabel(row, &lv_font_montserrat_28, kSecondaryColor);
    lv_obj_align(gauge.window, LV_ALIGN_LEFT_MID, 0, 0);
    lv_label_set_text(gauge.window, windowLabel);
    gauge.percent = addLabel(row, &lv_font_montserrat_28, kTextColor);
    lv_obj_align(gauge.percent, LV_ALIGN_RIGHT_MID, 0, 0);

    gauge.bar = lv_bar_create(gauge.group);
    lv_obj_remove_style_all(gauge.bar);
    lv_obj_remove_flag(gauge.bar, static_cast<lv_obj_flag_t>(LV_OBJ_FLAG_CLICKABLE |
                                                             LV_OBJ_FLAG_SCROLLABLE));
    lv_obj_set_size(gauge.bar, lv_pct(100), kBarHeight);
    lv_bar_set_range(gauge.bar, 0, 100);
    for (lv_part_t part : {LV_PART_MAIN, LV_PART_INDICATOR}) {
        lv_obj_set_style_bg_opa(gauge.bar, LV_OPA_COVER, part);
        lv_obj_set_style_radius(gauge.bar, LV_RADIUS_CIRCLE, part);
    }
    lv_obj_set_style_bg_color(gauge.bar, kTrackColor, LV_PART_MAIN);
    return gauge;
}

void showGauge(Gauge& gauge, const totem::GaugeView& view, bool dimmed) {
    setShown(gauge.group, view.present);
    if (!view.present) return;
    char percent[16];
    snprintf(percent, sizeof percent, "%d%%", static_cast<int>(view.percent));
    setText(gauge.percent, percent);
    setTextColor(gauge.window, shade(kSecondaryColor, dimmed));
    setTextColor(gauge.percent, shade(kTextColor, dimmed));
    if (lv_bar_get_value(gauge.bar) != view.fill) {
        lv_bar_set_value(gauge.bar, view.fill, LV_ANIM_OFF);
    }
    setBg(gauge.bar, LV_PART_MAIN, shade(kTrackColor, dimmed));
    setBg(gauge.bar, LV_PART_INDICATOR,
          shade(lv_color_hex(totem::gaugeRgb(view.color)), dimmed));
}

}  // namespace

lv_obj_t* pageQuotasBegin() {
    lv_obj_t* page = pageCreate();

    const int32_t line20 = lv_font_montserrat_20.line_height;
    const int32_t line28 = lv_font_montserrat_28.line_height;

    gTitle = addLabel(page, &lv_font_montserrat_20, kTitleColor);
    lv_obj_set_size(gTitle, lv_pct(100), line20);
    lv_obj_set_style_text_align(gTitle, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_margin_bottom(gTitle, kGroupGap - kPageRowGap, 0);

    gFiveHour = addGauge(page, totem::kFiveHourLabel);
    // Fixed height, empty when unknown: the 7 d gauge never jumps.
    gCountdown = addLabel(gFiveHour.group, &lv_font_montserrat_28,
                          lv_color_hex(totem::kCountdownRgb));
    lv_obj_set_size(gCountdown, lv_pct(100), line28);
    lv_obj_set_style_text_align(gCountdown, LV_TEXT_ALIGN_RIGHT, 0);
    lv_obj_set_style_margin_bottom(gFiveHour.group, kGroupGap - kPageRowGap, 0);

    gSevenDay = addGauge(page, totem::kSevenDayLabel);

    gNoQuotas = addLabel(page, &lv_font_montserrat_28, kSecondaryColor);
    lv_obj_set_size(gNoQuotas, lv_pct(100), line28);
    lv_obj_set_style_text_align(gNoQuotas, LV_TEXT_ALIGN_CENTER, 0);
    lv_label_set_text(gNoQuotas, "no quotas");

    // Déconnecté until the first accepted Instantané.
    totem::QuotaView boot;
    boot.dimmed = true;
    pageQuotasUpdate(boot);
    return page;
}

void pageQuotasUpdate(const totem::QuotaView& view) {
    if (gTitle == nullptr) return;
    setText(gTitle, view.dimmed ? "QUOTAS - DISCONNECTED" : "QUOTAS");
    setTextColor(gTitle, view.dimmed ? kDisconnectedColor : kTitleColor);

    showGauge(gFiveHour, view.fiveHour, view.dimmed);
    showGauge(gSevenDay, view.sevenDay, view.dimmed);

    char countdown[32] = "";
    if (view.hasCountdown) {
        char left[16];
        totem::formatCountdown(view.countdownSeconds, left, sizeof left);
        snprintf(countdown, sizeof countdown, LV_SYMBOL_REFRESH " %s", left);
    }
    setText(gCountdown, countdown);
    setTextColor(gCountdown, shade(lv_color_hex(totem::kCountdownRgb), view.dimmed));

    setShown(gNoQuotas, !view.hasQuotas());
    setTextColor(gNoQuotas, shade(kSecondaryColor, view.dimmed));
}

}  // namespace ui
