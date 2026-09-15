// Touch gesture tests (issue #160): a tap flips the state page and the Quotas
// page, a long press steps the brightness once, the Quotas page returns to
// the state page after ~30 s without a touch. The touch does nothing else.
#include <unity.h>

#include "brightness_levels.h"
#include "gesture.h"

using totem::Page;
using totem::TouchNavigator;
using totem::TouchStep;

namespace {

/// What happened while the finger was `touched` from `fromMs` to `toMs`
/// (excluded), sampled every `periodMs` like LVGL's input device timer.
struct Outcome {
    int pageChanges = 0;
    int brightnessSteps = 0;
};

Outcome feed(TouchNavigator& nav, bool touched, uint32_t fromMs, uint32_t toMs,
             uint32_t periodMs = 30) {
    Outcome outcome;
    for (uint32_t now = fromMs; now < toMs; now += periodMs) {
        const TouchStep step = nav.step(touched, now);
        if (step.pageChanged) ++outcome.pageChanges;
        if (step.brightnessStep) ++outcome.brightnessSteps;
    }
    return outcome;
}

/// One quick tap at `atMs`, then idle for a while.
Outcome tap(TouchNavigator& nav, uint32_t atMs) {
    Outcome pressed = feed(nav, true, atMs, atMs + 120);
    Outcome released = feed(nav, false, atMs + 120, atMs + 400);
    return {pressed.pageChanges + released.pageChanges,
            pressed.brightnessSteps + released.brightnessSteps};
}

}  // namespace

void setUp() {}
void tearDown() {}

void test_the_totem_starts_on_the_state_page() {
    TouchNavigator nav;
    TEST_ASSERT_TRUE(nav.page() == Page::State);
}

void test_a_tap_flips_between_the_state_page_and_the_quotas_page() {
    TouchNavigator nav;

    Outcome first = tap(nav, 1000);
    TEST_ASSERT_EQUAL_INT(1, first.pageChanges);
    TEST_ASSERT_EQUAL_INT(0, first.brightnessSteps);
    TEST_ASSERT_TRUE(nav.page() == Page::Quotas);

    TEST_ASSERT_EQUAL_INT(1, tap(nav, 2000).pageChanges);
    TEST_ASSERT_TRUE(nav.page() == Page::State);
}

void test_a_long_press_steps_the_brightness_once_and_never_flips_the_page() {
    TouchNavigator nav;

    Outcome held = feed(nav, true, 1000, 1000 + 5000);  // finger kept down 5 s
    Outcome released = feed(nav, false, 6000, 6400);

    TEST_ASSERT_EQUAL_INT(1, held.brightnessSteps);  // no repeat while held
    TEST_ASSERT_EQUAL_INT(0, released.brightnessSteps);
    TEST_ASSERT_EQUAL_INT(0, held.pageChanges + released.pageChanges);
    TEST_ASSERT_TRUE(nav.page() == Page::State);
}

void test_the_long_press_fires_at_its_threshold_while_the_finger_is_down() {
    TouchNavigator nav;
    TEST_ASSERT_TRUE(totem::kLongPressMs >= 400 && totem::kLongPressMs <= 800);

    nav.step(true, 1000);
    TEST_ASSERT_FALSE(nav.step(true, 1000 + totem::kLongPressMs - 1).brightnessStep);
    TEST_ASSERT_TRUE(nav.step(true, 1000 + totem::kLongPressMs).brightnessStep);
}

void test_each_long_press_is_one_step() {
    TouchNavigator nav;
    int steps = 0;
    for (uint32_t press = 0; press < 3; ++press) {
        const uint32_t start = 1000 + press * 2000;
        steps += feed(nav, true, start, start + 900).brightnessSteps;
        steps += feed(nav, false, start + 900, start + 1500).brightnessSteps;
    }
    TEST_ASSERT_EQUAL_INT(3, steps);
}

void test_a_press_just_under_the_threshold_is_a_tap() {
    TouchNavigator nav;
    Outcome pressed = feed(nav, true, 1000, 1000 + totem::kLongPressMs - 30);
    Outcome released = feed(nav, false, 1000 + totem::kLongPressMs - 30, 3000);
    TEST_ASSERT_EQUAL_INT(0, pressed.brightnessSteps + released.brightnessSteps);
    TEST_ASSERT_EQUAL_INT(1, pressed.pageChanges + released.pageChanges);
}

