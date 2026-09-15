// Plain-text status screen (issue #158).
//
// LVGL's built-in Montserrat fonts only cover ASCII: on-screen French is
// written in capitals without accents (DECONNECTE, TERMINE).
#include "text_status.h"

#include <lvgl.h>

namespace ui {

namespace {

lv_obj_t* gLink = nullptr;     // CONNECTE / DECONNECTE
lv_obj_t* gState = nullptr;    // aggregated state
lv_obj_t* gCounts = nullptr;   // per-state counts
lv_obj_t* gAddress = nullptr;  // IP
lv_obj_t* gMdns = nullptr;     // island-totem.local

constexpr lv_color_t kConnectedColor = LV_COLOR_MAKE(0xF2, 0xF2, 0xF2);
constexpr lv_color_t kDimColor = LV_COLOR_MAKE(0x70, 0x70, 0x70);
constexpr lv_color_t kProblemColor = LV_COLOR_MAKE(0xFF, 0x9F, 0x0A);

lv_obj_t* addLabel(lv_obj_t* parent, const lv_font_t* font) {
    lv_obj_t* label = lv_label_create(parent);
    lv_obj_set_style_text_font(label, font, 0);
    lv_obj_set_style_text_color(label, kConnectedColor, 0);
    lv_obj_set_style_text_align(label, LV_TEXT_ALIGN_CENTER, 0);
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

const char* stateText(totem::AggregateState state) {
    switch (state) {
        case totem::AggregateState::Waiting: return "EN ATTENTE";
        case totem::AggregateState::Done: return "TERMINE";
        case totem::AggregateState::Working: return "EN COURS";
        case totem::AggregateState::Idle: return "REPOS";
    }
    return "?";
}

}  // namespace

void textStatusBegin() {
    lv_obj_t* screen = lv_screen_active();
    lv_obj_set_style_bg_color(screen, lv_color_black(), 0);
    lv_obj_set_flex_flow(screen, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(screen, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_row(screen, 14, 0);

    gLink = addLabel(screen, &lv_font_montserrat_28);
    gState = addLabel(screen, &lv_font_montserrat_28);
    gCounts = addLabel(screen, &lv_font_montserrat_20);
    gAddress = addLabel(screen, &lv_font_montserrat_20);
    gMdns = addLabel(screen, &lv_font_montserrat_20);

    setText(gLink, "DECONNECTE");
    setColor(gLink, kDimColor);
    setText(gMdns, "island-totem.local");
}

void textStatusShowConfigProblem(const char* problem) {
    setText(gLink, "CONFIG A CORRIGER");
    setColor(gLink, kProblemColor);
    setText(gState, problem);
    setText(gCounts, "data/config.json puis\npio run -t uploadfs");
    setText(gAddress, "serveur non demarre");
    setText(gMdns, "");
}

void textStatusUpdate(const totem::SnapshotReceiver& receiver, uint32_t nowMs, const String& ip) {
    const bool connected = receiver.isConnected(nowMs);
    setText(gLink, connected ? "CONNECTE" : "DECONNECTE");
    setColor(gLink, connected ? kConnectedColor : kDimColor);

    // A Déconnecté Totem never shows a stale state.
    if (connected && receiver.hasSnapshot()) {
        const totem::Snapshot& snapshot = receiver.snapshot();
        char counts[96];
        snprintf(counts, sizeof counts, "attente %u   termine %u\nen cours %u   repos %u",
                 static_cast<unsigned>(snapshot.counts.waiting),
                 static_cast<unsigned>(snapshot.counts.done),
                 static_cast<unsigned>(snapshot.counts.working),
                 static_cast<unsigned>(snapshot.counts.idle));
        setText(gState, stateText(snapshot.state));
        setText(gCounts, counts);
    } else {
        setText(gState, "--");
        setText(gCounts, "");
    }

    char address[40];
    if (ip.length() > 0) {
        snprintf(address, sizeof address, "IP %s", ip.c_str());
    } else {
        snprintf(address, sizeof address, "Wi-Fi : connexion...");
    }
    setText(gAddress, address);
    setText(gMdns, "island-totem.local");
}

}  // namespace ui
