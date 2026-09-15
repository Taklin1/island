// island Totem firmware (issue #158): a pure display of the Instantané the
// app pushes over the LAN (ADR-0013, ADR-0014).
#include <Arduino.h>
#include <LittleFS.h>

#include <string>

#include "board/board.h"
#include "config.h"
#include "net/net.h"
#include "receiver.h"
#include "ui/text_status.h"

namespace {

constexpr const char* kConfigPath = "/config.json";
constexpr size_t kMaxConfigBytes = 1024;
constexpr uint32_t kUiRefreshMs = 250;

bool gDisplayReady = false;
bool gServing = false;
bool gServerStarted = false;
totem::SnapshotReceiver* gReceiver = nullptr;
uint32_t gLastUiMs = 0;

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
    if (gDisplayReady) ui::textStatusBegin();

    totem::TotemConfig config;
    if (const char* problem = loadConfig(config)) {
        Serial.printf("[config] %s: server not started\n", problem);
        if (gDisplayReady) ui::textStatusShowConfigProblem(problem);
        return;
    }

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
            ui::textStatusUpdate(*gReceiver, gLastUiMs, net::wifiIp());
        }
    }
    board::displayLoop();
    delay(2);
}
