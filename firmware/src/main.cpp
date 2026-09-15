// island Totem firmware (issue #158): a pure display of the Instantané the
// app pushes over the LAN (ADR-0013, ADR-0014).
#include <Arduino.h>
#include <LittleFS.h>

#include <string>

#include <lvgl.h>

#include "board/board.h"
#include "brightness.h"
#include "config.h"
#include "gesture.h"
#include "net/net.h"
#include "quota_view.h"
#include "receiver.h"
#include "ui/page_quotas.h"
#include "ui/page_state.h"
#include "ui/pager.h"
#include "view_model.h"

namespace {

constexpr const char* kConfigPath = "/config.json";
constexpr size_t kMaxConfigBytes = 1024;
// Fast enough for the mascot's pace (4 fps at most); LVGL is only touched on
// a real change.
constexpr uint32_t kUiRefreshMs = 50;

bool gDisplayReady = false;
bool gServing = false;
bool gServerStarted = false;
totem::SnapshotReceiver* gReceiver = nullptr;
uint32_t gLastUiMs = 0;
totem::QuotaPresenter gQuotas;
totem::TouchNavigator gNavigator;

/// LVGL input device read callback (issue #160), polled on LVGL's input
/// timer. The touch only navigates locally (ADR-0013): pages and brightness,
/// never a request out, nothing towards the app.
void readTouch(lv_indev_t*, lv_indev_data_t* data) {
    int32_t x = 0;
    int32_t y = 0;
    const bool touched = board::touchRead(x, y);
    data->point.x = x;
    data->point.y = y;
    data->state = touched ? LV_INDEV_STATE_PRESSED : LV_INDEV_STATE_RELEASED;
    // Axis check on the board (README checklist): where each press lands.
    static bool wasTouched = false;
    if (touched && !wasTouched) Serial.printf("[touch] down at %d,%d\n", (int)x, (int)y);
    wasTouched = touched;

    const totem::TouchStep step = gNavigator.step(touched, lv_tick_get());
    if (step.pageChanged) ui::pagerShow(gNavigator.page());
    if (step.brightnessStep) brightness::step();
}

void touchBegin() {
    if (!board::touchBegin()) return;  // no touch: the state page stays up
    lv_indev_t* touch = lv_indev_create();
    lv_indev_set_type(touch, LV_INDEV_TYPE_POINTER);
    lv_indev_set_read_cb(touch, readTouch);
}

/// Loads `config.json` from LittleFS. Returns nullptr on success, otherwise
/// the on-screen reason (English, ADR-0012).
const char* loadConfig(totem::TotemConfig& config) {
    // Never format: an unformatted partition means `uploadfs` was not run.
    if (!LittleFS.begin(false)) return "LittleFS empty";
    File file = LittleFS.open(kConfigPath, "r");
    if (!file) return "config.json missing";
    if (file.size() > kMaxConfigBytes) return "config.json too large";
    std::string json(file.size(), '\0');
    const size_t read = file.read(reinterpret_cast<uint8_t*>(&json[0]), json.size());
    file.close();
    if (read != json.size()) return "config.json unreadable";

    switch (totem::parseConfig(json.data(), json.size(), config)) {
        case totem::ConfigResult::Ok: return nullptr;
        case totem::ConfigResult::InvalidJson: return "config.json invalid";
        case totem::ConfigResult::MissingSsid: return "ssid missing";
        case totem::ConfigResult::MissingToken: return "token empty";
    }
    return "config.json invalid";
}

}  // namespace

void setup() {
    Serial.begin(115200);

    gDisplayReady = board::displayBegin(board::begin());
    if (gDisplayReady) {
        brightness::begin();
        // Both pages are built once; a tap only flips LV_OBJ_FLAG_HIDDEN.
        lv_obj_t* statePage = ui::pageStateBegin();
        lv_obj_t* quotasPage = ui::pageQuotasBegin();
        ui::pagerBegin(statePage, quotasPage);
    }

    totem::TotemConfig config;
    if (const char* problem = loadConfig(config)) {
        Serial.printf("[config] %s: server not started\n", problem);
        // No touch either: the problem screen stays in view.
        if (gDisplayReady) ui::pageStateShowConfigProblem(problem);
        return;
    }

    if (gDisplayReady) touchBegin();
    gReceiver = new totem::SnapshotReceiver(config.token.c_str());
    net::wifiBegin(config);
    gServing = true;
}

void loop() {
    if (gServing) {
        net::wifiLoop();
        // Listen on all interfaces once the stack has an address; the socket
        // then survives reconnections and IP changes.
        if (!gServerStarted && net::wifiHasIp()) {
            net::snapshotServerBegin(*gReceiver);
            gServerStarted = true;
        }
        if (gServerStarted) net::snapshotServerLoop();

        if (gDisplayReady && millis() - gLastUiMs >= kUiRefreshMs) {
            gLastUiMs = millis();
            ui::pageStateUpdate(totem::viewModelFor(*gReceiver, gLastUiMs), gLastUiMs,
                                net::wifiIp().c_str());
            if (gQuotas.update(*gReceiver, gLastUiMs)) ui::pageQuotasUpdate(gQuotas.view());
        }
    }
    board::displayLoop();
    delay(2);
}
