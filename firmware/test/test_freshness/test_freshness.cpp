// Freshness tests (issue #158): the Totem is Déconnecté at boot, after
// 30 s without an accepted Instantané, and at once on `shutdown`.
#include <unity.h>

#include "freshness.h"

using totem::Freshness;

void setUp() {}
void tearDown() {}

void test_is_disconnected_at_boot() {
    Freshness freshness;
    TEST_ASSERT_FALSE(freshness.isConnected(0));
    TEST_ASSERT_FALSE(freshness.isConnected(12345));
}

void test_stays_connected_for_30_seconds_after_an_accepted_instantane() {
    Freshness freshness;
    freshness.onAccepted(1000, false);
    TEST_ASSERT_TRUE(freshness.isConnected(1000));
    TEST_ASSERT_TRUE(freshness.isConnected(1000 + Freshness::kTimeoutMs - 1));
    TEST_ASSERT_FALSE(freshness.isConnected(1000 + Freshness::kTimeoutMs));
}

void test_the_timeout_is_30_000_ms() {
    TEST_ASSERT_EQUAL_UINT32(30000, Freshness::kTimeoutMs);
}

void test_shutdown_disconnects_at_once() {
    Freshness freshness;
    freshness.onAccepted(1000, false);
    freshness.onAccepted(2000, true);
    TEST_ASSERT_FALSE(freshness.isConnected(2000));
    TEST_ASSERT_FALSE(freshness.isConnected(2001));
}

void test_the_next_normal_instantane_after_shutdown_reconnects() {
    Freshness freshness;
    freshness.onAccepted(2000, true);
    freshness.onAccepted(5000, false);
    TEST_ASSERT_TRUE(freshness.isConnected(5000));
    TEST_ASSERT_TRUE(freshness.isConnected(5000 + Freshness::kTimeoutMs - 1));
}

void test_stays_connected_across_the_millis_wraparound() {
    Freshness freshness;
    const uint32_t beforeWrap = UINT32_MAX - 1000;  // ~49.7 days of uptime
    freshness.onAccepted(beforeWrap, false);
    TEST_ASSERT_TRUE(freshness.isConnected(5000));  // wrapped past zero, 6 s later
    TEST_ASSERT_FALSE(freshness.isConnected(beforeWrap + Freshness::kTimeoutMs));
}

void test_a_long_silence_never_reads_as_fresh_again_when_millis_wraps() {
    Freshness freshness;
    freshness.onAccepted(1000, false);
    TEST_ASSERT_FALSE(freshness.isConnected(1000 + Freshness::kTimeoutMs));
    // The loop keeps polling; 2^32 ms later the raw difference is small again.
    TEST_ASSERT_FALSE(freshness.isConnected(UINT32_MAX / 2));
    TEST_ASSERT_FALSE(freshness.isConnected(1000 + 10));
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_is_disconnected_at_boot);
    RUN_TEST(test_stays_connected_for_30_seconds_after_an_accepted_instantane);
    RUN_TEST(test_the_timeout_is_30_000_ms);
    RUN_TEST(test_shutdown_disconnects_at_once);
    RUN_TEST(test_the_next_normal_instantane_after_shutdown_reconnects);
    RUN_TEST(test_stays_connected_across_the_millis_wraparound);
    RUN_TEST(test_a_long_silence_never_reads_as_fresh_again_when_millis_wraps);
    return UNITY_END();
}
