# Status Indicator

A private, USB-only macOS status light for Microsoft Teams. It drives either a Waveshare ESP32-S3-Matrix, a supported Kuando/Plenom Busylight, or both at the same time.

The project contains two pieces:

- `firmware/` — PlatformIO/Arduino firmware for the Waveshare ESP32-S3-Matrix (64 RGB LEDs on GPIO 14), exposed as native USB CDC serial.
- `mac/TeamsLight/` — a native macOS 13+ SwiftUI menu-bar app, with an Xcode project and tests. It controls the ESP32 over serial and Busylights over HID, without a vendor SDK or driver.

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
pio run -t upload
```

PlatformIO normally finds `/dev/cu.usbmodem*` automatically. If it cannot enter the bootloader, hold **BOOT**, press and release **RESET**, then release **BOOT** and run the command again.

### Kuando / Plenom Busylight

The macOS app automatically recognizes supported legacy Kuando devices (vendor ID `04D8`) and Plenom Busylight models `27BB:3BCA` through `27BB:3BCF`, including Busylight Omega. It sends the standard 64-byte HID output report directly through IOKit; no Kuando package, driver, or SDK is needed.

## macOS app

Open [TeamsLight.xcodeproj](mac/TeamsLight/TeamsLight.xcodeproj) in Xcode. Select the **TeamsLight** scheme, choose **My Mac**, then Build and Run. The **TeamsLightTests** target can be run with Product → Test.

From the command line:

```sh
cd mac/TeamsLight
swift test
swift build -c release
```

The menu-bar popover includes:

- Automatic or manual presence selection.
- Brightness control.
- A settings menu for choosing **ESP32**, **Busylight**, or **Both**.
- Diagnostics and a Test Lights sequence (tests every selected output).
- Optional Start at Login.
- A hidden-style **5/3 Matrix Mode**, available when ESP32 output is selected. It displays a low-brightness, 180°-oriented 5/3 mark on the matrix while all other LEDs remain off. Turning it off restores ordinary presence indication.

The app reconnects USB devices after sleep/wake and transient disconnects. Camera access may require macOS permission and can be restricted by MDM.

## Firmware protocol

The ESP32 accepts newline-delimited UTF-8 serial commands:

```text
AVAILABLE  BUSY  IN_CALL  IN_MEETING  DND  PRESENTING  AWAY  OFFLINE  UNKNOWN
PING  STATUS  BRIGHTNESS 0..15  COLOR R G B  TEST  FIVE_THREE  OFF
```

It responds with `PONG`, `OK …`, or `ERR …`. `COLOR` and `TEST` are temporary diagnostic modes; a normal state command restores presence rendering. `FIVE_THREE` displays the special matrix mark.

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

## Sources

- [Waveshare ESP32-S3-Matrix documentation](https://docs.waveshare.com/ESP32-S3-Matrix)
- [Waveshare Arduino example](https://www.waveshare.com/wiki/ESP32-S3-Matrix)
