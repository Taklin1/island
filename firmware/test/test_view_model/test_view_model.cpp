// View model tests (issue #159): what the state page shows for the
// Instantané the Totem last accepted, and when LVGL must be touched.
#include <unity.h>

#include <cstdio>
#include <string>

#include "../support/files.h"
#include "receiver.h"
#include "totem_sprites.h"
#include "view_model.h"

using test_support::readFixture;
using totem::AggregateState;
using totem::Animation;
using totem::HaloColor;
using totem::PagePresenter;
using totem::PageUpdate;
using totem::Snapshot;
using totem::SnapshotReceiver;
using totem::ViewModel;
namespace sprites = totem::sprites;

namespace {

constexpr const char* kToken = "s3cret-token";

std::string snapshotJson(const char* state, unsigned waiting, unsigned done, unsigned working,
                         unsigned idle, bool shutdown = false, long long sentAt = 1738420000) {
    char json[256];
    std::snprintf(json, sizeof json,
                  "{\"v\":1,\"state\":\"%s\",\"counts\":{\"waiting\":%u,\"done\":%u,"
                  "\"working\":%u,\"idle\":%u},\"sentAt\":%lld,\"shutdown\":%s}",
                  state, waiting, done, working, idle, sentAt, shutdown ? "true" : "false");
    return json;
}

void push(SnapshotReceiver& receiver, const std::string& body, uint32_t nowMs) {
    TEST_ASSERT_EQUAL_UINT16(204, receiver.receive(kToken, body.data(), body.size(), nowMs));
}

}  // namespace

void setUp() {}
void tearDown() {}

void test_each_aggregated_state_shows_its_animation() {
    TEST_ASSERT_TRUE(totem::animationFor(AggregateState::Idle) == Animation::Sleeping);
    TEST_ASSERT_TRUE(totem::animationFor(AggregateState::Working) == Animation::Working);
    TEST_ASSERT_TRUE(totem::animationFor(AggregateState::Done) == Animation::Finished);
    TEST_ASSERT_TRUE(totem::animationFor(AggregateState::Waiting) == Animation::Question);
}

void test_a_connected_totem_shows_the_mac_state_and_the_raw_counts() {
    SnapshotReceiver receiver(kToken);
    push(receiver, readFixture("snapshot-nominal.json"), 1000);

    const ViewModel view = totem::viewModelFor(receiver, 1000);

    TEST_ASSERT_TRUE(view.connected);
    TEST_ASSERT_FALSE(view.grey);
    TEST_ASSERT_TRUE(view.animation == Animation::Finished);
    TEST_ASSERT_EQUAL_UINT32(1, view.counts.waiting);
    TEST_ASSERT_EQUAL_UINT32(1, view.counts.done);
    TEST_ASSERT_EQUAL_UINT32(2, view.counts.working);
    TEST_ASSERT_EQUAL_UINT32(1, view.counts.idle);
}

void test_an_acknowledged_waiting_session_still_counts_but_lights_no_halo() {
    // Founder, 2026-09-15: counts are raw, only the aggregated state knows
    // about the Acquittement. A waiting count with the Halo off is normal.
    SnapshotReceiver receiver(kToken);
    push(receiver, snapshotJson("idle", 1, 0, 0, 2), 1000);

    const ViewModel view = totem::viewModelFor(receiver, 1000);

    TEST_ASSERT_TRUE(view.animation == Animation::Sleeping);
    TEST_ASSERT_EQUAL_UINT32(1, view.counts.waiting);
    TEST_ASSERT_TRUE(view.halo == HaloColor::Off);
}

void test_a_totem_disconnected_at_boot_sleeps_grey_with_no_counts_and_no_halo() {
    SnapshotReceiver receiver(kToken);

    const ViewModel view = totem::viewModelFor(receiver, 5000);

    TEST_ASSERT_FALSE(view.connected);
    TEST_ASSERT_TRUE(view.grey);
    TEST_ASSERT_TRUE(view.animation == Animation::Sleeping);
    TEST_ASSERT_TRUE(view.halo == HaloColor::Off);
    TEST_ASSERT_EQUAL_UINT32(0, view.counts.waiting + view.counts.done + view.counts.working +
                                    view.counts.idle);
}

