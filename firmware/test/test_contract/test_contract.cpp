// Contract tests (issue #158, ADR-0015): the firmware decodes the very
// fixtures the app encodes byte for byte in `swift test`.
#include <unity.h>

#include <cstring>
#include <string>

#include "../support/files.h"
#include "snapshot.h"

using totem::AggregateState;
using totem::DecodeResult;
using totem::Snapshot;

using test_support::readFixture;

static DecodeResult decode(const std::string& json, Snapshot& out) {
    return totem::decodeSnapshot(json.data(), json.size(), out);
}

void setUp() {}
void tearDown() {}

void test_decodes_the_nominal_fixture() {
    Snapshot snapshot;
    TEST_ASSERT_EQUAL(static_cast<int>(DecodeResult::Ok),
                      static_cast<int>(decode(readFixture("snapshot-nominal.json"), snapshot)));

    TEST_ASSERT_EQUAL(static_cast<int>(AggregateState::Done), static_cast<int>(snapshot.state));
    TEST_ASSERT_EQUAL_UINT32(1, snapshot.counts.waiting);
    TEST_ASSERT_EQUAL_UINT32(1, snapshot.counts.done);
    TEST_ASSERT_EQUAL_UINT32(2, snapshot.counts.working);
    TEST_ASSERT_EQUAL_UINT32(1, snapshot.counts.idle);
    TEST_ASSERT_FALSE(snapshot.shutdown);

    TEST_ASSERT_TRUE(snapshot.fiveHour.present);
    TEST_ASSERT_EQUAL_INT32(24, snapshot.fiveHour.usedPercentage);
    TEST_ASSERT_TRUE(snapshot.fiveHour.hasResetsAt);
    // Unix epoch seconds (2025), not a 2001-based reference date (~7.6e8).
    TEST_ASSERT_TRUE(snapshot.fiveHour.resetsAt == 1738425600LL);

    TEST_ASSERT_TRUE(snapshot.sevenDay.present);
    TEST_ASSERT_EQUAL_INT32(41, snapshot.sevenDay.usedPercentage);
    TEST_ASSERT_FALSE(snapshot.sevenDay.hasResetsAt);

    TEST_ASSERT_TRUE(snapshot.sentAt == 1738420000LL);
}

void test_decodes_the_empty_fixture_with_quotas_omitted() {
    Snapshot snapshot;
    snapshot.fiveHour.present = true;  // a window left over from a previous Instantané
    TEST_ASSERT_EQUAL(static_cast<int>(DecodeResult::Ok),
                      static_cast<int>(decode(readFixture("snapshot-empty.json"), snapshot)));

    TEST_ASSERT_EQUAL(static_cast<int>(AggregateState::Idle), static_cast<int>(snapshot.state));
    TEST_ASSERT_EQUAL_UINT32(0, snapshot.counts.waiting + snapshot.counts.done +
                                    snapshot.counts.working + snapshot.counts.idle);
    TEST_ASSERT_FALSE(snapshot.fiveHour.present);
    TEST_ASSERT_FALSE(snapshot.sevenDay.present);
    TEST_ASSERT_TRUE(snapshot.shutdown);
    TEST_ASSERT_TRUE(snapshot.sentAt == 1738420000LL);
}

static const char* kBody =
    "\"counts\":{\"done\":0,\"idle\":1,\"waiting\":0,\"working\":0},"
    "\"sentAt\":1738420000,\"shutdown\":false,\"state\":\"idle\"";

static DecodeResult decodeWith(const std::string& versionMember, Snapshot& out) {
    return decode("{" + versionMember + kBody + "}", out);
}

void test_rejects_an_instantane_without_version() {
    Snapshot snapshot;
    TEST_ASSERT_EQUAL(static_cast<int>(DecodeResult::MissingVersion),
                      static_cast<int>(decodeWith("", snapshot)));
}

void test_rejects_an_instantane_of_another_version() {
    Snapshot snapshot;
    TEST_ASSERT_EQUAL(static_cast<int>(DecodeResult::UnsupportedVersion),
                      static_cast<int>(decodeWith("\"v\":2,", snapshot)));
    TEST_ASSERT_EQUAL(static_cast<int>(DecodeResult::UnsupportedVersion),
                      static_cast<int>(decodeWith("\"v\":0,", snapshot)));
    TEST_ASSERT_EQUAL(static_cast<int>(DecodeResult::UnsupportedVersion),
                      static_cast<int>(decodeWith("\"v\":\"1\",", snapshot)));
    TEST_ASSERT_EQUAL(static_cast<int>(DecodeResult::Ok),
                      static_cast<int>(decodeWith("\"v\":1,", snapshot)));
}

void test_key_order_is_irrelevant() {
    Snapshot snapshot;
    const std::string reordered =
        "{\"v\":1,\"state\":\"waiting\",\"shutdown\":false,\"sentAt\":1790000000,"
        "\"quotas\":{\"sevenDay\":{\"resetsAt\":1790500000,\"usedPercentage\":7}},"
        "\"counts\":{\"working\":0,\"waiting\":3,\"idle\":0,\"done\":0}}";
    TEST_ASSERT_EQUAL(static_cast<int>(DecodeResult::Ok),
                      static_cast<int>(decode(reordered, snapshot)));
    TEST_ASSERT_EQUAL(static_cast<int>(AggregateState::Waiting), static_cast<int>(snapshot.state));
    TEST_ASSERT_EQUAL_UINT32(3, snapshot.counts.waiting);
    TEST_ASSERT_FALSE(snapshot.fiveHour.present);
    TEST_ASSERT_TRUE(snapshot.sevenDay.present);
    TEST_ASSERT_TRUE(snapshot.sevenDay.resetsAt == 1790500000LL);
}

void test_a_rejected_instantane_leaves_the_previous_one_untouched() {
    Snapshot snapshot;
    TEST_ASSERT_EQUAL(static_cast<int>(DecodeResult::Ok),
                      static_cast<int>(decode(readFixture("snapshot-nominal.json"), snapshot)));

    const char* garbage = "{\"v\":1,";
    TEST_ASSERT_EQUAL(static_cast<int>(DecodeResult::InvalidJson),
                      static_cast<int>(totem::decodeSnapshot(garbage, std::strlen(garbage), snapshot)));
    TEST_ASSERT_EQUAL(static_cast<int>(DecodeResult::InvalidField),
                      static_cast<int>(decode("{\"v\":1,\"state\":\"sleeping\"}", snapshot)));
    TEST_ASSERT_EQUAL(static_cast<int>(DecodeResult::InvalidJson),
                      static_cast<int>(decode("[1]", snapshot)));

    TEST_ASSERT_EQUAL(static_cast<int>(AggregateState::Done), static_cast<int>(snapshot.state));
    TEST_ASSERT_EQUAL_UINT32(2, snapshot.counts.working);
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_decodes_the_nominal_fixture);
    RUN_TEST(test_decodes_the_empty_fixture_with_quotas_omitted);
    RUN_TEST(test_rejects_an_instantane_without_version);
    RUN_TEST(test_rejects_an_instantane_of_another_version);
    RUN_TEST(test_key_order_is_irrelevant);
    RUN_TEST(test_a_rejected_instantane_leaves_the_previous_one_untouched);
    return UNITY_END();
}
