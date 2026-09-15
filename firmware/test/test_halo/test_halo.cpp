// Halo tests (issue #159, CONTEXT.md § Halo): its colour follows the
// aggregated state the Mac sends, it is off when Déconnecté, and it breathes
// slowly on its own clock (never driven by the Instantanés).
#include <unity.h>

#include "halo.h"

using totem::AggregateState;
using totem::HaloColor;

void setUp() {}
void tearDown() {}

void test_orange_while_a_session_waits() {
    TEST_ASSERT_TRUE(totem::haloFor(true, AggregateState::Waiting) == HaloColor::Orange);
}

void test_green_while_a_session_has_finished_unacknowledged() {
    TEST_ASSERT_TRUE(totem::haloFor(true, AggregateState::Done) == HaloColor::Green);
}

void test_off_while_working_or_idle() {
    // The Mac folds the Acquittement into `state`: an acknowledged Session
    // arrives as working/idle and turns the Halo off.
    TEST_ASSERT_TRUE(totem::haloFor(true, AggregateState::Working) == HaloColor::Off);
    TEST_ASSERT_TRUE(totem::haloFor(true, AggregateState::Idle) == HaloColor::Off);
}

void test_never_lit_when_disconnected() {
    TEST_ASSERT_TRUE(totem::haloFor(false, AggregateState::Waiting) == HaloColor::Off);
    TEST_ASSERT_TRUE(totem::haloFor(false, AggregateState::Done) == HaloColor::Off);
}

void test_colours_are_the_edge_outline_system_colours() {
    // Liseré = SwiftUI Color.orange / Color.green (GlowWindow.swift), dark
    // appearance values: the Halo shows the colour the Liseré would have.
    TEST_ASSERT_EQUAL_HEX32(0xFF9F0A, totem::haloRgb(HaloColor::Orange));
    TEST_ASSERT_EQUAL_HEX32(0x30D158, totem::haloRgb(HaloColor::Green));
}

void test_the_glow_fades_inwards_band_by_band() {
    TEST_ASSERT_TRUE(totem::kHaloBandCount >= 3 && totem::kHaloBandCount <= 4);
    for (uint8_t band = 1; band < totem::kHaloBandCount; ++band) {
        TEST_ASSERT_TRUE(totem::kHaloBandOpa[band] < totem::kHaloBandOpa[band - 1]);
    }
}

void test_breathing_stays_between_its_dim_and_full_levels() {
    uint8_t lowest = 255;
    uint8_t highest = 0;
    for (uint32_t now = 0; now < 2 * totem::kHaloBreathPeriodMs; now += 10) {
        const uint8_t level = totem::haloBreathLevel(now);
        if (level < lowest) lowest = level;
        if (level > highest) highest = level;
    }
    TEST_ASSERT_EQUAL_UINT8(totem::kHaloBreathMin, lowest);
    TEST_ASSERT_EQUAL_UINT8(255, highest);
    // Discreet: never below 60 % of the full glow.
    TEST_ASSERT_TRUE(totem::kHaloBreathMin >= 153);
}

void test_breathing_is_slow_and_smooth() {
    TEST_ASSERT_TRUE(totem::kHaloBreathPeriodMs >= 6000);
    for (uint32_t now = 0; now < totem::kHaloBreathPeriodMs; now += 100) {
        const int step = totem::haloBreathLevel(now + 100) - totem::haloBreathLevel(now);
        TEST_ASSERT_TRUE_MESSAGE(step <= 8 && step >= -8, "a jump over 100 ms reads as a blink");
    }
}

void test_breathing_is_periodic_and_seamless_across_the_millis_wrap() {
    TEST_ASSERT_EQUAL_UINT8(totem::haloBreathLevel(1234),
                            totem::haloBreathLevel(1234 + totem::kHaloBreathPeriodMs));
    // The period divides 2^32, so millis() wrapping never jumps the level.
    const int step = totem::haloBreathLevel(0) - totem::haloBreathLevel(UINT32_MAX - 99);
    TEST_ASSERT_TRUE(step <= 8 && step >= -8);
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_orange_while_a_session_waits);
    RUN_TEST(test_green_while_a_session_has_finished_unacknowledged);
    RUN_TEST(test_off_while_working_or_idle);
    RUN_TEST(test_never_lit_when_disconnected);
    RUN_TEST(test_colours_are_the_edge_outline_system_colours);
    RUN_TEST(test_the_glow_fades_inwards_band_by_band);
    RUN_TEST(test_breathing_stays_between_its_dim_and_full_levels);
    RUN_TEST(test_breathing_is_slow_and_smooth);
    RUN_TEST(test_breathing_is_periodic_and_seamless_across_the_millis_wrap);
    return UNITY_END();
}
