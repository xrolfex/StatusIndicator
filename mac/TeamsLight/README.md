# TeamsLight macOS agent

Native SwiftUI menu-bar app for macOS 13+. The shared **TeamsLight Production** Xcode scheme uses the Release configuration for running, profiling, analyzing, and archiving while keeping unit tests on Debug. In Xcode, select that scheme and choose **Product → Archive** to create a desktop-distribution archive.

Run `scripts/package-app.sh` to create `.build/TeamsLight.xcarchive` and copy its Xcode-built application to `.build/TeamsLight.app`. Setting `TEAMSLIGHT_SIGNING_IDENTITY` signs the archived app with a Developer ID Application identity. Notarize the signed app through the organization’s normal release pipeline before broad distribution.

The app uses `SMAppService.mainApp` for the optional Start at Login switch. It emits privacy-safe lifecycle events to the unified log under subsystem `com.example.TeamsLight`; inspect with Console or `log show --predicate 'subsystem == "com.example.TeamsLight"'`.

The app drives a connected ESP32-S3 Matrix over its verified native USB serial port and compatible Kuando/Plenom Busylights over IOKit HID. Both may be connected simultaneously. Kuando support uses the standard HID output report for recognized legacy `04D8` devices and Plenom `27BB:3BCA` through `27BB:3BCF` models; it requires no vendor SDK or driver.

The settings menu's **LED Matrix Editor** displays the ESP32's logical 8×8 layout. Click selects one pixel, Command-click toggles additional pixels, Shift-click selects a rectangular range, and **Select All** selects the complete matrix. Changing the color updates every selected NeoPixel; reopening the editor restores the complete in-memory frame. Presence selection exits custom matrix mode.

Local microphone detection is CoreAudio “input device running” state and camera detection is CoreMediaIO “device running” state. Camera access may be denied by TCC/MDM. Teams-specific state is limited to whether the app is running; the app does not access Teams files, databases, tokens, or UI internals.
