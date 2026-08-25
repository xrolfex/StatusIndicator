import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowPresenter {
    static let shared = SettingsWindowPresenter()
    private var window: NSWindow?
    private init() {}

    func show(controller: AppController) {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Teams Light Settings"
            window.contentView = NSHostingView(rootView: SettingsView(controller: controller))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        if let window { bringToForeground(window) }
    }
}

struct SettingsView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        Form {
            Section("Quick Start") {
                Text("1. Connect the matrix with a data-capable USB cable.  2. Choose ESP32 output.  3. Open Matrix Calibration and run the corner test.  4. Return to Presence when the pattern looks correct.")
                    .font(.callout)
                Button("Open Diagnostics") { DiagnosticsWindowPresenter.shared.show(controller: controller) }
            }
            Section("Permissions & Privacy") {
                ForEach(controller.permissionSummary, id: \.name) { permission in
                    LabeledContent(permission.name, value: permission.status)
                }
                Text("Permissions are optional. Calendar, microphone, and screen access are only requested when their related features are enabled.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Output Devices") {
                Picker("Output", selection: $controller.outputDestination) {
                    ForEach(OutputDestination.allCases) { Text($0.title).tag($0) }
                }
                Picker("ESP32", selection: $controller.selectedESP32Path) {
                    Text("Automatic").tag("")
                    ForEach(controller.availableESP32Paths, id: \.self) { Text($0).tag($0) }
                }
                Picker("Busylight", selection: $controller.selectedBusylightID) {
                    Text("All Compatible Devices").tag("")
                    ForEach(controller.availableBusylights) { Text($0.name).tag($0.id) }
                }
            }
            Section("Automatic Detection") {
                Toggle("Use Microphone", isOn: policyBinding(\.useMicrophone))
                Toggle("Use Camera", isOn: policyBinding(\.useCamera))
                Toggle("Use Idle Time", isOn: policyBinding(\.useIdleTime))
                Toggle("Require Teams for Call Activity", isOn: policyBinding(\.requireTeamsForCallActivity))
                Picker("Change Delay", selection: $controller.automaticTransitionDelay) {
                    Text("No Delay").tag(0.0); Text("10 Seconds").tag(10.0); Text("30 Seconds").tag(30.0)
                }
            }
            Section("Behavior") {
                Picker("When Locked or Asleep", selection: $controller.inactiveDisplayBehavior) {
                    ForEach(InactiveDisplayBehavior.allCases) { Text($0.title).tag($0) }
                }
                Picker("Return to Auto", selection: $controller.manualOverrideTimeout) {
                    Text("Never").tag(0.0); Text("After 15 Minutes").tag(900.0); Text("After 30 Minutes").tag(1800.0); Text("After 1 Hour").tag(3600.0)
                }
                Toggle("Start at Login", isOn: $controller.startAtLogin)
            }
            Section("Desk Display") {
                Toggle("Use live microphone level for Audio Meter scenes", isOn: $controller.audioReactiveEnabled)
                Toggle("Use Calendar for upcoming-meeting scenes", isOn: $controller.calendarIntegrationEnabled)
                Text("Calendar access is optional. Teams Light only requests it after you turn this on, and only reads the next event locally.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Desk Display…") { DeskDisplayWindowPresenter.shared.show(controller: controller) }
            }
            Section("Scene Safety & Priority") {
                Picker("When scenes conflict", selection: $controller.scenePriority) { ForEach(ScenePriority.allCases) { Text($0.title).tag($0) } }
                HStack { Text("Maximum scene speed"); Slider(value: $controller.sceneSafetyLimits.maximumFramesPerSecond, in: 1...10, step: 1); Text("\(Int(controller.sceneSafetyLimits.maximumFramesPerSecond)) fps") }
                HStack { Text("Maximum scene intensity"); Slider(value: $controller.sceneSafetyLimits.maximumIntensity, in: 10...100, step: 5); Text("\(Int(controller.sceneSafetyLimits.maximumIntensity))%") }
                Text("Safety limits cap every scene before it is sent to the USB matrix.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Matrix Calibration") {
                Picker("Orientation", selection: Binding(get: { controller.calibrationRotation }, set: { controller.setMatrixCalibration(rotation: $0, serpentine: controller.calibrationSerpentine) })) {
                    Text("0°").tag(0); Text("90°").tag(90); Text("180°").tag(180); Text("270°").tag(270)
                }
                .disabled(!controller.supportsMatrixCalibration)
                Toggle("Serpentine wiring", isOn: Binding(get: { controller.calibrationSerpentine }, set: { controller.setMatrixCalibration(rotation: controller.calibrationRotation, serpentine: $0) }))
                    .disabled(!controller.supportsMatrixCalibration)
                Button("Show Corner Test Pattern") { controller.showCalibrationTestPattern() }
                    .disabled(!controller.outputDestination.usesESP32)
                Button("Restore Board Default Mapping") { controller.resetMatrixCalibration() }
                    .disabled(!controller.supportsMatrixCalibration)
                Text(controller.supportsMatrixCalibration ? "Changes apply immediately and are useful for checking panel orientation or row wiring." : "Connect current protocol firmware to calibrate the matrix.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Corner-test guide: red = top-left, green = top-right, blue = bottom-left, white = bottom-right. Adjust orientation and serpentine wiring until these match.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("State Appearance") {
                HStack {
                    Text("State").frame(width: 88, alignment: .leading)
                    Text("ESP32").frame(width: 64)
                    Text("Busylight").frame(width: 64)
                    Text("ESP32 %").frame(width: 52)
                    Text("Busylight %").frame(width: 52)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ForEach(PresenceState.allCases, id: \.rawValue) { state in
                    HStack {
                        Text(state.title).frame(width: 88, alignment: .leading)
                        ColorPicker("ESP32", selection: profileColorBinding(state, \.esp32Color), supportsOpacity: false)
                            .labelsHidden().accessibilityLabel("ESP32 color for \(state.title)")
                        ColorPicker("Busylight", selection: profileColorBinding(state, \.busylightColor), supportsOpacity: false)
                            .labelsHidden().accessibilityLabel("Busylight color for \(state.title)")
                        Slider(value: profileBrightnessBinding(state, \.esp32Brightness), in: 0...100)
                            .frame(width: 52)
                            .help("ESP32 brightness for \(state.title)")
                            .accessibilityLabel("ESP32 brightness for \(state.title)")
                        Slider(value: profileBrightnessBinding(state, \.busylightBrightness), in: 0...100)
                            .frame(width: 52)
                            .help("Busylight brightness for \(state.title)")
                            .accessibilityLabel("Busylight brightness for \(state.title)")
                        Button("Reset") { controller.resetAppearanceProfile(for: state) }
                            .disabled(controller.appearanceProfiles[state.rawValue] == nil)
                    }
                }
                Text("Each device has its own color and brightness. Brightness is multiplied by the global brightness setting.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Backup") {
                Button("Export Full Settings Backup…") { exportBackup() }
                Button("Import Full Settings Backup…") { importBackup() }
                Text("Includes scenes, presets, scene controls, rules, appearance profiles, matrix frame, calibration, detection policy, and safety settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("What’s New") {
                Text("Desk Display now includes live previews, scene safety limits, configurable priority, calibration guidance, and privacy-first permission controls.")
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 520, minHeight: 480)
    }

    private func policyBinding(_ keyPath: WritableKeyPath<LocalPresencePolicy, Bool>) -> Binding<Bool> {
        Binding(
            get: { controller.presencePolicy[keyPath: keyPath] },
            set: { value in controller.setPresencePolicy { $0[keyPath: keyPath] = value } }
        )
    }
    private func profileColorBinding(_ state: PresenceState, _ keyPath: WritableKeyPath<StateAppearanceProfile, LEDColor>) -> Binding<Color> {
        Binding(
            get: {
                let color = controller.appearanceProfile(for: state)[keyPath: keyPath]
                return Color(red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255)
            },
            set: { color in
                guard let converted = NSColor(color).usingColorSpace(.deviceRGB) else { return }
                func byte(_ value: CGFloat) -> UInt8 { UInt8((min(1, max(0, value)) * 255).rounded()) }
                var profile = controller.appearanceProfile(for: state)
                profile[keyPath: keyPath] = LEDColor(red: byte(converted.redComponent), green: byte(converted.greenComponent), blue: byte(converted.blueComponent))
                controller.setAppearanceProfile(profile, for: state)
            }
        )
    }
    private func profileBrightnessBinding(_ state: PresenceState, _ keyPath: WritableKeyPath<StateAppearanceProfile, Double>) -> Binding<Double> {
        Binding(
            get: { controller.appearanceProfile(for: state)[keyPath: keyPath] },
            set: { value in
                var profile = controller.appearanceProfile(for: state)
                profile[keyPath: keyPath] = value
                controller.setAppearanceProfile(profile, for: state)
            }
        )
    }
    private func exportBackup() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "TeamsLight-Backup.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? controller.exportBackup(to: url)
    }
    private func importBackup() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = controller.importBackup(from: url)
    }
}
