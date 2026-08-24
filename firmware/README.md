# Firmware

The same firmware and serial protocol support both 8×8 targets:

| PlatformIO environment | Controller and LEDs | Data GPIO | Pixel layout |
| --- | --- | --- | --- |
| `waveshare_esp32_s3_matrix` | Waveshare ESP32-S3-Matrix onboard 8×8 matrix | 14 | RGB, linear, 180° rotation |
| `esp32_wroom_32d_ws2812b_64` | ESP32-WROOM-32D with external WS2812B-64 8×8 matrix | 16 | GRB, serpentine |

Install PlatformIO only on the development/flashing machine. Build both targets with:

```sh
pio run -e waveshare_esp32_s3_matrix -e esp32_wroom_32d_ws2812b_64
```

Upload the connected target with one of:

```sh
pio run -e waveshare_esp32_s3_matrix -t upload
pio run -e esp32_wroom_32d_ws2812b_64 -t upload
```

The Waveshare environment enables ESP32-S3 native USB CDC at boot and normally appears on macOS as `/dev/cu.usbmodem*`. WROOM development boards use their USB-to-UART bridge and commonly appear as `/dev/cu.usbserial*`, `/dev/cu.SLAB_USBtoUART*`, or `/dev/cu.wchusbserial*`. The Mac agent supports all of these names and verifies the firmware using `PING`/`PONG`.

The WROOM upload target uses 115200 baud and verified 4 KB ROM-loader transactions. This is slower than esptool's normal RAM-stub upload, but it remains reliable on CP2102 boards that disconnect during a sustained flash write.

## ESP32-WROOM-32D matrix wiring

The WROOM environment uses GPIO 16:

| ESP32 / supply | WS2812B-64 |
| --- | --- |
| GPIO 16 through a 330–470 Ω resistor | `DIN` |
| Ground | `GND` |
| External regulated 5 V | `5V` |

Join the ESP32 and matrix grounds. Do not power the matrix from the ESP32 3.3 V pin. A 3.3 V-to-5 V logic-level shifter on the data line and a roughly 1000 µF capacitor across the matrix supply are recommended. A 64-pixel WS2812B panel can draw several amps at unrestricted full white, so size the 5 V supply and wiring appropriately even though this firmware caps brightness at 15%.

Most WS2812B-64 panels use GRB pixels in a serpentine row layout. If the `FIVE_THREE` pattern is mirrored or rotated on a particular panel, adjust `MATRIX_SERPENTINE` and `MATRIX_ROTATION` in the WROOM environment. Solid presence colors are unaffected by matrix orientation.

The firmware never includes or initializes Wi-Fi or Bluetooth. It caps brightness at 15%. `COLOR` is a diagnostic mode; send a presence state to return to normal rendering.

Send `INFO` over the serial connection to return `OK INFO TEAMSLIGHT_PROTOCOL 1 MATRIX_8X8`. This small capability handshake lets host software identify a compatible firmware build without relying on a USB port name.

Custom matrices use logical, zero-based coordinates. `PIXEL ROW COLUMN R G B` updates one NeoPixel, while `MATRIX` accepts exactly 64 contiguous `RRGGBB` values in row-major order. Both commands apply the target's configured rotation and serpentine layout and remain active until a presence-state command is received.

Run the parser unit tests on a connected board with `pio test -e waveshare_esp32_s3_matrix` or `pio test -e esp32_wroom_32d_ws2812b_64`. The tests cover valid state changes, malformed state rejection, and full-matrix payload validation; protocol commands also reject out-of-range brightness, coordinates, and RGB values at runtime.
