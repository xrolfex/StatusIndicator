#include "led_controller.h"
#include <algorithm>
#include <Preferences.h>

namespace {
constexpr uint8_t kMaxBrightness = 15; // Supply/thermal-safe default cap for this 64 LED board.
uint8_t wave(uint32_t now, uint32_t periodMs, uint8_t low, uint8_t high) {
  const uint32_t phase = now % periodMs;
  const uint32_t half = periodMs / 2;
  const uint32_t value = phase < half ? phase * 255 / half : (periodMs - phase) * 255 / half;
  return low + (high - low) * value / 255;
}
}

void LedController::begin() {
  Preferences preferences;
  if (preferences.begin("teamslight", true)) {
    rotation_ = preferences.getUShort("rotation", MATRIX_ROTATION);
    serpentine_ = preferences.getBool("serpentine", MATRIX_SERPENTINE);
    preferences.end();
  }
  // Never accept an invalid value from a corrupted or older NVS entry.
  if ((rotation_ != 0 && rotation_ != 90 && rotation_ != 180 && rotation_ != 270) ||
      ((rotation_ == 90 || rotation_ == 270) && MATRIX_WIDTH != MATRIX_HEIGHT)) {
    rotation_ = MATRIX_ROTATION;
    serpentine_ = MATRIX_SERPENTINE;
  }
  pixels_.begin(); pixels_.clear(); pixels_.show();
}
uint16_t LedController::pixelIndex(uint8_t row, uint8_t column) const {
  uint8_t physicalRow;
  uint8_t physicalColumn;
  switch (rotation_) {
  case 0:
  physicalRow = row;
  physicalColumn = column;
  break;
  case 90:
  physicalRow = column;
  physicalColumn = MATRIX_WIDTH - 1 - row;
  break;
  case 180:
  physicalRow = MATRIX_HEIGHT - 1 - row;
  physicalColumn = MATRIX_WIDTH - 1 - column;
  break;
  default:
  physicalRow = MATRIX_HEIGHT - 1 - column;
  physicalColumn = row;
  }
  if (serpentine_ && physicalRow % 2 != 0) physicalColumn = MATRIX_WIDTH - 1 - physicalColumn;
  return physicalRow * MATRIX_WIDTH + physicalColumn;
}
bool LedController::setCalibration(uint16_t rotation, bool serpentine) {
  if (rotation != 0 && rotation != 90 && rotation != 180 && rotation != 270) return false;
  if ((rotation == 90 || rotation == 270) && MATRIX_WIDTH != MATRIX_HEIGHT) return false;
  rotation_ = rotation;
  serpentine_ = serpentine;
  Preferences preferences;
  if (preferences.begin("teamslight", false)) {
    preferences.putUShort("rotation", rotation_);
    preferences.putBool("serpentine", serpentine_);
    preferences.end();
  }
  if (matrixMode_) renderMatrix(); else if (!diagnostic_) renderState(millis());
  return true;
}
void LedController::resetCalibration() {
  rotation_ = MATRIX_ROTATION;
  serpentine_ = MATRIX_SERPENTINE;
  Preferences preferences;
  if (preferences.begin("teamslight", false)) {
    preferences.remove("rotation");
    preferences.remove("serpentine");
    preferences.end();
  }
  if (matrixMode_) renderMatrix(); else if (!diagnostic_) renderState(millis());
}
void LedController::setState(PresenceState state) {
  state_ = state;
  diagnostic_ = false;
  matrixMode_ = false;
}
void LedController::setBrightness(uint8_t percent) {
  brightnessPercent_ = std::min(percent, kMaxBrightness);
  if (matrixMode_) renderMatrix();
}
void LedController::setDiagnosticColor(uint8_t r, uint8_t g, uint8_t b) {
  diagnostic_ = true;
  matrixMode_ = false;
  render(r, g, b);
}
void LedController::setMatrix(const uint8_t* rgbValues) {
  std::copy(rgbValues, rgbValues + sizeof(matrixColors_), matrixColors_);
  diagnostic_ = true;
  matrixMode_ = true;
  renderMatrix();
}
void LedController::setMatrixPixel(uint8_t row, uint8_t column, uint8_t r, uint8_t g, uint8_t b) {
  if (!matrixMode_) std::fill(matrixColors_, matrixColors_ + sizeof(matrixColors_), 0);
  const uint16_t offset = (row * MATRIX_WIDTH + column) * 3;
  matrixColors_[offset] = r;
  matrixColors_[offset + 1] = g;
  matrixColors_[offset + 2] = b;
  diagnostic_ = true;
  matrixMode_ = true;
  renderMatrix();
}
void LedController::showFiveThird() {
  // Compact 5/3 mark: white numerals and a green slash; all other LEDs stay off.
  static constexpr uint8_t kFive[] = {0b111, 0b100, 0b111, 0b001, 0b111};
  static constexpr uint8_t kThree[] = {0b111, 0b001, 0b111, 0b001, 0b111};
  const auto setPixel = [this](uint8_t row, uint8_t col, uint32_t color) {
    pixels_.setPixelColor(pixelIndex(row, col), color);
  };
  pixels_.clear();
  for (uint8_t row = 0; row < 5; ++row) {
    for (uint8_t col = 0; col < 3; ++col) {
      if (kFive[row] & (1 << (2 - col))) setPixel(row + 1, col, pixels_.Color(brightnessPercent_ * 17, brightnessPercent_ * 17, brightnessPercent_ * 17));
      if (kThree[row] & (1 << (2 - col))) setPixel(row + 1, col + 5, pixels_.Color(brightnessPercent_ * 17, brightnessPercent_ * 17, brightnessPercent_ * 17));
    }
  }
  setPixel(1, 4, pixels_.Color(0, brightnessPercent_ * 17, 0));
  setPixel(2, 4, pixels_.Color(0, brightnessPercent_ * 17, 0));
  setPixel(3, 3, pixels_.Color(0, brightnessPercent_ * 17, 0));
  setPixel(4, 3, pixels_.Color(0, brightnessPercent_ * 17, 0));
  setPixel(5, 3, pixels_.Color(0, brightnessPercent_ * 17, 0));
  diagnostic_ = true;
  matrixMode_ = false;
  pixels_.show();
}
void LedController::off() {
  state_ = PresenceState::OFFLINE;
  diagnostic_ = false;
  matrixMode_ = false;
  render(0, 0, 0);
}

