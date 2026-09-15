// Auth tests (issue #158, ADR-0014): only the shared `X-Island-Token` lets an
// Instantané through; an empty configured token lets nothing through.
#include <unity.h>

#include <cstdint>
#include <string>

#include "../support/files.h"
#include "auth.h"
#include "receiver.h"

using totem::AggregateState;
using totem::isAuthorized;
using totem::SnapshotReceiver;

void setUp() {}
void tearDown() {}

void test_accepts_the_configured_token() {
    TEST_ASSERT_TRUE(isAuthorized("s3cret-token", "s3cret-token"));
}

void test_refuses_a_wrong_token() {
    TEST_ASSERT_FALSE(isAuthorized("s3cret-token", "s3cret-tokem"));
    TEST_ASSERT_FALSE(isAuthorized("s3cret-token", "s3cret"));
    TEST_ASSERT_FALSE(isAuthorized("s3cret", "s3cret-token"));
}

void test_refuses_an_absent_token() {
    // WebServer::header() yields "" for a missing header.
    TEST_ASSERT_FALSE(isAuthorized("s3cret-token", ""));
    TEST_ASSERT_FALSE(isAuthorized("s3cret-token", nullptr));
}

void test_an_empty_configured_token_refuses_everything() {
    TEST_ASSERT_FALSE(isAuthorized("", ""));
    TEST_ASSERT_FALSE(isAuthorized("", "anything"));
    TEST_ASSERT_FALSE(isAuthorized(nullptr, nullptr));
}

// --- The POST /snapshot gate: token, then size, then contract. ---

static const char* kToken = "s3cret-token";
/// Read inside each test: a missing fixture must fail a test, not static init.
static std::string nominal() { return test_support::readFixture("snapshot-nominal.json"); }

static uint16_t post(SnapshotReceiver& receiver, const char* token, const std::string& body,
                     uint32_t nowMs) {
    return receiver.receive(token, body.data(), body.size(), nowMs);
}

void test_an_authorized_instantane_is_accepted_and_connects() {
    SnapshotReceiver receiver(kToken);
    TEST_ASSERT_EQUAL_UINT16(204, post(receiver, kToken, nominal(), 1000));
    TEST_ASSERT_TRUE(receiver.hasSnapshot());
    TEST_ASSERT_EQUAL(static_cast<int>(AggregateState::Done),
                      static_cast<int>(receiver.snapshot().state));
    TEST_ASSERT_TRUE(receiver.isConnected(1000));
}

void test_a_missing_or_wrong_token_is_401_before_anything_is_decoded() {
    SnapshotReceiver receiver(kToken);
    TEST_ASSERT_EQUAL_UINT16(401, post(receiver, "", nominal(), 1000));
    TEST_ASSERT_EQUAL_UINT16(401, post(receiver, "wrong", nominal(), 1000));
    TEST_ASSERT_FALSE(receiver.hasSnapshot());
    TEST_ASSERT_FALSE(receiver.isConnected(1000));
}

void test_a_401_leaves_state_and_freshness_unchanged() {
    SnapshotReceiver receiver(kToken);
    TEST_ASSERT_EQUAL_UINT16(204, post(receiver, kToken, nominal(), 1000));

    const std::string forged =
        "{\"counts\":{\"done\":0,\"idle\":0,\"waiting\":9,\"working\":0},"
        "\"sentAt\":1738420000,\"shutdown\":false,\"state\":\"waiting\",\"v\":1}";
    TEST_ASSERT_EQUAL_UINT16(401, post(receiver, "wrong", forged, 20000));

    TEST_ASSERT_EQUAL(static_cast<int>(AggregateState::Done),
                      static_cast<int>(receiver.snapshot().state));
    // Not refreshed at 20 000 ms: still expires 30 s after the accepted one.
    TEST_ASSERT_FALSE(receiver.isConnected(1000 + totem::Freshness::kTimeoutMs));
}

void test_an_empty_configured_token_answers_401_to_everyone() {
    SnapshotReceiver receiver("");
    TEST_ASSERT_EQUAL_UINT16(401, post(receiver, "", nominal(), 1000));
    TEST_ASSERT_FALSE(receiver.hasSnapshot());
}

