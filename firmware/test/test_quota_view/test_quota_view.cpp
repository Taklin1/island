// Quotas page tests (issue #160): the gauges mirror the Extended Island
// (Sources/IslandUI/QuotaGauges.swift), absent Quotas never read as 0 %, the
// 5 h reset is a relative countdown, and a Déconnecté Totem dims and freezes.
#include <unity.h>

#include <cstdio>
#include <string>

#include "../support/files.h"
#include "quota_view.h"
#include "receiver.h"
#include "snapshot.h"

using test_support::readFixture;
using totem::GaugeColor;
using totem::QuotaPresenter;
using totem::QuotaView;
using totem::Snapshot;
using totem::SnapshotReceiver;

namespace {

constexpr const char* kToken = "s3cret-token";

bool decode(const std::string& json, Snapshot& out) {
    return totem::decodeSnapshot(json.data(), json.size(), out) == totem::DecodeResult::Ok;
}

std::string quotasJson(int fiveHourPercent, long long sentAt, long long resetsAt, bool shutdown) {
    char json[256];
    std::snprintf(json, sizeof json,
                  "{\"v\":1,\"state\":\"working\",\"counts\":{\"waiting\":0,\"done\":0,"
                  "\"working\":1,\"idle\":0},\"quotas\":{\"fiveHour\":{\"usedPercentage\":%d,"
                  "\"resetsAt\":%lld}},\"sentAt\":%lld,\"shutdown\":%s}",
                  fiveHourPercent, resetsAt, sentAt, shutdown ? "true" : "false");
    return json;
}

std::string noQuotasJson() {
    return "{\"v\":1,\"state\":\"idle\",\"counts\":{\"waiting\":0,\"done\":0,\"working\":0,"
           "\"idle\":1},\"sentAt\":1738420100,\"shutdown\":false}";
}

void push(SnapshotReceiver& receiver, const std::string& body, uint32_t nowMs) {
    TEST_ASSERT_EQUAL_UINT16(204, receiver.receive(kToken, body.data(), body.size(), nowMs));
}

}  // namespace

void setUp() {}
void tearDown() {}

void test_gauge_colour_follows_the_extended_island_thresholds() {
    TEST_ASSERT_TRUE(totem::gaugeColorFor(0) == GaugeColor::Green);
    TEST_ASSERT_TRUE(totem::gaugeColorFor(39) == GaugeColor::Green);
    TEST_ASSERT_TRUE(totem::gaugeColorFor(40) == GaugeColor::Yellow);
    TEST_ASSERT_TRUE(totem::gaugeColorFor(74) == GaugeColor::Yellow);
    TEST_ASSERT_TRUE(totem::gaugeColorFor(75) == GaugeColor::Red);
    TEST_ASSERT_TRUE(totem::gaugeColorFor(100) == GaugeColor::Red);
    TEST_ASSERT_TRUE(totem::gaugeColorFor(130) == GaugeColor::Red);
    TEST_ASSERT_TRUE(totem::gaugeColorFor(-5) == GaugeColor::Green);
}

void test_labels_and_colours_are_the_extended_island_ones() {
    TEST_ASSERT_EQUAL_STRING("5 h", totem::kFiveHourLabel);
    TEST_ASSERT_EQUAL_STRING("7 d", totem::kSevenDayLabel);
    // SwiftUI Color.green / .yellow / .red / .cyan, dark appearance (the
    // Halo already takes the dark system colours of the Liseré).
    TEST_ASSERT_EQUAL_HEX32(0x30D158, totem::gaugeRgb(GaugeColor::Green));
    TEST_ASSERT_EQUAL_HEX32(0xFFD60A, totem::gaugeRgb(GaugeColor::Yellow));
    TEST_ASSERT_EQUAL_HEX32(0xFF453A, totem::gaugeRgb(GaugeColor::Red));
    TEST_ASSERT_EQUAL_HEX32(0x64D2FF, totem::kCountdownRgb);
}

void test_the_nominal_instantane_shows_both_gauges_as_the_extended_island() {
    Snapshot snapshot;
    TEST_ASSERT_TRUE(decode(readFixture("snapshot-nominal.json"), snapshot));

    const QuotaView view = totem::makeQuotaView(snapshot, 0);

    TEST_ASSERT_TRUE(view.hasQuotas());
    TEST_ASSERT_TRUE(view.fiveHour.present);
    TEST_ASSERT_EQUAL_INT32(24, view.fiveHour.percent);
    TEST_ASSERT_EQUAL_UINT8(24, view.fiveHour.fill);
    TEST_ASSERT_TRUE(view.fiveHour.color == GaugeColor::Green);
    TEST_ASSERT_TRUE(view.sevenDay.present);
    TEST_ASSERT_EQUAL_INT32(41, view.sevenDay.percent);
    TEST_ASSERT_TRUE(view.sevenDay.color == GaugeColor::Yellow);
}