void test_a_silent_totem_never_shows_a_stale_state_or_halo() {
    SnapshotReceiver receiver(kToken);
    push(receiver, snapshotJson("waiting", 2, 0, 1, 0), 1000);

    const ViewModel view = totem::viewModelFor(receiver, 1000 + totem::Freshness::kTimeoutMs);

    TEST_ASSERT_FALSE(view.connected);
    TEST_ASSERT_TRUE(view.grey);
    TEST_ASSERT_TRUE(view.animation == Animation::Sleeping);
    TEST_ASSERT_TRUE(view.halo == HaloColor::Off);
    TEST_ASSERT_EQUAL_UINT32(0, view.counts.waiting);
}

void test_a_shutdown_instantane_disconnects_the_page_at_once() {
    SnapshotReceiver receiver(kToken);
    push(receiver, snapshotJson("done", 0, 1, 0, 0), 1000);
    push(receiver, snapshotJson("done", 0, 1, 0, 0, true), 2000);

    const ViewModel view = totem::viewModelFor(receiver, 2000);

    TEST_ASSERT_FALSE(view.connected);
    TEST_ASSERT_TRUE(view.halo == HaloColor::Off);
}

// --- PagePresenter: touch LVGL only on a real difference (no flicker) ---

void test_the_first_step_draws_the_whole_page() {
    PagePresenter page;
    const PageUpdate update = page.step(totem::makeViewModel(false, nullptr), 0);
    TEST_ASSERT_TRUE(update.link);
    TEST_ASSERT_TRUE(update.counts);
    TEST_ASSERT_TRUE(update.halo);
    TEST_ASSERT_TRUE(update.mascot);
}

void test_an_identical_instantane_or_a_heartbeat_touches_nothing() {
    SnapshotReceiver receiver(kToken);
    PagePresenter page;
    push(receiver, snapshotJson("waiting", 1, 2, 0, 0, false, 1738420000), 1000);
    page.step(totem::viewModelFor(receiver, 1000), 1000);

    // Same state 10 ms later (frame unchanged), then a heartbeat re-send.
    TEST_ASSERT_FALSE(page.step(totem::viewModelFor(receiver, 1010), 1010).any());
    push(receiver, snapshotJson("waiting", 1, 2, 0, 0, false, 1738420010), 1020);
    TEST_ASSERT_FALSE(page.step(totem::viewModelFor(receiver, 1020), 1020).any());
}

void test_a_count_change_only_redraws_the_counts() {
    PagePresenter page;
    Snapshot snapshot;
    snapshot.state = AggregateState::Working;
    snapshot.counts.working = 1;
    page.step(totem::makeViewModel(true, &snapshot), 0);

    snapshot.counts.working = 2;
    const PageUpdate update = page.step(totem::makeViewModel(true, &snapshot), 10);

    TEST_ASSERT_TRUE(update.counts);
    TEST_ASSERT_FALSE(update.link);
    TEST_ASSERT_FALSE(update.halo);
    TEST_ASSERT_FALSE(update.mascot);
}

void test_the_mascot_advances_at_the_sprite_pace_and_only_then_redraws() {
    PagePresenter page;
    Snapshot snapshot;
    snapshot.state = AggregateState::Working;  // 4 frames at 4 fps
    const ViewModel view = totem::makeViewModel(true, &snapshot);
    const uint8_t first = sprites::kLoops[static_cast<int>(Animation::Working)].firstFrame;

    page.step(view, 1000);
    TEST_ASSERT_EQUAL_UINT8(first, page.frame());
    TEST_ASSERT_FALSE(page.step(view, 1249).mascot);
    TEST_ASSERT_TRUE(page.step(view, 1250).mascot);
    TEST_ASSERT_EQUAL_UINT8(first + 1, page.frame());
    page.step(view, 2000);  // 4 frames later: back to the first one
    TEST_ASSERT_EQUAL_UINT8(first, page.frame());
}

