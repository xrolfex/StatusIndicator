#pragma once
#include <Adafruit_NeoPixel.h>
#include "presence_state.h"

class LedController {
 public:
  void begin();
  void setState(PresenceState state);
  void setBrightness(uint8_t percent);
  uint8_t brightness() const { return brightnessPercent_; }
  PresenceState state() const { return state_; }
  void setDiagnosticColor(uint8_t red, uint8_t green, uint8_t blue);
  void test();
  void off();
  void update(uint32_t nowMs);

 private:
  // The Waveshare ESP32-S3-Matrix's onboard 8x8 LEDs use RGB byte order.
  Adafruit_NeoPixel pixels_{LED_COUNT, LED_DATA_PIN, NEO_RGB + NEO_KHZ800};
  PresenceState state_ = PresenceState::OFFLINE;
  uint8_t brightnessPercent_ = 15;
  bool diagnostic_ = false;
  uint32_t lastFrameMs_ = 0;
  uint16_t pixelIndex(uint8_t row, uint8_t column) const;
  void render(uint8_t red, uint8_t green, uint8_t blue, uint8_t scale = 255);
  void renderState(uint32_t nowMs);
};
