#include "led_controller.h"
#include <algorithm>

namespace {
constexpr uint8_t kMaxBrightness = 15; // Supply/thermal-safe default cap for this 64 LED board.
uint8_t wave(uint32_t now, uint32_t periodMs, uint8_t low, uint8_t high) {
  const uint32_t phase = now % periodMs;
  const uint32_t half = periodMs / 2;
  const uint32_t value = phase < half ? phase * 255 / half : (periodMs - phase) * 255 / half;
  return low + (high - low) * value / 255;
}
}

void LedController::begin() { pixels_.begin(); pixels_.clear(); pixels_.show(); }
uint16_t LedController::pixelIndex(uint8_t row, uint8_t column) const { return row * 8 + column; }
void LedController::setState(PresenceState state) { state_ = state; diagnostic_ = false; }
void LedController::setBrightness(uint8_t percent) { brightnessPercent_ = std::min(percent, kMaxBrightness); }
void LedController::setDiagnosticColor(uint8_t r, uint8_t g, uint8_t b) { diagnostic_ = true; render(r, g, b); }
void LedController::showFiveThird() {
  // Compact 5/3 mark: white numerals and a green slash; all other LEDs stay off.
  static constexpr uint8_t kFive[] = {0b111, 0b100, 0b111, 0b001, 0b111};
  static constexpr uint8_t kThree[] = {0b111, 0b001, 0b111, 0b001, 0b111};
  const auto setPixel = [this](uint8_t row, uint8_t col, uint32_t color) {
    // The Waveshare matrix is mounted 180 degrees from the logical USB orientation.
    pixels_.setPixelColor(pixelIndex(7 - row, 7 - col), color);
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
  pixels_.show();
}
void LedController::off() { state_ = PresenceState::OFFLINE; diagnostic_ = false; render(0, 0, 0); }
void LedController::test() { diagnostic_ = true; render(255, 255, 255, 80); }

void LedController::render(uint8_t r, uint8_t g, uint8_t b, uint8_t scale) {
  const uint16_t factor = uint16_t(brightnessPercent_) * scale / 100;
  for (uint8_t row = 0; row < 8; ++row)
    for (uint8_t col = 0; col < 8; ++col)
      pixels_.setPixelColor(pixelIndex(row, col), pixels_.Color(uint16_t(r) * factor / 255, uint16_t(g) * factor / 255, uint16_t(b) * factor / 255));
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