void test_a_new_instantane_with_the_same_animation_never_restarts_the_frame() {
    PagePresenter page;
    Snapshot snapshot;
    snapshot.state = AggregateState::Working;
    const uint8_t first = sprites::kLoops[static_cast<int>(Animation::Working)].firstFrame;
    page.step(totem::makeViewModel(true, &snapshot), 0);
    page.step(totem::makeViewModel(true, &snapshot), 500);
    TEST_ASSERT_EQUAL_UINT8(first + 2, page.frame());

    snapshot.counts.working = 3;
    const PageUpdate update = page.step(totem::makeViewModel(true, &snapshot), 510);

    TEST_ASSERT_FALSE(update.mascot);
    TEST_ASSERT_EQUAL_UINT8(first + 2, page.frame());
}

void test_a_new_animation_starts_on_its_first_frame() {
    PagePresenter page;
    Snapshot snapshot;
    snapshot.state = AggregateState::Working;
    page.step(totem::makeViewModel(true, &snapshot), 0);
    page.step(totem::makeViewModel(true, &snapshot), 500);

    snapshot.state = AggregateState::Waiting;
    const PageUpdate update = page.step(totem::makeViewModel(true, &snapshot), 510);

    TEST_ASSERT_TRUE(update.mascot);
    TEST_ASSERT_TRUE(update.halo);
    TEST_ASSERT_EQUAL_UINT8(sprites::kLoops[static_cast<int>(Animation::Question)].firstFrame,
                            page.frame());
    // The question loop then keeps its own pace (2.5 fps: 400 ms a frame).
    TEST_ASSERT_FALSE(page.step(totem::makeViewModel(true, &snapshot), 909).mascot);
    TEST_ASSERT_TRUE(page.step(totem::makeViewModel(true, &snapshot), 910).mascot);
}

void test_going_disconnected_while_asleep_greys_the_mascot_without_restarting_it() {
    PagePresenter page;
    Snapshot snapshot;  // idle: sleeping, 2 frames at 1.5 fps
    const uint8_t first = sprites::kLoops[static_cast<int>(Animation::Sleeping)].firstFrame;
    page.step(totem::makeViewModel(true, &snapshot), 0);
    page.step(totem::makeViewModel(true, &snapshot), 700);
    TEST_ASSERT_EQUAL_UINT8(first + 1, page.frame());

    const PageUpdate update = page.step(totem::makeViewModel(false, nullptr), 710);

    TEST_ASSERT_TRUE(update.mascot);
    TEST_ASSERT_TRUE(update.link);
    TEST_ASSERT_TRUE(update.counts);
    TEST_ASSERT_FALSE(update.halo);
    TEST_ASSERT_TRUE(page.view().grey);
    TEST_ASSERT_EQUAL_UINT8(first + 1, page.frame());
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_each_aggregated_state_shows_its_animation);
    RUN_TEST(test_a_connected_totem_shows_the_mac_state_and_the_raw_counts);
    RUN_TEST(test_an_acknowledged_waiting_session_still_counts_but_lights_no_halo);
    RUN_TEST(test_a_totem_disconnected_at_boot_sleeps_grey_with_no_counts_and_no_halo);
    RUN_TEST(test_a_silent_totem_never_shows_a_stale_state_or_halo);
    RUN_TEST(test_a_shutdown_instantane_disconnects_the_page_at_once);
    RUN_TEST(test_the_first_step_draws_the_whole_page);
    RUN_TEST(test_an_identical_instantane_or_a_heartbeat_touches_nothing);
    RUN_TEST(test_a_count_change_only_redraws_the_counts);
    RUN_TEST(test_the_mascot_advances_at_the_sprite_pace_and_only_then_redraws);
    RUN_TEST(test_a_new_instantane_with_the_same_animation_never_restarts_the_frame);
    RUN_TEST(test_a_new_animation_starts_on_its_first_frame);
    RUN_TEST(test_going_disconnected_while_asleep_greys_the_mascot_without_restarting_it);
    return UNITY_END();
}
