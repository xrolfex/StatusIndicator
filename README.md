# Teams Sensor

USB-only Microsoft Teams presence light for a Waveshare ESP32-S3-Matrix and macOS.

* `firmware/` is a PlatformIO/Arduino firmware project. It exposes the ESP32-S3's native USB CDC serial port and never starts Wi-Fi or Bluetooth.
* `mac/TeamsLight/` is a native SwiftUI menu-bar app. It uses local activity signals and POSIX serial I/O; it has no runtime dependency on Python, Node, Homebrew, Arduino, or ESP-IDF.

The light intentionally begins **OFF** after boot and only changes state when its USB host supplies a command.

## Quick start

1. Flash `firmware` from a development machine: `cd firmware && pio run -t upload`.
2. Build the Mac app on the target Mac: `cd mac/TeamsLight && swift build -c release`.
3. Package/sign/notarize the resulting `TeamsLight` executable as your organization requires, then run it. Normal operation needs no administrator privileges or third-party driver.

The agent discovers `/dev/cu.*` candidates and verifies a board by `PING`/`PONG`; it does not bind to a hard-coded device path. USB reconnects, sleep/wake, and temporary write failures cause automatic rediscovery.

## Detection and privacy

The default local signals are deliberately conservative:

* CoreAudio input-device activity: an active input while Teams is running resolves to `IN_CALL`; an active input otherwise resolves to `BUSY`.
* AVFoundation camera-in-use resolves to `BUSY`.
* Teams running is observable through `NSWorkspace`, but no unstable client database, token, accessibility scraping, meeting subject, audio, or chat data is read.
* User idle time resolves to `AWAY` after five minutes when no higher-priority signal exists.

macOS may require the user to grant Camera permission for the camera probe, and enterprise MDM can restrict USB serial access. The agent does not bypass either control. Microphone activity uses CoreAudio device state and does **not** capture, record, or inspect audio; macOS does not offer a general, supported public API that reliably attributes arbitrary microphone use to a particular application. Consequently Teams attribution is an inference from “Teams running + input active”, shown as such in Diagnostics.

Microsoft Graph is deliberately not implemented as a required path. If added, put it behind `PresenceProvider`; it would need an Entra app registration and delegated `Presence.Read` (or other tenant-approved presence permission), which frequently needs admin consent and introduces token handling.

## Board details

The target is Waveshare SKU 27119. Waveshare's Arduino example specifies `PIN_NEOPIXEL 14`; the matrix is 64 chained WS2812-compatible RGB LEDs. This project uses GPIO 14 and progressive index order. If a production batch has a different physical orientation, change `LedController::pixelIndex` only—state colors are matrix-wide, so orientation has no visible effect today. Keep brightness low: Waveshare warns against high LED brightness; firmware clamps the default/max to 15% unless changed at build time.

Sources: [Waveshare board documentation](https://docs.waveshare.com/ESP32-S3-Matrix), [Waveshare Arduino example](https://www.waveshare.com/wiki/ESP32-S3-Matrix).

## Protocol

Newline-delimited UTF-8 commands: `AVAILABLE`, `BUSY`, `IN_CALL`, `IN_MEETING`, `DND`, `PRESENTING`, `AWAY`, `OFFLINE`, `UNKNOWN`, `PING`, `STATUS`, `BRIGHTNESS 0..15`, `COLOR R G B`, `TEST`, and `OFF`.

Responses are `PONG`, `OK ...`, or `ERR ...`. `COLOR` is a temporary solid-color diagnostic mode; a subsequent state command restores state rendering.

## Distribution

For a corporate deployment, archive a Release `.app` in Xcode (or wrap this Swift package in the supplied app target), sign it with the organization’s Developer ID/Application certificate, notarize it if required, and distribute through the organization’s approved MDM/software channel. The code requests no elevated privileges. Start at Login uses `SMAppService` on macOS 13+.