void test_absent_quotas_show_no_gauge_never_zero_percent() {
    // The statusline tee is off by default: this is the most common case.
    Snapshot snapshot;
    TEST_ASSERT_TRUE(decode(readFixture("snapshot-empty.json"), snapshot));

    const QuotaView view = totem::makeQuotaView(snapshot, 0);

    TEST_ASSERT_FALSE(view.hasQuotas());
    TEST_ASSERT_FALSE(view.fiveHour.present);
    TEST_ASSERT_FALSE(view.sevenDay.present);
    TEST_ASSERT_FALSE(view.hasCountdown);
}

void test_each_window_can_be_missing_on_its_own() {
    Snapshot snapshot;
    snapshot.sevenDay = {true, 12, false, 0};

    const QuotaView view = totem::makeQuotaView(snapshot, 0);

    TEST_ASSERT_TRUE(view.hasQuotas());
    TEST_ASSERT_FALSE(view.fiveHour.present);
    TEST_ASSERT_TRUE(view.sevenDay.present);
    TEST_ASSERT_FALSE(view.hasCountdown);  // the countdown is the 5 h reset only
}

void test_the_fill_is_clamped_but_the_percent_is_shown_as_sent() {
    // QuotaGauges.swift: fraction min(1, max(0, used / 100)), label unclamped.
    Snapshot snapshot;
    snapshot.fiveHour = {true, 130, false, 0};
    snapshot.sevenDay = {true, -3, false, 0};

    const QuotaView view = totem::makeQuotaView(snapshot, 0);

    TEST_ASSERT_EQUAL_INT32(130, view.fiveHour.percent);
    TEST_ASSERT_EQUAL_UINT8(100, view.fiveHour.fill);
    TEST_ASSERT_TRUE(view.fiveHour.color == GaugeColor::Red);
    TEST_ASSERT_EQUAL_INT32(-3, view.sevenDay.percent);
    TEST_ASSERT_EQUAL_UINT8(0, view.sevenDay.fill);
}

// --- The 5 h reset as a relative countdown (no clock, no NTP, no time zone) ---

void test_the_countdown_starts_from_resets_at_minus_sent_at() {
    Snapshot snapshot;
    TEST_ASSERT_TRUE(decode(readFixture("snapshot-nominal.json"), snapshot));

    const QuotaView view = totem::makeQuotaView(snapshot, 0);

    TEST_ASSERT_TRUE(view.hasCountdown);
    TEST_ASSERT_EQUAL_UINT32(1738425600 - 1738420000, view.countdownSeconds);  // 5600 s
}

void test_the_countdown_runs_down_with_the_local_clock() {
    Snapshot snapshot;
    snapshot.sentAt = 1000;
    snapshot.fiveHour = {true, 50, true, 1000 + 600};

    TEST_ASSERT_EQUAL_UINT32(600, totem::makeQuotaView(snapshot, 999).countdownSeconds);
    TEST_ASSERT_EQUAL_UINT32(599, totem::makeQuotaView(snapshot, 1000).countdownSeconds);
    TEST_ASSERT_EQUAL_UINT32(540, totem::makeQuotaView(snapshot, 60000).countdownSeconds);
}

void test_the_countdown_stops_at_zero() {
    Snapshot snapshot;
    snapshot.sentAt = 1000;
    snapshot.fiveHour = {true, 50, true, 1000 + 5};
    TEST_ASSERT_EQUAL_UINT32(0, totem::makeQuotaView(snapshot, 5000).countdownSeconds);
    TEST_ASSERT_EQUAL_UINT32(0, totem::makeQuotaView(snapshot, UINT32_MAX).countdownSeconds);

    // A reset already past when the Mac sent it.
    snapshot.fiveHour.resetsAt = 900;
    const QuotaView view = totem::makeQuotaView(snapshot, 0);
    TEST_ASSERT_TRUE(view.hasCountdown);
    TEST_ASSERT_EQUAL_UINT32(0, view.countdownSeconds);
}

void test_no_countdown_without_a_5h_reset() {
    Snapshot snapshot;
    snapshot.fiveHour = {true, 50, false, 0};
    snapshot.sevenDay = {true, 50, true, 999999};
    TEST_ASSERT_FALSE(totem::makeQuotaView(snapshot, 0).hasCountdown);
}

