# Status Indicator

A private, USB-only macOS status light for Microsoft Teams. It drives a Waveshare ESP32-S3-Matrix, an ESP32-WROOM-32D with an external WS2812B-64 matrix, a supported Kuando/Plenom Busylight, or an ESP32 and Busylight at the same time.

The project contains two pieces:

- `firmware/` — shared PlatformIO/Arduino firmware for the Waveshare ESP32-S3-Matrix and ESP32-WROOM-32D with an external 8×8 WS2812B matrix.
- `mac/TeamsLight/` — a native macOS 13+ SwiftUI menu-bar app, with an Xcode project and tests. It controls the ESP32 over serial and Busylights over HID, without a vendor SDK or driver.

For a step-by-step wiring and first-run verification guide, see
[Hardware setup and first-run check](docs/HARDWARE_SETUP.md).

Neither component uses Wi-Fi or Bluetooth. The ESP32 starts with its LEDs off and only changes when commanded by the Mac app.

## What it shows

The app resolves local, privacy-preserving signals into a presence state. You can also select a manual state from the menu-bar popover.

| State | ESP32 / Busylight color |
| --- | --- |
| Available | Green |
| Busy, in a call, or in a meeting | Red |
| Do Not Disturb | Purple |
| Presenting | Purple pulse (ESP32) |
| Away | Orange |
| Offline | Off |

The default automatic signals are Teams running, active microphone input, active camera use, and macOS idle time. The app does not read Teams databases, UI, tokens, chat, meeting subjects, or audio. Microphone detection observes CoreAudio input-device activity—it does not capture or inspect sound—and Teams attribution is intentionally an inference of “Teams is running + an input is active.” Diagnostics explains each current source.

## Hardware

### Waveshare ESP32-S3-Matrix

This firmware targets Waveshare SKU 27119. Its 8×8 WS2812-compatible matrix is wired to GPIO 14. The firmware caps brightness at 15% to stay within the board’s thermal/power guidance.

Install PlatformIO if needed:

```sh
brew install platformio
```

Build and upload with the board connected:

```sh
cd firmware
pio run -e waveshare_esp32_s3_matrix -t upload
```

PlatformIO normally finds `/dev/cu.usbmodem*` automatically. If it cannot enter the bootloader, hold **BOOT**, press and release **RESET**, then release **BOOT** and run the command again.

### ESP32-WROOM-32D with WS2812B-64

Connect a standard 8×8 WS2812B-64 panel to GPIO 16 using a common ground, a 330–470 Ω series data resistor, and a separate regulated 5 V supply. A logic-level shifter and a roughly 1000 µF supply capacitor are recommended. Do not power the matrix from the ESP32 3.3 V pin.

Build and upload the WROOM target with:

```sh
cd firmware
pio run -e esp32_wroom_32d_ws2812b_64 -t upload
```

This target uses the common GRB, serpentine matrix layout. Its USB-to-UART bridge may appear as `cu.usbserial`, `cu.SLAB_USBtoUART`, or `cu.wchusbserial`; the Mac app recognizes and verifies each using the same serial protocol.

### Kuando / Plenom Busylight

The macOS app automatically recognizes supported legacy Kuando devices (vendor ID `04D8`) and Plenom Busylight models `27BB:3BCA` through `27BB:3BCF`, including Busylight Omega. It sends the standard 64-byte HID output report directly through IOKit; no Kuando package, driver, or SDK is needed.

## macOS app

Open [TeamsLight.xcodeproj](mac/TeamsLight/TeamsLight.xcodeproj) in Xcode. Use the **TeamsLight** scheme for development. For a desktop-distribution build, select the shared **TeamsLight Production** scheme and choose **Product → Archive**. Its run, profile, analyze, and archive actions use Release; unit tests remain on Debug.

From the command line:

```sh
cd mac/TeamsLight
swift test
swift build -c release
scripts/package-app.sh
```

The packaging script creates `.build/TeamsLight.xcarchive` and `.build/TeamsLight.app` from the production Xcode scheme. Set `TEAMSLIGHT_SIGNING_IDENTITY` to a Developer ID Application identity to sign the app before notarization.

The menu-bar popover includes:

