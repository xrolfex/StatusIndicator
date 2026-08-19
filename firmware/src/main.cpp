#include <Arduino.h>
#include "led_controller.h"
#include "serial_protocol.h"

#ifndef PIO_UNIT_TESTING
LedController leds;
SerialProtocol protocol(leds);

void setup() {
  // Native USB CDC only. No Wi-Fi or Bluetooth APIs are called or initialized.
  Serial.begin(115200);
  leds.begin(); // Safe default: OFF.
}
void loop() {
  protocol.poll(Serial);
  leds.update(millis());
  delay(1);
}
#endif
