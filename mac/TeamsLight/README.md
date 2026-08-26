# TeamsLight macOS agent

Native SwiftUI menu-bar app for macOS 13+. The shared **TeamsLight Production** Xcode scheme uses the Release configuration for running, profiling, analyzing, and archiving while keeping unit tests on Debug. In Xcode, select that scheme and choose **Product → Archive** to create a desktop-distribution archive.

Run `scripts/package-app.sh` to create `.build/TeamsLight.xcarchive` and copy its Xcode-built application to `.build/TeamsLight.app`. Setting `TEAMSLIGHT_SIGNING_IDENTITY` signs the archived app with a Developer ID Application identity. Notarize the signed app through the organization’s normal release pipeline before broad distribution.

The app uses `SMAppService.mainApp` for the optional Start at Login switch. It emits privacy-safe lifecycle events to the unified log under subsystem `com.example.TeamsLight`; inspect with Console or `log show --predicate 'subsystem == "com.example.TeamsLight"'`.

Preferences persist across relaunches: chosen output, brightness, manual presence selection, custom color, matrix frame, notification flashes, and automatic-detection policy. Under **Automatic Detection**, microphone, camera, and idle-time signals can be enabled independently. The default requires Teams to be running before microphone or camera activity can drive a call-related state, avoiding false Busy indicators from unrelated meeting apps. Turning that requirement off intentionally treats activity from any app as Busy.

Automatic presence changes default to a 10-second stability window, avoiding momentary microphone/camera activity flickering the indicator. Choose **No Delay**, **10 Seconds**, or **30 Seconds** from Automatic Detection; manual selections always apply immediately. **When Locked or Asleep** can retain the current light, show Away, or turn all selected outputs off, and resumes normal indication on unlock or wake.

Use **Return to Auto** to make a manual presence selection temporary. Choose 15 minutes, 30 minutes, or one hour; when the time expires, Teams Light resumes automatic detection.

The app drives a connected ESP32-S3 Matrix over its verified native USB serial port and compatible Kuando/Plenom Busylights over IOKit HID. Both may be connected simultaneously. Kuando support uses the standard HID output report for recognized legacy `04D8` devices and Plenom `27BB:3BCA` through `27BB:3BCF` models; it requires no vendor SDK or driver.

By default, **ESP32 Device** uses the first verified compatible serial port and **Busylight Device** updates every compatible Busylight. If multiple devices are connected, select an explicit serial path or Busylight USB location from Settings; that choice persists and prevents other compatible devices from receiving updates.

The settings menu's **LED Matrix Editor** uses the width and height reported by the connected firmware. Click selects one pixel, Command-click toggles additional pixels, Shift-click selects a rectangular range, and **Select All** selects the complete matrix. Changing the color updates every selected NeoPixel; reopening the editor restores the complete in-memory frame. Presence selection exits custom matrix mode.

**Matrix Presets** provides a visual picker for built-in Available, Busy, DND, Focus Border, Break, and Checkmark scenes. Choose a thumbnail to show it immediately. Save the current editor frame with a name to create a personal preset; personal presets are stored only in local preferences and can be deleted from the picker.

Use **Export** to save personal presets as JSON and **Import** to merge a JSON backup from another Mac. Built-in scenes are not exported, and duplicate matrix frames are ignored on import.

The Settings window includes **State Appearance** profiles. Each state can use independent ESP32 and Busylight colors and brightness multipliers; Reset restores the original status-light behavior. A customized Presenting profile uses a fixed color, while the default continues to pulse on the ESP32.

**Import Image** converts a selected local image to the matrix's 8×8 RGB frame and shows it immediately. Choose **Fit** to preserve the full image with black letterboxing, or **Crop to Fill** to use the entire matrix. Save the result as a personal preset if you want to reuse it.

Brief Teams chat-alert audio activity blinks white on the active ESP32 and Busylight outputs. Input activity must remain active for two seconds before it is treated as a call, preventing a chat chime from briefly showing red. Turn off **Flash white for notifications** under **Behavior** to keep the current display unchanged for these alerts.

**Desk Display** is the animation and automation workspace. It includes pulse, rainbow, scanner, sparkle, countdown, scrolling-text, audio-meter, and screen-ambient scenes; custom scenes are local and reusable. Import an animated GIF to convert up to 120 frames to the current matrix geometry. Rules can show scenes automatically for presence, active microphone, or a calendar event beginning within ten minutes. Calendar access is off by default and is only requested after enabling it in Settings; audio access is also opt-in and processed locally without recording.


Local microphone detection is CoreAudio “input device running” state and camera detection is CoreMediaIO “device running” state. Camera access may be denied by TCC/MDM. Teams-specific state is limited to whether the app is running; the app does not access Teams files, databases, tokens, or UI internals.

Diagnostics displays the latest response from the verified ESP32 serial protocol. During connection the app requests `INFO`, which current firmware answers with its protocol version and 8×8-matrix capability. Matrix and 5/3 modes are ESP32-only displays; when **Both** is selected, the Busylight is turned off while either special matrix mode is active.