void test_a_dropped_report_during_a_press_does_not_split_it_into_two_taps() {
    TouchNavigator nav;
    Outcome outcome;
    const auto add = [&outcome](const Outcome& more) {
        outcome.pageChanges += more.pageChanges;
        outcome.brightnessSteps += more.brightnessSteps;
    };
    add(feed(nav, true, 1000, 1090));
    add(feed(nav, false, 1090, 1120));  // one lost sample, under the debounce
    add(feed(nav, true, 1120, 1210));
    add(feed(nav, false, 1210, 1600));

    TEST_ASSERT_TRUE(totem::kTouchDebounceMs >= 30 && totem::kTouchDebounceMs <= 100);
    TEST_ASSERT_EQUAL_INT(1, outcome.pageChanges);
    TEST_ASSERT_TRUE(nav.page() == Page::Quotas);
}

void test_a_dropped_report_during_a_long_press_does_not_add_a_tap_or_a_step() {
    TouchNavigator nav;
    Outcome first = feed(nav, true, 1000, 1900);
    Outcome glitch = feed(nav, false, 1900, 1930);
    Outcome second = feed(nav, true, 1930, 2800);
    Outcome released = feed(nav, false, 2800, 3200);

    TEST_ASSERT_EQUAL_INT(1, first.brightnessSteps + glitch.brightnessSteps +
                                 second.brightnessSteps + released.brightnessSteps);
    TEST_ASSERT_EQUAL_INT(0, first.pageChanges + glitch.pageChanges + second.pageChanges +
                                 released.pageChanges);
}

void test_the_tap_lands_once_the_release_is_confirmed() {
    TouchNavigator nav;
    feed(nav, true, 1000, 1100);
    TEST_ASSERT_FALSE(nav.step(false, 1100).pageChanged);
    TEST_ASSERT_FALSE(nav.step(false, 1100 + totem::kTouchDebounceMs - 1).pageChanged);
    TEST_ASSERT_TRUE(nav.step(false, 1100 + totem::kTouchDebounceMs).pageChanged);
}

// --- Automatic return to the state page ---

void test_the_quotas_page_returns_to_the_state_page_after_30_s_without_a_touch() {
    TEST_ASSERT_TRUE(totem::kAutoReturnMs >= 20000 && totem::kAutoReturnMs <= 40000);
    TouchNavigator nav;
    feed(nav, true, 1000, 1090);  // last touched sample at 1060
    feed(nav, false, 1090, 1300);
    TEST_ASSERT_TRUE(nav.page() == Page::Quotas);

    const uint32_t lastTouch = 1060;
    TEST_ASSERT_EQUAL_INT(0, feed(nav, false, 1300, lastTouch + totem::kAutoReturnMs).pageChanges);
    TEST_ASSERT_TRUE(nav.page() == Page::Quotas);
    TEST_ASSERT_TRUE(nav.step(false, lastTouch + totem::kAutoReturnMs).pageChanged);
    TEST_ASSERT_TRUE(nav.page() == Page::State);
    TEST_ASSERT_EQUAL_INT(0, feed(nav, false, lastTouch + totem::kAutoReturnMs + 30, 200000).pageChanges);
}

void test_every_touch_rearms_the_return_timer() {
    TouchNavigator nav;
    tap(nav, 1000);  // to Quotas
    // A long press (brightness) 20 s later keeps the Quotas page up.
    feed(nav, true, 21000, 22000);
    feed(nav, false, 22000, 22300);

    TEST_ASSERT_EQUAL_INT(0, feed(nav, false, 22300, 21990 + totem::kAutoReturnMs).pageChanges);
    TEST_ASSERT_TRUE(nav.page() == Page::Quotas);
    TEST_ASSERT_EQUAL_INT(1, feed(nav, false, 21990 + totem::kAutoReturnMs,
                                  21990 + totem::kAutoReturnMs + 60).pageChanges);
    TEST_ASSERT_TRUE(nav.page() == Page::State);
}

void test_a_finger_resting_on_the_quotas_page_keeps_it_up() {
    TouchNavigator nav;
    tap(nav, 1000);
    Outcome resting = feed(nav, true, 2000, 2000 + 2 * totem::kAutoReturnMs);
    TEST_ASSERT_EQUAL_INT(0, resting.pageChanges);
    TEST_ASSERT_TRUE(nav.page() == Page::Quotas);
}

