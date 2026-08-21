#pragma once
#include <Arduino.h>
#include <cstddef>
#include "led_controller.h"

constexpr size_t kSerialProtocolMaxCommandLength = 7 + LED_COUNT * 6;

bool parseMatrixPayload(const char* payload, uint8_t* rgbValues, size_t pixelCount);

class SerialProtocol {
 public:
  explicit SerialProtocol(LedController& leds) : leds_(leds) {}
  void poll(Stream& serial);
 private:
  LedController& leds_;
  char buffer_[kSerialProtocolMaxCommandLength + 1]{};
  size_t length_ = 0;
  // Once a line exceeds buffer_, ignore the remainder instead of treating a
  // suffix as a new command. This keeps framing deterministic on noisy links.
  bool discardingLine_ = false;
  void handle(Stream& serial, char* line);
  void reply(Stream& serial, const char* text);
};
