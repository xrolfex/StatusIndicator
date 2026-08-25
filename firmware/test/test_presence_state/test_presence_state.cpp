#include <Arduino.h>
#include <unity.h>
#include "presence_state.h"
#include "serial_protocol.h"

void test_known_state_parses() {
  PresenceState state = PresenceState::UNKNOWN;
  TEST_ASSERT_TRUE(parsePresence("IN_MEETING", state));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(PresenceState::IN_MEETING), static_cast<int>(state));
}

void test_every_state_round_trips_through_its_protocol_name() {
  const PresenceState states[] = {
    PresenceState::AVAILABLE, PresenceState::BUSY, PresenceState::IN_CALL,
    PresenceState::IN_MEETING, PresenceState::DND, PresenceState::PRESENTING,
    PresenceState::AWAY, PresenceState::OFFLINE, PresenceState::UNKNOWN,
  };
  for (const PresenceState expected : states) {
    PresenceState parsed = PresenceState::AVAILABLE;
    TEST_ASSERT_TRUE(parsePresence(presenceName(expected), parsed));
    TEST_ASSERT_EQUAL_INT(static_cast<int>(expected), static_cast<int>(parsed));
  }
}

void test_malformed_state_rejected() {
  PresenceState state = PresenceState::AVAILABLE;
  TEST_ASSERT_FALSE(parsePresence("IN MEETING", state));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(PresenceState::AVAILABLE), static_cast<int>(state));
}
void test_unknown_state_rejected_without_mutating_output() {
  PresenceState state = PresenceState::DND;
  TEST_ASSERT_FALSE(parsePresence("DO_NOT_DISTURB", state));
  TEST_ASSERT_EQUAL_INT(static_cast<int>(PresenceState::DND), static_cast<int>(state));
}

void test_matrix_payload_parses_rgb_pixels() {
  uint8_t colors[6]{};
  TEST_ASSERT_TRUE(parseMatrixPayload("000000Ff1080", colors, 2));
  const uint8_t expected[] = {0, 0, 0, 255, 16, 128};
  TEST_ASSERT_EQUAL_UINT8_ARRAY(expected, colors, 6);
}

void test_malformed_matrix_payload_is_rejected() {
  uint8_t colors[6]{};
  TEST_ASSERT_FALSE(parseMatrixPayload("000000FF108", colors, 2));
  TEST_ASSERT_FALSE(parseMatrixPayload("000000FG1080", colors, 2));
  TEST_ASSERT_FALSE(parseMatrixPayload("000000FF108000", colors, 2));
}

void test_matrix_payload_rejects_null_arguments() {
  uint8_t colors[3]{};
  TEST_ASSERT_FALSE(parseMatrixPayload(nullptr, colors, 1));
  TEST_ASSERT_FALSE(parseMatrixPayload("000000", nullptr, 1));
}

void test_matrix_payload_accepts_case_insensitive_hex() {
  uint8_t colors[3]{};
  TEST_ASSERT_TRUE(parseMatrixPayload("aBcD0f", colors, 1));
  const uint8_t expected[] = {171, 205, 15};
  TEST_ASSERT_EQUAL_UINT8_ARRAY(expected, colors, 3);
}

void test_protocol_maximum_command_holds_a_complete_matrix() {
  TEST_ASSERT_EQUAL_UINT32(391, kSerialProtocolMaxCommandLength);
}

void setup() {
  // Keep native USB CDC configured long enough for PlatformIO to reopen the
  // port after flashing before Unity begins sending its one-shot output.
  Serial.begin(115200);
  delay(5000);
  UNITY_BEGIN();
  RUN_TEST(test_known_state_parses);
  RUN_TEST(test_every_state_round_trips_through_its_protocol_name);
  RUN_TEST(test_malformed_state_rejected);
  RUN_TEST(test_unknown_state_rejected_without_mutating_output);
  RUN_TEST(test_matrix_payload_parses_rgb_pixels);
  RUN_TEST(test_malformed_matrix_payload_is_rejected);
  RUN_TEST(test_matrix_payload_rejects_null_arguments);
  RUN_TEST(test_matrix_payload_accepts_case_insensitive_hex);
  RUN_TEST(test_protocol_maximum_command_holds_a_complete_matrix);
  UNITY_END();
}
void loop() {}
