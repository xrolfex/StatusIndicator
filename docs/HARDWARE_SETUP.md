# Hardware setup and first-run check

This guide covers the supported ESP32 matrix targets. The macOS app only uses
USB serial after it verifies the board by sending `PING` and receiving `PONG`.
It never enables Wi-Fi or Bluetooth.

## Choose a target

| Target | Best when | What you need |
| --- | --- | --- |
| Waveshare ESP32-S3-Matrix (SKU 27119) | You want the simplest single-board setup. | Board and a data-capable USB cable. |
| ESP32-WROOM-32D + WS2812B-64 | You want a separate 8x8 panel or enclosure. | ESP32, 8x8 panel, regulated 5 V supply, USB data cable, and wiring parts below. |

## Flash the firmware

Install PlatformIO with `brew install platformio`, then run one command from
the repository root:

```sh
cd firmware
pio run -e waveshare_esp32_s3_matrix -t upload
# or
pio run -e esp32_wroom_32d_ws2812b_64 -t upload
```

For a Waveshare board that does not enter its bootloader, hold **BOOT**, press
and release **RESET**, release **BOOT**, then run the upload command again.

## WROOM wiring

Never power a WS2812B matrix from the ESP32's 3.3 V pin.

```text
ESP32 GPIO 16 --- 330-470 ohm resistor --- WS2812B DIN
ESP32 GND  -------------------------------- WS2812B GND
5 V regulated supply + -------------------- WS2812B 5V
5 V regulated supply - -------------------- WS2812B GND
```

The ESP32 ground and external-supply ground must be connected. Use a 5 V power
supply and wires sized for the panel; add an approximately 1000 uF capacitor
across the panel's 5 V/GND input. A 3.3 V-to-5 V logic-level shifter is
recommended, especially with longer data wires. Start with power disconnected
while changing wiring.

## First-run checklist

1. Disconnect any serial monitor, connect the board directly to the Mac using
   a data-capable USB cable, and launch Teams Light.
2. Open **Settings → Diagnostics**. The ESP32 entry should show a verified
   connection and `PONG`/`INFO` response. If it does not, reconnect the board
   and close tools such as PlatformIO Monitor, Arduino Serial Monitor, or
   `screen` that may have the port open.
3. Set **Output** to **ESP32**, then choose **Available**, **Busy**, and
   **Offline** from the menu-bar popover. Confirm green, red, and off.
4. Open **Matrix & Appearance → LED Matrix Editor** and use the corner test
   from Settings to confirm row/column orientation. If a WROOM panel is
   rotated or mirrored, use the Matrix Calibration controls; do not rewire a
   powered panel.
5. Return to **Automatic** presence only after the manual tests pass. Keep the
   default “Require Teams for Call Activity” enabled unless you deliberately
   want any microphone/camera use to show Busy.

## Before daily use

- Keep brightness at or below the firmware's 15% cap until you have checked
  panel temperature and power-supply stability.
- Provide strain relief for USB and the WROOM panel's 5 V lead.
- Recheck the Diagnostics window after macOS sleep/wake or a cable reconnect.
- Run the on-device parser tests after firmware changes:

  ```sh
  cd firmware
  pio test -e waveshare_esp32_s3_matrix
  # or pio test -e esp32_wroom_32d_ws2812b_64
  ```
