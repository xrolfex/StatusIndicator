# TeamsLight macOS agent

Native SwiftUI menu-bar app for macOS 13+. Build with `swift build -c release`; no runtime installation is necessary. `scripts/package-app.sh` creates `.build/TeamsLight.app`; setting `TEAMSLIGHT_SIGNING_IDENTITY` signs it with a Developer ID Application identity. Notarize the resulting app through the organization’s normal release pipeline before broad distribution. The included `TeamsLight.xcodeproj` opens the app and test targets directly in Xcode.

The app uses `SMAppService.mainApp` for the optional Start at Login switch. It emits privacy-safe lifecycle events to the unified log under subsystem `com.example.TeamsLight`; inspect with Console or `log show --predicate 'subsystem == "com.example.TeamsLight"'`.

The app drives a connected ESP32-S3 Matrix over its verified native USB serial port and compatible Kuando/Plenom Busylights over IOKit HID. Both may be connected simultaneously. Kuando support uses the standard HID output report for recognized legacy `04D8` devices and Plenom `27BB:3BCA` through `27BB:3BCF` models; it requires no vendor SDK or driver.

Local microphone detection is CoreAudio “input device running” state and camera detection is CoreMediaIO “device running” state. Camera access may be denied by TCC/MDM. Teams-specific state is limited to whether the app is running; the app does not access Teams files, databases, tokens, or UI internals.