void test_the_state_page_has_nothing_to_return_to() {
    TouchNavigator nav;
    tap(nav, 1000);
    tap(nav, 2000);  // back to the state page by hand
    TEST_ASSERT_EQUAL_INT(0, feed(nav, false, 3000, 3000 + 3 * totem::kAutoReturnMs, 500).pageChanges);
    TEST_ASSERT_TRUE(nav.page() == Page::State);
}

void test_the_return_timer_survives_the_millis_wrap() {
    TouchNavigator nav;
    const uint32_t start = UINT32_MAX - 5000;
    tap(nav, start);
    TEST_ASSERT_TRUE(nav.page() == Page::Quotas);
    TEST_ASSERT_FALSE(nav.step(false, start + 10000).pageChanged);  // wrapped, 10 s later
    TEST_ASSERT_TRUE(nav.page() == Page::Quotas);
    TEST_ASSERT_TRUE(nav.step(false, start + 120 + totem::kAutoReturnMs).pageChanged);
}

// --- Brightness levels (CO5300 register 0x51, persisted in NVS) ---

void test_there_are_four_brightness_levels_rising_from_a_visible_floor() {
    TEST_ASSERT_EQUAL_UINT8(4, totem::kBrightnessLevelCount);
    TEST_ASSERT_TRUE(totem::brightnessFor(0) > 0);  // never a switched-off look
    for (uint8_t level = 1; level < totem::kBrightnessLevelCount; ++level) {
        TEST_ASSERT_TRUE(totem::brightnessFor(level) > totem::brightnessFor(level - 1));
    }
}

void test_the_brightness_cycles_through_its_levels() {
    uint8_t level = 0;
    for (uint8_t i = 1; i < totem::kBrightnessLevelCount; ++i) {
        level = totem::nextBrightnessLevel(level);
        TEST_ASSERT_EQUAL_UINT8(i, level);
    }
    TEST_ASSERT_EQUAL_UINT8(0, totem::nextBrightnessLevel(level));  // brightest -> floor
}

void test_a_stored_level_is_read_back_and_a_bad_one_falls_back_to_the_default() {
    TEST_ASSERT_TRUE(totem::kDefaultBrightnessLevel < totem::kBrightnessLevelCount);
    TEST_ASSERT_EQUAL_UINT8(2, totem::storedBrightnessLevel(2));
    TEST_ASSERT_EQUAL_UINT8(totem::kDefaultBrightnessLevel, totem::storedBrightnessLevel(4));
    TEST_ASSERT_EQUAL_UINT8(totem::kDefaultBrightnessLevel, totem::storedBrightnessLevel(255));
    TEST_ASSERT_EQUAL_UINT8(totem::brightnessFor(totem::kDefaultBrightnessLevel),
                            totem::brightnessFor(9));
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_there_are_four_brightness_levels_rising_from_a_visible_floor);
    RUN_TEST(test_the_brightness_cycles_through_its_levels);
    RUN_TEST(test_a_stored_level_is_read_back_and_a_bad_one_falls_back_to_the_default);
    RUN_TEST(test_the_quotas_page_returns_to_the_state_page_after_30_s_without_a_touch);
    RUN_TEST(test_every_touch_rearms_the_return_timer);
    RUN_TEST(test_a_finger_resting_on_the_quotas_page_keeps_it_up);
    RUN_TEST(test_the_state_page_has_nothing_to_return_to);
    RUN_TEST(test_the_return_timer_survives_the_millis_wrap);
    RUN_TEST(test_the_totem_starts_on_the_state_page);
    RUN_TEST(test_a_tap_flips_between_the_state_page_and_the_quotas_page);
    RUN_TEST(test_a_long_press_steps_the_brightness_once_and_never_flips_the_page);
    RUN_TEST(test_the_long_press_fires_at_its_threshold_while_the_finger_is_down);
    RUN_TEST(test_each_long_press_is_one_step);
    RUN_TEST(test_a_press_just_under_the_threshold_is_a_tap);
    RUN_TEST(test_a_dropped_report_during_a_press_does_not_split_it_into_two_taps);
    RUN_TEST(test_a_dropped_report_during_a_long_press_does_not_add_a_tap_or_a_step);
    RUN_TEST(test_the_tap_lands_once_the_release_is_confirmed);
    return UNITY_END();
}
