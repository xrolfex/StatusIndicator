#include <Arduino.h>
#include "led_controller.h"
#include "serial_protocol.h"

#ifndef PIO_UNIT_TESTING
namespace {
constexpr size_t kSerialRxBufferSize = 512;
static_assert(kSerialRxBufferSize > kSerialProtocolMaxCommandLength,
              "Serial RX buffer must hold a complete protocol command");
}

LedController leds;
SerialProtocol protocol(leds);

void setup() {
  // Native USB CDC on ESP32-S3 or UART through the WROOM board's USB bridge.
  // No Wi-Fi or Bluetooth APIs are called or initialized.
  const size_t rxBufferSize = Serial.setRxBufferSize(kSerialRxBufferSize);
  Serial.begin(115200);
  if (rxBufferSize < kSerialRxBufferSize) Serial.println("ERR RX_BUFFER");
  leds.begin(); // Safe default: OFF.
}
void loop() {
  protocol.poll(Serial);
  leds.update(millis());
  delay(1);
}
#endif