void test_the_countdown_reads_in_whole_minutes_rounded_up() {
    char text[16];
    totem::formatCountdown(0, text, sizeof text);
    TEST_ASSERT_EQUAL_STRING("now", text);
    totem::formatCountdown(1, text, sizeof text);
    TEST_ASSERT_EQUAL_STRING("1m", text);
    totem::formatCountdown(59 * 60, text, sizeof text);
    TEST_ASSERT_EQUAL_STRING("59m", text);
    totem::formatCountdown(59 * 60 + 1, text, sizeof text);
    TEST_ASSERT_EQUAL_STRING("1h 00m", text);
    // 2h 12m 30s: a reset at 17:00 seen at 14:47:30 on the Mac reads 2h 13m.
    totem::formatCountdown(2 * 3600 + 12 * 60 + 30, text, sizeof text);
    TEST_ASSERT_EQUAL_STRING("2h 13m", text);
    totem::formatCountdown(5600, text, sizeof text);
    TEST_ASSERT_EQUAL_STRING("1h 34m", text);
    totem::formatCountdown(2 * 3600 + 5 * 60, text, sizeof text);
    TEST_ASSERT_EQUAL_STRING("2h 05m", text);
}

void test_the_countdown_reads_in_days_beyond_a_day() {
    // Not shown for the 5 h window today; ready if a 7 d reset appears later.
    char text[16];
    totem::formatCountdown(24 * 3600, text, sizeof text);
    TEST_ASSERT_EQUAL_STRING("24h 00m", text);
    totem::formatCountdown(24 * 3600 + 1, text, sizeof text);
    TEST_ASSERT_EQUAL_STRING("1d 00h", text);
    totem::formatCountdown(6 * 86400 + 3 * 3600 + 20 * 60, text, sizeof text);
    TEST_ASSERT_EQUAL_STRING("6d 03h", text);
    totem::formatCountdown(UINT32_MAX, text, sizeof text);
    TEST_ASSERT_EQUAL_STRING("49710d 06h", text);
}

void test_the_countdown_text_never_overflows_its_buffer() {
    char text[4];
    totem::formatCountdown(2 * 3600, text, sizeof text);
    TEST_ASSERT_EQUAL_UINT8('\0', text[3]);
}

// --- QuotaPresenter: live while Connecté, dimmed and frozen when Déconnecté ---

void test_a_totem_disconnected_at_boot_shows_dimmed_no_quotas() {
    SnapshotReceiver receiver(kToken);
    QuotaPresenter quotas;

    quotas.update(receiver, 5000);

    TEST_ASSERT_TRUE(quotas.view().dimmed);
    TEST_ASSERT_FALSE(quotas.view().hasQuotas());
    TEST_ASSERT_FALSE(quotas.view().hasCountdown);
}

void test_a_connected_totem_shows_live_quotas_and_runs_the_countdown_down() {
    SnapshotReceiver receiver(kToken);
    QuotaPresenter quotas;
    push(receiver, readFixture("snapshot-nominal.json"), 1000);

    quotas.update(receiver, 11000);

    TEST_ASSERT_FALSE(quotas.view().dimmed);
    TEST_ASSERT_EQUAL_INT32(24, quotas.view().fiveHour.percent);
    TEST_ASSERT_EQUAL_UINT32(5590, quotas.view().countdownSeconds);
}

void test_each_accepted_instantane_realigns_the_countdown() {
    SnapshotReceiver receiver(kToken);
    QuotaPresenter quotas;
    push(receiver, quotasJson(24, 1000, 1600, false), 1000);
    quotas.update(receiver, 21000);
    TEST_ASSERT_EQUAL_UINT32(580, quotas.view().countdownSeconds);

    // The Mac's heartbeat 25 s after the first push: its stamps win over the
    // local drift (here the board clock ran 5 s slow).
    push(receiver, quotasJson(24, 1025, 1600, false), 21000);
    quotas.update(receiver, 21000);
    TEST_ASSERT_EQUAL_UINT32(575, quotas.view().countdownSeconds);
}

