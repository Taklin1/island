// State page (issue #159).
//
// On-screen strings are English (ADR-0012), with the ADR-0012 state lexicon
// (`idle` for the aggregate too, as in contract v1). ASCII only, which is
// all LVGL's built-in Montserrat fonts cover.
//
// Layout (480x480): a centred column kept inside the Halo's edge margin —
// link, mascot 240x240, counts, IP, mDNS name. Every item has a fixed size,
// so a text change never moves the mascot (no relayout, no flicker).
#include "page_state.h"

#include <lvgl.h>

#include <cstdio>
#include <cstring>
#include <initializer_list>

#include "halo_layer.h"
#include "mascot_widget.h"
#include "pager.h"

namespace ui {

namespace {

lv_obj_t* gLink = nullptr;     // CONNECTED / DISCONNECTED
lv_obj_t* gMascot = nullptr;   // pixel-art bot
lv_obj_t* gCounts = nullptr;   // per-state counts
lv_obj_t* gAddress = nullptr;  // IP
lv_obj_t* gMdns = nullptr;     // island-totem.local

totem::PagePresenter gPresenter;

constexpr lv_color_t kTextColor = LV_COLOR_MAKE(0xF2, 0xF2, 0xF2);
constexpr lv_color_t kDimColor = LV_COLOR_MAKE(0x70, 0x70, 0x70);
constexpr lv_color_t kProblemColor = LV_COLOR_MAKE(0xFF, 0x9F, 0x0A);

lv_obj_t* addLabel(lv_obj_t* parent, const lv_font_t* font, int32_t height) {
    lv_obj_t* label = lv_label_create(parent);
    lv_obj_set_style_text_font(label, font, 0);
    lv_obj_set_style_text_color(label, kTextColor, 0);
    lv_obj_set_style_text_align(label, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_size(label, lv_pct(100), height);
    lv_label_set_long_mode(label, LV_LABEL_LONG_MODE_CLIP);
    lv_label_set_text(label, "");
    return label;
}

void setText(lv_obj_t* label, const char* text) {
    if (label == nullptr) return;
    if (strcmp(lv_label_get_text(label), text) != 0) lv_label_set_text(label, text);
}

void setColor(lv_obj_t* label, lv_color_t color) {
    if (label == nullptr) return;
    if (!lv_color_eq(lv_obj_get_style_text_color(label, LV_PART_MAIN), color)) {
        lv_obj_set_style_text_color(label, color, 0);
    }
}

}  // namespace

lv_obj_t* pageStateBegin() {
    // A page of its own (#160): the pager flips it with the Quotas page.
    lv_obj_t* page = pageCreate();

    const int32_t line20 = lv_font_montserrat_20.line_height;
    const int32_t line28 = lv_font_montserrat_28.line_height;
    gLink = addLabel(page, &lv_font_montserrat_20, line20);
    gMascot = mascotCreate(page);
    gCounts = addLabel(page, &lv_font_montserrat_28, 2 * line28 + 2);
    gAddress = addLabel(page, &lv_font_montserrat_20, line20);
    gMdns = addLabel(page, &lv_font_montserrat_20, line20);

    setText(gLink, "DISCONNECTED");
    setColor(gLink, kDimColor);
    setText(gMdns, "island-totem.local");

    haloBegin();
    // Déconnecté until the first accepted Instantané.
    pageStateUpdate(totem::makeViewModel(false, nullptr), lv_tick_get(), "");
    return page;
}

void pageStateShowConfigProblem(const char* problem) {
    haloSet(totem::HaloColor::Off);
    if (gMascot != nullptr) lv_obj_add_flag(gMascot, LV_OBJ_FLAG_HIDDEN);
    // Free heights: this screen is static, and its lines may wrap.
    for (lv_obj_t* label : {gLink, gCounts, gAddress, gMdns}) {
        if (label != nullptr) lv_obj_set_height(label, LV_SIZE_CONTENT);
    }
    setText(gLink, "CONFIG ERROR");
    setColor(gLink, kProblemColor);
    setText(gCounts, problem);
    setText(gAddress, "edit data/config.json then\npio run -t uploadfs");
    setText(gMdns, "server not started");
}

void pageStateUpdate(const totem::ViewModel& view, uint32_t nowMs, const char* ip) {
    const totem::PageUpdate update = gPresenter.step(view, nowMs);

    if (update.link) {
        setText(gLink, view.connected ? "CONNECTED" : "DISCONNECTED");
        setColor(gLink, view.connected ? kTextColor : kDimColor);
    }
    if (update.counts) {
        if (view.connected) {
            char counts[96];
            snprintf(counts, sizeof counts, "waiting %u   done %u\nworking %u   idle %u",
                     static_cast<unsigned>(view.counts.waiting),
                     static_cast<unsigned>(view.counts.done),
                     static_cast<unsigned>(view.counts.working),
                     static_cast<unsigned>(view.counts.idle));
            setText(gCounts, counts);
        } else {
            setText(gCounts, "");  // a Déconnecté Totem never shows stale counts
        }
    }
    if (update.halo) haloSet(view.halo);
    if (update.mascot) mascotShow(gMascot, gPresenter.frame(), view.grey);

    // The address is not part of the Instantané; setText skips equal texts.
    char address[40];
    if (ip != nullptr && ip[0] != '\0') {
        snprintf(address, sizeof address, "IP %s", ip);
    } else {
        snprintf(address, sizeof address, "Wi-Fi: connecting...");
    }
    setText(gAddress, address);
}

}  // namespace ui