- Automatic or manual presence selection.
- Brightness control.
- A settings menu for choosing **ESP32**, **Busylight**, or **Both**.
- Diagnostics for connected outputs and local presence signals.
- Optional Start at Login.
- An **LED Matrix Editor** for selecting each ESP32 NeoPixel and assigning its RGB color.
- A hidden-style **5/3 Matrix Mode**, available when ESP32 output is selected. It displays a low-brightness, 180°-oriented 5/3 mark on the matrix while all other LEDs remain off. Turning it off restores ordinary presence indication.

The app reconnects USB devices after sleep/wake and transient disconnects. Camera access may require macOS permission and can be restricted by MDM.

### First-use checklist and troubleshooting

1. Flash the target firmware, disconnect it, then reconnect it directly to the Mac. The app verifies a candidate serial port with `PING`/`PONG`; it does not send presence commands to unknown serial devices.
2. Set **Output** to the hardware you actually connected. The Diagnostics window names each discovered device and shows the most recent firmware acknowledgement, including `INFO` capability data.
3. In **Automatic Detection**, leave **Require Teams for Call Activity** on unless you intentionally want any app using the microphone or camera to set the light Busy. Each signal can be disabled independently; the choices persist across relaunches.
4. If an ESP32 does not appear, use a data-capable USB cable, close another serial monitor, and reconnect the board. For a Waveshare board that will not upload, follow the BOOT/RESET sequence above.
5. If an external matrix is rotated or mirrored, change only `MATRIX_SERPENTINE` or `MATRIX_ROTATION` for the WROOM environment, rebuild, and retest with the Matrix Editor. Do not change wiring while the 5 V supply is energized.

### Hardware build notes

For the external WROOM build, plan for a short, adequately thick 5 V power lead sized for the matrix and a common ground between the ESP32 and matrix supply. Place the recommended 330–470 Ω resistor near the matrix `DIN` pin and the roughly 1000 µF capacitor across the matrix 5 V/GND input. An enclosure should leave strain relief for USB and the power lead, keep the controller clear of exposed matrix contacts, and avoid trapping heat around the LED panel. Start at the firmware’s 15% cap and verify the panel temperature before making any brightness changes.

## Firmware protocol

The ESP32 accepts newline-delimited UTF-8 serial commands:

```text
AVAILABLE  BUSY  IN_CALL  IN_MEETING  DND  PRESENTING  AWAY  OFFLINE  UNKNOWN
PING  STATUS  INFO  BRIGHTNESS 0..15  COLOR R G B  FIVE_THREE  OFF
CALIBRATE ROTATION SERPENTINE
PIXEL ROW COLUMN R G B
MATRIX <64 contiguous RRGGBB values>
```

`ROW` and `COLUMN` are zero-based logical coordinates from `0` through `7`. A `MATRIX` payload is exactly 384 hexadecimal characters in logical row-major order; the firmware applies the configured rotation and serpentine wiring. `PIXEL` and `MATRIX` enter custom matrix mode, and a normal state command restores presence rendering.

The firmware responds with `PONG`, `OK …`, or `ERR …`. `INFO` reports the protocol version plus configured matrix width, height, and pixel count, which the macOS app uses to build its editor. `COLOR` is a temporary diagnostic mode. `FIVE_THREE` displays the special matrix mark.

`CALIBRATE` accepts a rotation of `0`, `90`, `180`, or `270` and a serpentine value of `0` or `1`. The board stores this mapping in its local nonvolatile storage, so the Matrix Calibration controls in the macOS app survive a restart. Quarter-turn rotations require a square matrix.

## Development and verification

Firmware compilation/upload:

```sh
cd firmware
pio run
pio run -t upload
```

macOS app tests:

```sh
cd mac/TeamsLight
swift test
```

For distribution, archive the Xcode app, sign it with your Developer ID certificate, and notarize it according to your organization’s release process. The app requests no elevated privileges.

GitHub Actions compiles both firmware targets and builds/tests the macOS app on
every pull request and `main` push. Pushing a `v*` tag starts the protected
release workflow, which signs, notarizes, staples, and attaches the macOS app
to a GitHub Release. Before using it, configure the `release` environment with
the required signing secrets and the `DEVELOPER_ID_APPLICATION_IDENTITY`
repository variable; see [release automation setup](docs/RELEASE_AUTOMATION.md).

## Sources

- [Waveshare ESP32-S3-Matrix documentation](https://docs.waveshare.com/ESP32-S3-Matrix)
- [Waveshare Arduino example](https://www.waveshare.com/wiki/ESP32-S3-Matrix)
