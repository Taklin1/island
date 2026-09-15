// Inbound POST /snapshot server (issue #158, ADR-0014).
//
// The body is streamed through WebServer's raw handler rather than
// `server.arg("plain")`: the plain path buffers the whole declared
// Content-Length on the heap and waits up to 5 s for it, which a board
// without PSRAM and a single-threaded loop cannot afford.
#include <WebServer.h>

#include "net.h"

namespace net {

namespace {

constexpr const char* kTokenHeader = "X-Island-Token";
/// Stream timeout while reading a body (WebServer's default is 5 s).
constexpr uint32_t kBodyReadTimeoutMs = 1000;
/// A connected client that sends nothing is dropped after this, so an idle
/// socket cannot hold the single-client server for WebServer's 5 s.
constexpr uint32_t kIdleClientTimeoutMs = 1000;
/// Past this many bytes the connection is cut without an answer: draining a
/// huge upload would stall the loop.
constexpr size_t kHardBodyLimitBytes = 16 * totem::kMaxSnapshotBytes;

WebServer server(kHttpPort);
totem::SnapshotReceiver* gReceiver = nullptr;

// The first kMaxSnapshotBytes of the current body, and its full length.
char gBody[totem::kMaxSnapshotBytes];
size_t gBodyStored = 0;
size_t gBodyLength = 0;
bool gBodyStreamed = false;

int gIdleFd = -1;
uint32_t gIdleSinceMs = 0;

void onBodyChunk() {
    HTTPRaw& raw = server.raw();
    switch (raw.status) {
        case RAW_START:
            gBodyStored = 0;
            gBodyLength = 0;
            gBodyStreamed = true;
            server.client().setTimeout(kBodyReadTimeoutMs);
            break;
        case RAW_WRITE: {
            const size_t room = sizeof gBody - gBodyStored;
            const size_t kept = raw.currentSize < room ? raw.currentSize : room;
            memcpy(gBody + gBodyStored, raw.buf, kept);
            gBodyStored += kept;
            gBodyLength = raw.totalSize;
            if (gBodyLength > kHardBodyLimitBytes) server.client().stop();
            break;
        }
        case RAW_END:
            break;
        case RAW_ABORTED:
            // No handler runs for an aborted request: drop its partial body
            // so it can never be mistaken for a later request's.
            gBodyStreamed = false;
            gBodyStored = 0;
            gBodyLength = 0;
            break;
    }
}

void onSnapshot() {
    const String token = server.header(kTokenHeader);
    // A POST that did not go through the raw path (e.g. multipart) has no body.
    const size_t length = gBodyStreamed ? gBodyLength : 0;
    const uint16_t status = gReceiver->receive(token.c_str(), gBody, length, millis());
    gBodyStreamed = false;
    gBodyStored = 0;
    gBodyLength = 0;
    server.send(status);
}

void onWrongMethod() {
    server.sendHeader("Allow", "POST");
    server.send(405);
}

void onNotFound() { server.send(404); }

void dropIdleClient() {
    NetworkClient& client = server.client();
    if (!client.connected()) {
        gIdleFd = -1;
        return;
    }
    if (client.fd() != gIdleFd) {
        gIdleFd = client.fd();
        gIdleSinceMs = millis();
    } else if (client.available() == 0 && millis() - gIdleSinceMs >= kIdleClientTimeoutMs) {
        client.stop();
        gIdleFd = -1;
    }
}

}  // namespace

void snapshotServerBegin(totem::SnapshotReceiver& receiver) {
    gReceiver = &receiver;
    const char* headers[] = {kTokenHeader};
    server.collectHeaders(headers, 1);
    // First match wins: POST /snapshot, then any other method on it.
    server.on("/snapshot", HTTP_POST, onSnapshot, onBodyChunk);
    server.on("/snapshot", HTTP_ANY, onWrongMethod);
    server.onNotFound(onNotFound);
    server.begin();
    Serial.printf("[server] listening on port %u\n", kHttpPort);
}

void snapshotServerLoop() {
    server.handleClient();
    dropIdleClient();
}

}  // namespace net
