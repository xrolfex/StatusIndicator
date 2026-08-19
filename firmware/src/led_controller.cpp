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
    case PresenceState::IN_MEETING: render(255, 0, 0, wave(now, 2600, 35, 255)); break;
    case PresenceState::DND: { uint32_t p = now % 1800; render(255, 0, 0, (p < 150 || (p > 310 && p < 460)) ? 255 : 0); break; }
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
