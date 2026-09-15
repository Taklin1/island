// Config tests (issue #158): `data/config.json` on LittleFS carries the Wi-Fi
// and the shared token; without a usable token the server never starts.
#include <unity.h>

#include <string>

#include "../support/files.h"
#include "config.h"

using totem::ConfigResult;
using totem::TotemConfig;

static ConfigResult parse(const std::string& json, TotemConfig& out) {
    return totem::parseConfig(json.data(), json.size(), out);
}

void setUp() {}
void tearDown() {}

void test_parses_ssid_password_and_token() {
    TotemConfig config;
    TEST_ASSERT_EQUAL(
        static_cast<int>(ConfigResult::Ok),
        static_cast<int>(parse(
            "{\"ssid\":\"Maison-2.4\",\"password\":\"p@ss word\",\"token\":\"abc123\"}", config)));
    TEST_ASSERT_EQUAL_STRING("Maison-2.4", config.ssid.c_str());
    TEST_ASSERT_EQUAL_STRING("p@ss word", config.password.c_str());
    TEST_ASSERT_EQUAL_STRING("abc123", config.token.c_str());
}

void test_an_open_network_needs_no_password() {
    TotemConfig config;
    TEST_ASSERT_EQUAL(static_cast<int>(ConfigResult::Ok),
                      static_cast<int>(parse("{\"ssid\":\"Open\",\"token\":\"abc\"}", config)));
    TEST_ASSERT_EQUAL_STRING("", config.password.c_str());
}

void test_refuses_an_unreadable_config() {
    TotemConfig config;
    TEST_ASSERT_EQUAL(static_cast<int>(ConfigResult::InvalidJson),
                      static_cast<int>(parse("{\"ssid\":\"Maison\",", config)));
    TEST_ASSERT_EQUAL(static_cast<int>(ConfigResult::InvalidJson),
                      static_cast<int>(parse("", config)));
    TEST_ASSERT_EQUAL(static_cast<int>(ConfigResult::InvalidJson),
                      static_cast<int>(parse("[\"Maison\"]", config)));
}

void test_refuses_a_missing_or_empty_ssid() {
    TotemConfig config;
    TEST_ASSERT_EQUAL(static_cast<int>(ConfigResult::MissingSsid),
                      static_cast<int>(parse("{\"token\":\"abc\"}", config)));
    TEST_ASSERT_EQUAL(static_cast<int>(ConfigResult::MissingSsid),
                      static_cast<int>(parse("{\"ssid\":\"\",\"token\":\"abc\"}", config)));
    TEST_ASSERT_EQUAL(static_cast<int>(ConfigResult::MissingSsid),
                      static_cast<int>(parse("{\"ssid\":42,\"token\":\"abc\"}", config)));
}

void test_refuses_a_missing_or_empty_token() {
    TotemConfig config;
    TEST_ASSERT_EQUAL(static_cast<int>(ConfigResult::MissingToken),
                      static_cast<int>(parse("{\"ssid\":\"Maison\"}", config)));
    TEST_ASSERT_EQUAL(static_cast<int>(ConfigResult::MissingToken),
                      static_cast<int>(parse("{\"ssid\":\"Maison\",\"token\":\"\"}", config)));
    TEST_ASSERT_EQUAL(static_cast<int>(ConfigResult::MissingToken),
                      static_cast<int>(parse("{\"ssid\":\"Maison\",\"token\":null}", config)));
}

void test_a_refused_config_leaves_the_output_untouched() {
    TotemConfig config;
    config.ssid = "previous";
    parse("{\"ssid\":\"Maison\",\"token\":\"\"}", config);
    TEST_ASSERT_EQUAL_STRING("previous", config.ssid.c_str());
}

/// The versioned example must be edited: its empty token is refused.
void test_the_versioned_example_is_refused_until_a_token_is_set() {
    const std::string json = test_support::readFirmwareFile("data/config.example.json");

    TotemConfig config;
    TEST_ASSERT_EQUAL(static_cast<int>(ConfigResult::MissingToken),
                      static_cast<int>(parse(json, config)));
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_parses_ssid_password_and_token);
    RUN_TEST(test_an_open_network_needs_no_password);
    RUN_TEST(test_refuses_an_unreadable_config);
    RUN_TEST(test_refuses_a_missing_or_empty_ssid);
    RUN_TEST(test_refuses_a_missing_or_empty_token);
    RUN_TEST(test_a_refused_config_leaves_the_output_untouched);
    RUN_TEST(test_the_versioned_example_is_refused_until_a_token_is_set);
    return UNITY_END();
}
