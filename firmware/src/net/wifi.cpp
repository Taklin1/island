// Wi-Fi station and mDNS (issue #158).
#include <ESPmDNS.h>
#include <WiFi.h>

#include <atomic>

#include "net.h"

namespace net {

namespace {

/// While disconnected, force a fresh attempt this often in case the
/// driver's auto-reconnect gave up (e.g. the AP was down at boot).
constexpr uint32_t kRetryIntervalMs = 30000;

std::atomic<bool> gGotIp{false};
std::string gSsid;
std::string gPassword;
uint32_t gLastAttemptMs = 0;

void onGotIp(arduino_event_id_t, arduino_event_info_t) { gGotIp = true; }

bool gMdnsStarted = false;

/// Restarts the responder so `island-totem.local` is announced on the new
/// link and address.
void announceMdns() {
    if (gMdnsStarted) MDNS.end();
    gMdnsStarted = MDNS.begin(kMdnsHostname);
    if (!gMdnsStarted) {
        Serial.println("[wifi] mDNS start failed");
        return;
    }
    MDNS.addService("http", "tcp", kHttpPort);
}

}  // namespace

void wifiBegin(const totem::TotemConfig& config) {
    gSsid = config.ssid;
    gPassword = config.password;
    WiFi.onEvent(onGotIp, ARDUINO_EVENT_WIFI_STA_GOT_IP);
    WiFi.setHostname(kMdnsHostname);  // DHCP host name; must precede mode()
    WiFi.mode(WIFI_STA);
    // On mains power: modem sleep adds hundreds of ms of latency, far too
    // close to the Relais' short timeout.
    WiFi.setSleep(false);
    WiFi.setAutoReconnect(true);
    WiFi.begin(gSsid.c_str(), gPassword.c_str());
    gLastAttemptMs = millis();
}

void wifiLoop() {
    // mDNS is restarted from the loop, never from the event task.
    if (gGotIp.exchange(false)) {
        Serial.printf("[wifi] connected, IP %s\n", WiFi.localIP().toString().c_str());
        announceMdns();
    }
    if (!WiFi.isConnected() && millis() - gLastAttemptMs >= kRetryIntervalMs) {
        gLastAttemptMs = millis();
        WiFi.disconnect();
        WiFi.begin(gSsid.c_str(), gPassword.c_str());
    }
}

bool wifiHasIp() { return WiFi.isConnected() && WiFi.localIP() != IPAddress(0, 0, 0, 0); }

String wifiIp() { return wifiHasIp() ? WiFi.localIP().toString() : String(); }

}  // namespace net