void test_the_token_is_checked_before_the_size_and_the_contract() {
    SnapshotReceiver receiver(kToken);
    const std::string huge(totem::kMaxSnapshotBytes + 1, ' ');
    TEST_ASSERT_EQUAL_UINT16(401, post(receiver, "wrong", huge, 1000));
    TEST_ASSERT_EQUAL_UINT16(401, post(receiver, "wrong", "not json", 1000));
}

void test_an_oversized_body_is_413_even_when_its_start_is_valid() {
    SnapshotReceiver receiver(kToken);
    std::string padded = nominal() + std::string(totem::kMaxSnapshotBytes, ' ');
    TEST_ASSERT_EQUAL_UINT16(413, post(receiver, kToken, padded, 1000));
    // The server hands over at most kMaxSnapshotBytes but the full length.
    TEST_ASSERT_EQUAL_UINT16(
        413, receiver.receive(kToken, nominal().data(), totem::kMaxSnapshotBytes + 1, 1000));
    TEST_ASSERT_FALSE(receiver.hasSnapshot());
    TEST_ASSERT_FALSE(receiver.isConnected(1000));
}

void test_a_body_that_is_not_a_v1_instantane_is_400_and_changes_nothing() {
    SnapshotReceiver receiver(kToken);
    TEST_ASSERT_EQUAL_UINT16(204, post(receiver, kToken, nominal(), 1000));

    TEST_ASSERT_EQUAL_UINT16(400, post(receiver, kToken, "", 20000));
    TEST_ASSERT_EQUAL_UINT16(400, post(receiver, kToken, "not json", 20000));
    TEST_ASSERT_EQUAL_UINT16(
        400, post(receiver, kToken, "{\"shutdown\":true,\"state\":\"idle\"}", 20000));
    TEST_ASSERT_EQUAL_UINT16(
        400, post(receiver, kToken,
                  "{\"counts\":{\"done\":0,\"idle\":0,\"waiting\":0,\"working\":0},"
                  "\"sentAt\":1738420000,\"shutdown\":true,\"state\":\"idle\",\"v\":2}",
                  20000));

    TEST_ASSERT_EQUAL(static_cast<int>(AggregateState::Done),
                      static_cast<int>(receiver.snapshot().state));
    TEST_ASSERT_TRUE(receiver.isConnected(20000));
    TEST_ASSERT_FALSE(receiver.isConnected(1000 + totem::Freshness::kTimeoutMs));
}

void test_an_accepted_shutdown_instantane_disconnects_at_once() {
    SnapshotReceiver receiver(kToken);
    TEST_ASSERT_EQUAL_UINT16(204, post(receiver, kToken, nominal(), 1000));
    TEST_ASSERT_EQUAL_UINT16(
        204, post(receiver, kToken, test_support::readFixture("snapshot-empty.json"), 2000));
    TEST_ASSERT_FALSE(receiver.isConnected(2000));
    TEST_ASSERT_EQUAL(static_cast<int>(AggregateState::Idle),
                      static_cast<int>(receiver.snapshot().state));
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_accepts_the_configured_token);
    RUN_TEST(test_refuses_a_wrong_token);
    RUN_TEST(test_refuses_an_absent_token);
    RUN_TEST(test_an_empty_configured_token_refuses_everything);
    RUN_TEST(test_an_authorized_instantane_is_accepted_and_connects);
    RUN_TEST(test_a_missing_or_wrong_token_is_401_before_anything_is_decoded);
    RUN_TEST(test_a_401_leaves_state_and_freshness_unchanged);
    RUN_TEST(test_an_empty_configured_token_answers_401_to_everyone);
    RUN_TEST(test_the_token_is_checked_before_the_size_and_the_contract);
    RUN_TEST(test_an_oversized_body_is_413_even_when_its_start_is_valid);
    RUN_TEST(test_a_body_that_is_not_a_v1_instantane_is_400_and_changes_nothing);
    RUN_TEST(test_an_accepted_shutdown_instantane_disconnects_at_once);
    return UNITY_END();
}
