#include "serial_protocol.h"
#include "presence_state.h"
#include <esp_system.h>
#include <cstdio>
#include <cstring>

namespace {
int hexNibble(char value) {
  if (value >= '0' && value <= '9') return value - '0';
  if (value >= 'A' && value <= 'F') return value - 'A' + 10;
  if (value >= 'a' && value <= 'f') return value - 'a' + 10;
  return -1;
}
}

bool parseMatrixPayload(const char* payload, uint8_t* rgbValues, size_t pixelCount) {
  if (!payload || !rgbValues || strlen(payload) != pixelCount * 6) return false;
  for (size_t component = 0; component < pixelCount * 3; ++component) {
    const int high = hexNibble(payload[component * 2]);
    const int low = hexNibble(payload[component * 2 + 1]);
    if (high < 0 || low < 0) return false;
    rgbValues[component] = static_cast<uint8_t>((high << 4) | low);
  }
  return true;
}

void SerialProtocol::reply(Stream& serial, const char* text) { serial.print(text); serial.print('\n'); }
void SerialProtocol::poll(Stream& serial) {
  while (serial.available()) {
    char c = static_cast<char>(serial.read());
    if (c == '\r') continue;
    if (c == '\n') {
      if (!discardingLine_) {
        buffer_[length_] = 0;
        if (length_) handle(serial, buffer_);
      }
      length_ = 0;
      discardingLine_ = false;
      continue;
    }
    if (discardingLine_) continue;
    if (c >= 32 && c <= 126) {
      if (length_ < sizeof(buffer_) - 1) {
        buffer_[length_++] = c;
      } else {
        length_ = 0;
        discardingLine_ = true;
        reply(serial, "ERR LINE_TOO_LONG");
      }
    }
  }
}
void SerialProtocol::handle(Stream& serial, char* line) {
  PresenceState state;
  if (parsePresence(line, state)) { leds_.setState(state); serial.printf("OK %s\n", presenceName(state)); return; }
  if (!strcmp(line, "PING")) { reply(serial, "PONG"); return; }
  if (!strcmp(line, "INFO")) {
    serial.printf("OK INFO TEAMSLIGHT_PROTOCOL 4 MATRIX WIDTH %d HEIGHT %d PIXELS %d ROTATION %u SERPENTINE %u UPTIME %lu HEAP %u RESET %d\n",
                  MATRIX_WIDTH, MATRIX_HEIGHT, LED_COUNT, leds_.rotation(), leds_.serpentine(),
                  static_cast<unsigned long>(millis() / 1000), ESP.getFreeHeap(), static_cast<int>(esp_reset_reason()));
    return;
  }
  if (!strcmp(line, "STATUS")) { serial.printf("OK %s BRIGHTNESS %u\n", presenceName(leds_.state()), leds_.brightness()); return; }
  if (!strcmp(line, "CALIBRATE DEFAULT")) {
    leds_.resetCalibration();
    serial.printf("OK CALIBRATE ROTATION %u SERPENTINE %u\n", leds_.rotation(), leds_.serpentine()); return;
  }
  int rotation, serpentine; char calibrationExtra;
  if (sscanf(line, "CALIBRATE %d %d %c", &rotation, &serpentine, &calibrationExtra) >= 2) {
    if (sscanf(line, "CALIBRATE %d %d %c", &rotation, &serpentine, &calibrationExtra) != 2 || (serpentine != 0 && serpentine != 1)) { reply(serial, "ERR MALFORMED_COMMAND"); return; }
    if (!leds_.setCalibration(rotation, serpentine != 0)) { reply(serial, "ERR UNSUPPORTED_CALIBRATION"); return; }
    serial.printf("OK CALIBRATE ROTATION %d SERPENTINE %d\n", rotation, serpentine); return;
  }
  if (!strcmp(line, "OFF")) { leds_.off(); reply(serial, "OK OFF"); return; }
  if (!strcmp(line, "FIVE_THREE")) {
#if MATRIX_WIDTH == 8 && MATRIX_HEIGHT == 8
    leds_.showFiveThird(); reply(serial, "OK FIVE_THREE");
#else
    reply(serial, "ERR UNSUPPORTED_GEOMETRY");
#endif
    return;
  }
  if (!strncmp(line, "MATRIX", 6)) {
    uint8_t rgbValues[LED_COUNT * 3];
    if (line[6] != ' ' || !parseMatrixPayload(line + 7, rgbValues, LED_COUNT)) {
      reply(serial, "ERR MALFORMED_COMMAND");
      return;
    }
    leds_.setMatrix(rgbValues);
    reply(serial, "OK MATRIX");
    return;
  }
  int value, row, column, r, g, b; char extra;
  if (!strncmp(line, "PIXEL", 5)) {
    if (sscanf(line, "PIXEL %d %d %d %d %d %c", &row, &column, &r, &g, &b, &extra) != 5) {
      reply(serial, "ERR MALFORMED_COMMAND");
      return;
    }
    if (row < 0 || row >= MATRIX_HEIGHT || column < 0 || column >= MATRIX_WIDTH) {
      reply(serial, "ERR PIXEL_RANGE");
      return;
    }
    if (r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255) {
      reply(serial, "ERR COLOR_RANGE");
      return;
    }
    leds_.setMatrixPixel(row, column, r, g, b);
    serial.printf("OK PIXEL %d %d\n", row, column);
    return;
  }
  if (sscanf(line, "BRIGHTNESS %d %c", &value, &extra) >= 1) {
    if (sscanf(line, "BRIGHTNESS %d %c", &value, &extra) != 1) { reply(serial, "ERR MALFORMED_COMMAND"); return; }
    if (value < 0 || value > 15) { reply(serial, "ERR BRIGHTNESS_RANGE"); return; }
    leds_.setBrightness(value); serial.printf("OK BRIGHTNESS %d\n", value); return;
  }
  if (sscanf(line, "COLOR %d %d %d %c", &r, &g, &b, &extra) >= 3) {
    if (sscanf(line, "COLOR %d %d %d %c", &r, &g, &b, &extra) != 3) { reply(serial, "ERR MALFORMED_COMMAND"); return; }
    if (r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255) { reply(serial, "ERR COLOR_RANGE"); return; }
    leds_.setDiagnosticColor(r, g, b); reply(serial, "OK COLOR"); return;
  }
  reply(serial, "ERR UNKNOWN_COMMAND");
}
