# TeamsLight macOS agent

Native SwiftUI menu-bar app for macOS 13+. The shared **TeamsLight Production** Xcode scheme uses the Release configuration for running, profiling, analyzing, and archiving while keeping unit tests on Debug. In Xcode, select that scheme and choose **Product → Archive** to create a desktop-distribution archive.

Run `scripts/package-app.sh` to create `.build/TeamsLight.xcarchive` and copy its Xcode-built application to `.build/TeamsLight.app`. Setting `TEAMSLIGHT_SIGNING_IDENTITY` signs the archived app with a Developer ID Application identity. Notarize the signed app through the organization’s normal release pipeline before broad distribution.

The app uses `SMAppService.mainApp` for the optional Start at Login switch. It emits privacy-safe lifecycle events to the unified log under subsystem `com.example.TeamsLight`; inspect with Console or `log show --predicate 'subsystem == "com.example.TeamsLight"'`.

Preferences persist across relaunches: chosen output, brightness, manual presence selection, custom color, matrix frame, and automatic-detection policy. Under **Automatic Detection**, microphone, camera, and idle-time signals can be enabled independently. The default requires Teams to be running before microphone or camera activity can drive a call-related state, avoiding false Busy indicators from unrelated meeting apps. Turning that requirement off intentionally treats activity from any app as Busy.

Automatic presence changes default to a 10-second stability window, avoiding momentary microphone/camera activity flickering the indicator. Choose **No Delay**, **10 Seconds**, or **30 Seconds** from Automatic Detection; manual selections always apply immediately. **When Locked or Asleep** can retain the current light, show Away, or turn all selected outputs off, and resumes normal indication on unlock or wake.

The app drives a connected ESP32-S3 Matrix over its verified native USB serial port and compatible Kuando/Plenom Busylights over IOKit HID. Both may be connected simultaneously. Kuando support uses the standard HID output report for recognized legacy `04D8` devices and Plenom `27BB:3BCA` through `27BB:3BCF` models; it requires no vendor SDK or driver.

The settings menu's **LED Matrix Editor** displays the ESP32's logical 8×8 layout. Click selects one pixel, Command-click toggles additional pixels, Shift-click selects a rectangular range, and **Select All** selects the complete matrix. Changing the color updates every selected NeoPixel; reopening the editor restores the complete in-memory frame. Presence selection exits custom matrix mode.

**Matrix Presets** provides a visual picker for built-in Available, Busy, DND, Focus Border, Break, and Checkmark scenes. Choose a thumbnail to show it immediately. Save the current editor frame with a name to create a personal preset; personal presets are stored only in local preferences and can be deleted from the picker.

Local microphone detection is CoreAudio “input device running” state and camera detection is CoreMediaIO “device running” state. Camera access may be denied by TCC/MDM. Teams-specific state is limited to whether the app is running; the app does not access Teams files, databases, tokens, or UI internals.

Diagnostics displays the latest response from the verified ESP32 serial protocol. During connection the app requests `INFO`, which current firmware answers with its protocol version and 8×8-matrix capability. Matrix and 5/3 modes are ESP32-only displays; when **Both** is selected, the Busylight is turned off while either special matrix mode is active.
