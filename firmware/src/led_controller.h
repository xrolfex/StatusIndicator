#pragma once
#include <Adafruit_NeoPixel.h>
#include "board_config.h"
#include "presence_state.h"

class LedController {
 public:
  void begin();
  void setState(PresenceState state);
  void setBrightness(uint8_t percent);
  uint8_t brightness() const { return brightnessPercent_; }
  PresenceState state() const { return state_; }
  void setDiagnosticColor(uint8_t red, uint8_t green, uint8_t blue);
  void setMatrix(const uint8_t* rgbValues);
  void setMatrixPixel(uint8_t row, uint8_t column, uint8_t red, uint8_t green, uint8_t blue);
  bool setCalibration(uint16_t rotation, bool serpentine);
  void resetCalibration();
  uint16_t rotation() const { return rotation_; }
  bool serpentine() const { return serpentine_; }
  void showFiveThird();
  void off();
  void update(uint32_t nowMs);

 private:
  Adafruit_NeoPixel pixels_{LED_COUNT, LED_DATA_PIN, LED_COLOR_ORDER + NEO_KHZ800};
  PresenceState state_ = PresenceState::OFFLINE;
  uint8_t brightnessPercent_ = 15;
  bool diagnostic_ = false;
  bool matrixMode_ = false;
  uint8_t matrixColors_[LED_COUNT * 3]{};
  uint32_t lastFrameMs_ = 0;
  uint16_t rotation_ = MATRIX_ROTATION;
  bool serpentine_ = MATRIX_SERPENTINE;
  uint16_t pixelIndex(uint8_t row, uint8_t column) const;
  void render(uint8_t red, uint8_t green, uint8_t blue, uint8_t scale = 255);
  void renderMatrix();
  void renderState(uint32_t nowMs);
};