void test_a_silent_totem_dims_and_freezes_the_last_quotas() {
    SnapshotReceiver receiver(kToken);
    QuotaPresenter quotas;
    push(receiver, readFixture("snapshot-nominal.json"), 1000);
    quotas.update(receiver, 1000 + totem::Freshness::kTimeoutMs - 1);
    const uint32_t lastLive = quotas.view().countdownSeconds;

    quotas.update(receiver, 1000 + totem::Freshness::kTimeoutMs);
    TEST_ASSERT_TRUE(quotas.view().dimmed);
    TEST_ASSERT_EQUAL_INT32(24, quotas.view().fiveHour.percent);
    TEST_ASSERT_EQUAL_INT32(41, quotas.view().sevenDay.percent);
    TEST_ASSERT_EQUAL_UINT32(lastLive, quotas.view().countdownSeconds);

    quotas.update(receiver, 900000);
    TEST_ASSERT_TRUE(quotas.view().dimmed);
    TEST_ASSERT_EQUAL_UINT32(lastLive, quotas.view().countdownSeconds);
}

void test_the_app_shutdown_freezes_the_last_quotas_not_its_empty_instantane() {
    // The closing Instantané carries no Quotas: Déconnecté keeps the last ones.
    SnapshotReceiver receiver(kToken);
    QuotaPresenter quotas;
    push(receiver, readFixture("snapshot-nominal.json"), 1000);
    quotas.update(receiver, 2000);

    push(receiver, readFixture("snapshot-empty.json"), 3000);
    quotas.update(receiver, 3000);

    TEST_ASSERT_TRUE(quotas.view().dimmed);
    TEST_ASSERT_TRUE(quotas.view().hasQuotas());
    TEST_ASSERT_EQUAL_INT32(24, quotas.view().fiveHour.percent);
    TEST_ASSERT_EQUAL_UINT32(5599, quotas.view().countdownSeconds);
}

void test_reconnecting_shows_the_new_quotas_even_when_absent() {
    SnapshotReceiver receiver(kToken);
    QuotaPresenter quotas;
    push(receiver, readFixture("snapshot-nominal.json"), 1000);
    quotas.update(receiver, 1000);
    quotas.update(receiver, 1000 + totem::Freshness::kTimeoutMs);

    push(receiver, noQuotasJson(), 60000);
    quotas.update(receiver, 60000);

    TEST_ASSERT_FALSE(quotas.view().dimmed);
    TEST_ASSERT_FALSE(quotas.view().hasQuotas());
}

void test_the_presenter_reports_a_change_only_on_a_visible_difference() {
    SnapshotReceiver receiver(kToken);
    QuotaPresenter quotas;
    TEST_ASSERT_TRUE(quotas.update(receiver, 0));  // first draw
    TEST_ASSERT_FALSE(quotas.update(receiver, 50));

    push(receiver, readFixture("snapshot-nominal.json"), 1000);
    TEST_ASSERT_TRUE(quotas.update(receiver, 1000));
    TEST_ASSERT_FALSE(quotas.update(receiver, 1050));
    TEST_ASSERT_TRUE(quotas.update(receiver, 2000));  // one second less
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_gauge_colour_follows_the_extended_island_thresholds);
    RUN_TEST(test_labels_and_colours_are_the_extended_island_ones);
    RUN_TEST(test_the_nominal_instantane_shows_both_gauges_as_the_extended_island);
    RUN_TEST(test_absent_quotas_show_no_gauge_never_zero_percent);
    RUN_TEST(test_each_window_can_be_missing_on_its_own);
    RUN_TEST(test_the_fill_is_clamped_but_the_percent_is_shown_as_sent);
    RUN_TEST(test_the_countdown_starts_from_resets_at_minus_sent_at);
    RUN_TEST(test_the_countdown_runs_down_with_the_local_clock);
    RUN_TEST(test_the_countdown_stops_at_zero);
    RUN_TEST(test_no_countdown_without_a_5h_reset);
    RUN_TEST(test_the_countdown_reads_in_whole_minutes_rounded_up);
    RUN_TEST(test_the_countdown_reads_in_days_beyond_a_day);
    RUN_TEST(test_the_countdown_text_never_overflows_its_buffer);
    RUN_TEST(test_a_totem_disconnected_at_boot_shows_dimmed_no_quotas);
    RUN_TEST(test_a_connected_totem_shows_live_quotas_and_runs_the_countdown_down);
    RUN_TEST(test_each_accepted_instantane_realigns_the_countdown);
    RUN_TEST(test_a_silent_totem_dims_and_freezes_the_last_quotas);
    RUN_TEST(test_the_app_shutdown_freezes_the_last_quotas_not_its_empty_instantane);
    RUN_TEST(test_reconnecting_shows_the_new_quotas_even_when_absent);
    RUN_TEST(test_the_presenter_reports_a_change_only_on_a_visible_difference);
    return UNITY_END();
}
