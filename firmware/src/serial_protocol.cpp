#include "serial_protocol.h"
#include "presence_state.h"
#include <cstdio>
#include <cstring>

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
  if (!strcmp(line, "STATUS")) { serial.printf("OK %s BRIGHTNESS %u\n", presenceName(leds_.state()), leds_.brightness()); return; }
  if (!strcmp(line, "OFF")) { leds_.off(); reply(serial, "OK OFF"); return; }
  if (!strcmp(line, "TEST")) { leds_.test(); reply(serial, "OK TEST"); return; }
  int value, r, g, b; char extra;
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