void LedController::render(uint8_t r, uint8_t g, uint8_t b, uint8_t scale) {
  const uint16_t factor = uint16_t(brightnessPercent_) * scale / 100;
  for (uint8_t row = 0; row < MATRIX_HEIGHT; ++row)
    for (uint8_t col = 0; col < MATRIX_WIDTH; ++col)
      pixels_.setPixelColor(pixelIndex(row, col), pixels_.Color(uint16_t(r) * factor / 255, uint16_t(g) * factor / 255, uint16_t(b) * factor / 255));
  pixels_.show();
}

void LedController::renderMatrix() {
  for (uint8_t row = 0; row < MATRIX_HEIGHT; ++row) {
    for (uint8_t col = 0; col < MATRIX_WIDTH; ++col) {
      const uint16_t offset = (row * MATRIX_WIDTH + col) * 3;
      pixels_.setPixelColor(
        pixelIndex(row, col),
        pixels_.Color(
          uint16_t(matrixColors_[offset]) * brightnessPercent_ / 100,
          uint16_t(matrixColors_[offset + 1]) * brightnessPercent_ / 100,
          uint16_t(matrixColors_[offset + 2]) * brightnessPercent_ / 100
        )
      );
    }
  }
  pixels_.show();
}

void LedController::renderState(uint32_t now) {
  switch (state_) {
    case PresenceState::AVAILABLE: render(0, 255, 0); break;
    case PresenceState::BUSY: render(255, 0, 0); break;
    case PresenceState::IN_CALL:
    case PresenceState::IN_MEETING: render(255, 0, 0); break;
    case PresenceState::DND: render(255, 0, 255); break;
    case PresenceState::PRESENTING: render(170, 0, 255, wave(now, 1800, 25, 255)); break;
    case PresenceState::AWAY: render(255, 145, 0); break;
    case PresenceState::UNKNOWN: render(255, 255, 255, 45); break;
    case PresenceState::OFFLINE: render(0, 0, 0); break;
  }
}

void LedController::update(uint32_t nowMs) {
  if (diagnostic_ || nowMs - lastFrameMs_ < 40) return;
  lastFrameMs_ = nowMs;
  renderState(nowMs);
}
