#pragma once
#include <Arduino.h>
#include "led_controller.h"

class SerialProtocol {
 public:
  explicit SerialProtocol(LedController& leds) : leds_(leds) {}
  void poll(Stream& serial);
 private:
  LedController& leds_;
  char buffer_[80]{};
  uint8_t length_ = 0;
  // Once a line exceeds buffer_, ignore the remainder instead of treating a
  // suffix as a new command. This keeps framing deterministic on noisy links.
  bool discardingLine_ = false;
  void handle(Stream& serial, char* line);
  void reply(Stream& serial, const char* text);
};
