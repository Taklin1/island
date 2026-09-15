// Network side of the Totem (issue #158): Wi-Fi station, mDNS name and the
// inbound-only POST /snapshot server. No outgoing request, no channel back to
// the app (ADR-0013).
#pragma once

#include <Arduino.h>

#include "config.h"
#include "receiver.h"

namespace net {

/// mDNS host name: the Totem answers at `island-totem.local`.
constexpr const char* kMdnsHostname = "island-totem";
constexpr uint16_t kHttpPort = 80;

/// Joins the configured 2.4 GHz network, modem sleep off, auto-reconnect on.
void wifiBegin(const totem::TotemConfig& config);

/// Keeps the link up and (re)announces mDNS after every (re)connection.
void wifiLoop();

bool wifiHasIp();

/// The current station IP as text, "" without one.
String wifiIp();

/// Registers the routes and starts listening on all interfaces (so the
/// server stays reachable across IP changes). `receiver` must outlive it.
void snapshotServerBegin(totem::SnapshotReceiver& receiver);

void snapshotServerLoop();

}  // namespace net
