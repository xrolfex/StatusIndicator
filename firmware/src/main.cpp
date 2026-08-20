#include <Arduino.h>
#include "led_controller.h"
#include "serial_protocol.h"

#ifndef PIO_UNIT_TESTING
LedController leds;
SerialProtocol protocol(leds);

void setup() {
  // Native USB CDC on ESP32-S3 or UART through the WROOM board's USB bridge.
  // No Wi-Fi or Bluetooth APIs are called or initialized.
  Serial.begin(115200);
  leds.begin(); // Safe default: OFF.
}
void loop() {
  protocol.poll(Serial);
  leds.update(millis());
  delay(1);
}
#endif
