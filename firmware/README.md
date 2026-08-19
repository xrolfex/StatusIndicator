# Firmware

Target: Waveshare ESP32-S3-Matrix (ESP32-S3, 64 WS2812-compatible LEDs on GPIO 14).

Install PlatformIO only on the development/flashing machine, connect the board, and run `pio run -t upload`. The `platformio.ini` enables ESP32-S3 native USB CDC at boot. On macOS the flashed board normally appears as `/dev/cu.usbmodem*`; the Mac agent identifies it with `PING`/`PONG` rather than assuming a name.

The firmware never includes or initializes Wi-Fi or Bluetooth. It caps brightness at 15%. `COLOR` and `TEST` are diagnostic modes; send a presence state to return to normal rendering.

Run the parser unit tests on the development machine with `pio test -e waveshare_esp32_s3_matrix`. The test covers valid state changes and malformed state rejection; protocol commands also reject out-of-range brightness and RGB values at runtime.
