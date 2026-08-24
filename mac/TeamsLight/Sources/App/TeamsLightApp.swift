import ServiceManagement
import SwiftUI
import os

@main
struct TeamsLightApp: App {
    @StateObject private var controller = AppController()
    
    var body: some Scene {
        MenuBarExtra("Teams Light", systemImage: controller.menuBarSystemImage) {
            TeamsLightPopover(controller: controller)
        }
        .menuBarExtraStyle(.window)
    }
}

struct TeamsLightPopover: View {
    @ObservedObject var controller: AppController
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatusHeader(controller: controller)
            Divider()
            PresenceOverrideSection(controller: controller)
            BrightnessSection(controller: controller)
        }
        .padding()
        .frame(width: 320)
    }
}

struct StatusHeader: View {
    @ObservedObject var controller: AppController
    
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(controller.displayAccentColor)
                .frame(width: 10, height: 10)
                .shadow(color: controller.displayAccentColor.opacity(0.45), radius: 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.displayTitle)
                    .font(.headline)
            }
            Spacer()
            Menu {
                Picker("Output", selection: $controller.outputDestination) {
                    ForEach(OutputDestination.allCases) { destination in
                        Text(destination.title).tag(destination)
                    }
                }
                Menu("Automatic Detection") {
                    Toggle("Use Microphone", isOn: Binding(
                        get: { controller.presencePolicy.useMicrophone },
                        set: { enabled in controller.setPresencePolicy { $0.useMicrophone = enabled } }
                    ))
                    Toggle("Use Camera", isOn: Binding(
                        get: { controller.presencePolicy.useCamera },
                        set: { enabled in controller.setPresencePolicy { $0.useCamera = enabled } }
                    ))
                    Toggle("Use Idle Time", isOn: Binding(
                        get: { controller.presencePolicy.useIdleTime },
                        set: { enabled in controller.setPresencePolicy { $0.useIdleTime = enabled } }
                    ))
                    Divider()
                    Toggle("Require Teams for Call Activity", isOn: Binding(
                        get: { controller.presencePolicy.requireTeamsForCallActivity },
                        set: { enabled in controller.setPresencePolicy { $0.requireTeamsForCallActivity = enabled } }
                    ))
                    Divider()
                    Picker("Change Delay", selection: $controller.automaticTransitionDelay) {
                        Text("No Delay").tag(0.0)
                        Text("10 Seconds").tag(10.0)
                        Text("30 Seconds").tag(30.0)
                    }
                }
                Picker("When Locked or Asleep", selection: $controller.inactiveDisplayBehavior) {
                    ForEach(InactiveDisplayBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }
                Divider()
                Button {
                    DiagnosticsWindowPresenter.shared.show(controller: controller)
                } label: {
                    Label("Diagnostics", systemImage: "waveform.path.ecg")
                }
                Button {
                    LEDMatrixWindowPresenter.shared.show(controller: controller)
                } label: {
                    Label("LED Matrix Editor…", systemImage: "square.grid.3x3.fill")
                }
                .disabled(!controller.outputDestination.usesESP32)
                Button {
                    MatrixPresetWindowPresenter.shared.show(controller: controller)
                } label: {
                    Label("Matrix Presets…", systemImage: "square.grid.2x2")
                }
                .disabled(!controller.outputDestination.usesESP32)
                Toggle(
                    "5/3 Matrix Mode",
                    isOn: Binding(
                        get: { controller.isFiveThirdMode },
                        set: { controller.setFiveThirdMode($0) }
                    )
                )
                .disabled(!controller.outputDestination.usesESP32)
                Divider()
                Button {
                    CustomColorPanelPresenter.shared.show(controller: controller)
                } label: {
                    Label("Custom Color…", systemImage: "paintpalette")
                }
                Toggle("Start at Login", isOn: $controller.startAtLogin)
                Divider()
                Button("Quit Teams Light") {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .help("Settings")
        }
    }
    
}

struct PresenceOverrideSection: View {
    @ObservedObject var controller: AppController
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Presence")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(PresenceChoice.all) { choice in
                    PresenceChoiceButton(choice: choice, controller: controller)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct PresenceChoiceButton: View {
    let choice: PresenceChoice
    @ObservedObject var controller: AppController
    
    var body: some View {
        Button(choice.title) {
            controller.setPresenceOverride(choice.state)
        }
        .buttonStyle(PresenceChipButtonStyle(
            isSelected: !controller.isCustomColorOverride
            && !controller.isMatrixOverride
            && !controller.isFiveThirdMode
            && controller.override == choice.state
        ))
    }
}

struct PresenceChoice: Identifiable {
    let id: String
    let title: String
    let state: PresenceState?
    
    static let all = [
        PresenceChoice(id: "auto", title: "Auto", state: nil),
        PresenceChoice(id: "available", title: "Available", state: .available),
        PresenceChoice(id: "busy", title: "Busy", state: .busy),
        PresenceChoice(id: "in-call", title: "In Call", state: .inCall),
        PresenceChoice(id: "in-meeting", title: "Meeting", state: .inMeeting),
        PresenceChoice(id: "presenting", title: "Presenting", state: .presenting),
        PresenceChoice(id: "dnd", title: "DND", state: .dnd),
        PresenceChoice(id: "away", title: "Away", state: .away),
        PresenceChoice(id: "offline", title: "Offline", state: .offline)
    ]
}

@MainActor
final class CustomColorPanelPresenter: NSObject {
    static let shared = CustomColorPanelPresenter()
    
    private weak var controller: AppController?
    
    func show(controller: AppController) {
        self.controller = controller
        let panel = NSColorPanel.shared
        panel.color = NSColor(controller.customColor)
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(colorDidChange(_:)))
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    
    @objc private func colorDidChange(_ sender: NSColorPanel) {
        controller?.setCustomColor(Color(sender.color))
    }
}

struct PresenceChipButtonStyle: ButtonStyle {
    let isSelected: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 26)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                isSelected ? Color.accentColor : Color.secondary.opacity(configuration.isPressed ? 0.25 : 0.12),
                in: RoundedRectangle(cornerRadius: 7)
            )
    }
}

struct BrightnessSection: View {
    @ObservedObject var controller: AppController
    
    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text("Brightness")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(controller.brightnessPercent, format: .number.precision(.fractionLength(0)))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Image(systemName: "sun.min")
                    .foregroundStyle(.secondary)
                Slider(
                    value: $controller.brightnessPercent,
                    in: 0...100,
                    onEditingChanged: { isEditing in
                        if !isEditing {
                            controller.setBrightness()
                        }
                    }
                )
                .accessibilityLabel("Brightness")
                .accessibilityValue("\(controller.brightnessPercent, format: .number.precision(.fractionLength(0))) percent")
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
final class DiagnosticsWindowPresenter {
    static let shared = DiagnosticsWindowPresenter()
    
    private var window: NSWindow?
    
    private init() {}
    
    func show(controller: AppController) {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Teams Light Diagnostics"
            window.contentView = NSHostingView(rootView: DiagnosticsView(controller: controller))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class AppController: ObservableObject {
    private enum DefaultsKey {
        static let output = "outputDestination"
        static let brightness = "brightnessPercent"
        static let override = "presenceOverride"
        static let customRed = "customColor.red"
        static let customGreen = "customColor.green"
        static let customBlue = "customColor.blue"
        static let matrix = "matrix.hexPayload"
        static let microphone = "presencePolicy.microphone"
        static let camera = "presencePolicy.camera"
        static let idle = "presencePolicy.idle"
        static let requireTeams = "presencePolicy.requireTeams"
        static let transitionDelay = "presenceTransitionDelay"
        static let inactiveBehavior = "inactiveDisplayBehavior"
    }
    private let defaults = UserDefaults.standard
    @Published var state: PresenceState = .unknown
    @Published var signals: [PresenceSignal] = []
    @Published var connected = false
    @Published var deviceName: String?
    @Published var busylightDeviceName: String?
    @Published var outputDestination: OutputDestination = .both { didSet { defaults.set(outputDestination.rawValue, forKey: DefaultsKey.output); tick() } }
    // Level 1 is the lowest visible ESP32 matrix brightness (level 0 turns it off).
    private static let lowestVisibleBrightnessPercent = 100.0 / 15.0
    @Published private(set) var isFiveThirdMode = false
    @Published var brightnessPercent = 100.0 { didSet { defaults.set(brightnessPercent, forKey: DefaultsKey.brightness) } }
    @Published var override: PresenceState? {
        didSet {
            if let override { defaults.set(override.rawValue, forKey: DefaultsKey.override) }
            else { defaults.removeObject(forKey: DefaultsKey.override) }
        }
    }
    @Published var customColor = Color.purple
    @Published var isCustomColorOverride = false
    @Published private(set) var matrix = LEDMatrix()
    @Published private(set) var isMatrixOverride = false
    @Published var startAtLogin = false { didSet { setLoginItem() } }
    @Published var presencePolicy = LocalPresencePolicy() { didSet { persistPresencePolicy(); tick() } }
    @Published var automaticTransitionDelay = 10.0 {
        didSet {
            let normalized: Double = automaticTransitionDelay == 30 ? 30 : automaticTransitionDelay == 0 ? 0 : 10
            if automaticTransitionDelay != normalized {
                automaticTransitionDelay = normalized
                return
            }
            transitionFilter.delay = automaticTransitionDelay
            defaults.set(automaticTransitionDelay, forKey: DefaultsKey.transitionDelay)
        }
    }
    @Published var inactiveDisplayBehavior: InactiveDisplayBehavior = .away {
        didSet { defaults.set(inactiveDisplayBehavior.rawValue, forKey: DefaultsKey.inactiveBehavior); setInactiveDisplay(isInactiveDisplay) }
    }
    private let transport = USBSerialTransport()
    private let busylight = KuandoBusylightTransport()
    private let sampler = LocalPresenceSampler(); private let resolver = PresenceResolver()
    private var transitionFilter = PresenceTransitionFilter()
    private var isInactiveDisplay = false
    private var timer: Timer?
    init() {
        if let rawValue = defaults.string(forKey: DefaultsKey.output), let destination = OutputDestination(rawValue: rawValue) {
            outputDestination = destination
        }
        if let brightness = defaults.object(forKey: DefaultsKey.brightness) as? Double {
            brightnessPercent = min(100, max(0, brightness))
        }
        if let rawValue = defaults.string(forKey: DefaultsKey.override) {
            override = PresenceState(rawValue: rawValue)
        }
        let red = defaults.object(forKey: DefaultsKey.customRed) as? Double ?? 0.5
        let green = defaults.object(forKey: DefaultsKey.customGreen) as? Double ?? 0
        let blue = defaults.object(forKey: DefaultsKey.customBlue) as? Double ?? 0.5
        customColor = Color(red: red, green: green, blue: blue)
        if let payload = defaults.string(forKey: DefaultsKey.matrix), let restoredMatrix = LEDMatrix(hexPayload: payload) {
            matrix = restoredMatrix
        }
        presencePolicy = LocalPresencePolicy(
            useMicrophone: defaults.object(forKey: DefaultsKey.microphone) as? Bool ?? true,
            useCamera: defaults.object(forKey: DefaultsKey.camera) as? Bool ?? true,
            useIdleTime: defaults.object(forKey: DefaultsKey.idle) as? Bool ?? true,
            requireTeamsForCallActivity: defaults.object(forKey: DefaultsKey.requireTeams) as? Bool ?? true
        )
        if let delay = defaults.object(forKey: DefaultsKey.transitionDelay) as? Double, [0.0, 10.0, 30.0].contains(delay) {
            automaticTransitionDelay = delay
        }
        if let rawValue = defaults.string(forKey: DefaultsKey.inactiveBehavior), let behavior = InactiveDisplayBehavior(rawValue: rawValue) {
            inactiveDisplayBehavior = behavior
        }
        transitionFilter.delay = automaticTransitionDelay
        startAtLogin = SMAppService.mainApp.status == .enabled
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        NotificationCenter.default.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.setInactiveDisplay(true) } }
        NotificationCenter.default.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.setInactiveDisplay(false) } }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.setInactiveDisplay(true) } }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.setInactiveDisplay(false) } }
    }
    func tick() {
        signals = sampler.sample(policy: presencePolicy)
        let resolved = resolver.resolve(signals)
        let next: PresenceState
        if let override {
            transitionFilter.reset(to: override)
            next = override
        } else {
            next = transitionFilter.resolve(resolved)
        }
        let displayState = isInactiveDisplay ? inactiveDisplayBehavior.presenceState ?? next : next
        let retainsInactiveDisplay = isInactiveDisplay && inactiveDisplayBehavior == .retain
        let command: USBCommand
        if isInactiveDisplay {
            command = .presence(displayState)
        } else if isMatrixOverride {
            command = .matrix(matrix)
        } else if isFiveThirdMode {
            command = .fiveThree
        } else if isCustomColorOverride {
            command = customColorCommand
        } else {
            command = .presence(next)
        }
        let destination = outputDestination
        Task {
            if !retainsInactiveDisplay && destination.usesESP32 && !transport.isConnected { await transport.reconnect() }
            if !retainsInactiveDisplay && destination.usesBusylight && !busylight.isConnected { await busylight.reconnect() }
            if !retainsInactiveDisplay && destination.usesESP32 && transport.isConnected {
                // Ensure the special mark is rendered at its lowest visible brightness.
                if isFiveThirdMode { await transport.send(USBCommand.brightness(1).wireValue) }
                await transport.send(command.wireValue)
            }
            if !retainsInactiveDisplay && destination.usesBusylight && busylight.isConnected {
                if isInactiveDisplay {
                    await busylight.send(displayState, brightnessPercent: brightnessPercent)
                } else if isMatrixOverride || isFiveThirdMode {
                    // Matrix-specific displays have no Busylight equivalent;
                    // keep the secondary device dark rather than showing stale presence.
                    await busylight.send(.offline, brightnessPercent: brightnessPercent)
                } else if isCustomColorOverride {
                    let color = customColorComponents
                    await busylight.send(red: color.red, green: color.green, blue: color.blue, brightnessPercent: brightnessPercent)
                } else {
                    await busylight.send(displayState, brightnessPercent: brightnessPercent)
                }
            }
            connected = (destination.usesESP32 && transport.isConnected) || (destination.usesBusylight && busylight.isConnected)
            deviceName = transport.deviceName
            busylightDeviceName = busylight.deviceName
        }
        if next != state { Logger(subsystem: "com.example.TeamsLight", category: "presence").info("Presence changed \(self.state.rawValue) -> \(next.rawValue)"); state = next }
    }
    func setPresenceOverride(_ state: PresenceState?) {
        isFiveThirdMode = false
        isMatrixOverride = false
        isCustomColorOverride = false
        override = state
        tick()
    }
    private func setInactiveDisplay(_ inactive: Bool) {
        isInactiveDisplay = inactive
        tick()
    }
    func setFiveThirdMode(_ enabled: Bool) {
        isFiveThirdMode = enabled
        if enabled {
            isMatrixOverride = false
            isCustomColorOverride = false
            brightnessPercent = Self.lowestVisibleBrightnessPercent
        }
        tick()
    }
    func activateCustomColor() {
        isFiveThirdMode = false
        isMatrixOverride = false
        isCustomColorOverride = true
        tick()
    }
    func setCustomColor(_ color: Color) {
        customColor = color
        persistCustomColor()
        isFiveThirdMode = false
        isMatrixOverride = false
        isCustomColorOverride = true
        let components = customColorComponents
        Task {
            if outputDestination.usesESP32 { await transport.send(customColorCommand.wireValue) }
            if outputDestination.usesBusylight { await busylight.send(red: components.red, green: components.green, blue: components.blue, brightnessPercent: brightnessPercent) }
        }
    }
    func activateMatrixEditor() {
        isFiveThirdMode = false
        isCustomColorOverride = false
        isMatrixOverride = true
        tick()
    }
    func applyMatrixPreset(_ preset: MatrixPreset) {
        matrix = preset.matrix
        defaults.set(matrix.hexPayload, forKey: DefaultsKey.matrix)
        isFiveThirdMode = false
        isCustomColorOverride = false
        isMatrixOverride = true
        tick()
    }
    func matrixColor(at coordinate: MatrixCoordinate) -> LEDColor {
        matrix[coordinate]
    }
    func setMatrixColor(_ color: Color, at coordinates: Set<MatrixCoordinate>) {
        guard !coordinates.isEmpty else {
            Logger(subsystem: "com.example.TeamsLight", category: "matrix").error("Cannot set a matrix color without selected pixels")
            return
        }
        guard let converted = NSColor(color).usingColorSpace(.deviceRGB) else {
            Logger(subsystem: "com.example.TeamsLight", category: "matrix").error("Could not convert the selected matrix color to RGB")
            return
        }
        func byte(_ component: CGFloat) -> UInt8 {
            UInt8((min(1, max(0, component)) * 255).rounded())
        }
        let ledColor = LEDColor(
            red: byte(converted.redComponent),
            green: byte(converted.greenComponent),
            blue: byte(converted.blueComponent)
        )
        var updatedMatrix = matrix
        updatedMatrix.setColor(ledColor, at: coordinates)
        let wasMatrixOverride = isMatrixOverride
        matrix = updatedMatrix
        defaults.set(updatedMatrix.hexPayload, forKey: DefaultsKey.matrix)
        isFiveThirdMode = false
        isCustomColorOverride = false
        isMatrixOverride = true
        let command: USBCommand
        if wasMatrixOverride, coordinates.count == 1, let coordinate = coordinates.first {
            command = .pixel(coordinate, ledColor)
        } else {
            command = .matrix(updatedMatrix)
        }
        Task {
            if outputDestination.usesESP32 {
                await transport.send(command.wireValue)
            }
        }
    }
    func clearMatrix() {
        matrix = LEDMatrix()
        defaults.set(matrix.hexPayload, forKey: DefaultsKey.matrix)
        activateMatrixEditor()
    }
    func setBrightness() {
        let deviceLevel = Int((brightnessPercent * 15 / 100).rounded())
        Task {
            if outputDestination.usesESP32 { await transport.send(USBCommand.brightness(deviceLevel).wireValue) }
            guard outputDestination.usesBusylight else { return }
            if isCustomColorOverride {
                let color = customColorComponents
                await busylight.send(red: color.red, green: color.green, blue: color.blue, brightnessPercent: brightnessPercent)
            } else {
                await busylight.send(isInactiveDisplay ? inactiveDisplayBehavior.presenceState ?? state : state, brightnessPercent: brightnessPercent)
            }
        }
    }
    func adjustBrightness(by amount: Double) {
        brightnessPercent = min(100, max(0, brightnessPercent + amount))
        setBrightness()
    }
    func setPresencePolicy(_ update: (inout LocalPresencePolicy) -> Void) {
        var updated = presencePolicy
        update(&updated)
        presencePolicy = updated
    }
    private func setLoginItem() {
        do {
            if startAtLogin {
                try SMAppService.mainApp.register() } else {
                    try SMAppService.mainApp.unregister()
                }
        } catch { Logger(subsystem: "com.example.TeamsLight", category: "app").error("Login item update failed") } }
    private func persistCustomColor() {
        let color = customColorComponents
        defaults.set(Double(color.red) / 255, forKey: DefaultsKey.customRed)
        defaults.set(Double(color.green) / 255, forKey: DefaultsKey.customGreen)
        defaults.set(Double(color.blue) / 255, forKey: DefaultsKey.customBlue)
    }
    private func persistPresencePolicy() {
        defaults.set(presencePolicy.useMicrophone, forKey: DefaultsKey.microphone)
        defaults.set(presencePolicy.useCamera, forKey: DefaultsKey.camera)
        defaults.set(presencePolicy.useIdleTime, forKey: DefaultsKey.idle)
        defaults.set(presencePolicy.requireTeamsForCallActivity, forKey: DefaultsKey.requireTeams)
    }
    
    var displayTitle: String {
        if isMatrixOverride { return "Custom Matrix" }
        if isFiveThirdMode { return "5/3 Matrix" }
        return isCustomColorOverride ? "Custom Color" : state.title
    }
    var displayAccentColor: Color {
        if isMatrixOverride { return .cyan }
        if isFiveThirdMode { return .green }
        return isCustomColorOverride ? customColor : state.accentColor
    }
    var menuBarSystemImage: String {
        if isMatrixOverride || isFiveThirdMode { return "square.grid.3x3.fill" }
        return isCustomColorOverride ? "paintpalette.fill" : state.menuBarSystemImage
    }
    
    private var customColorCommand: USBCommand {
        let color = customColorComponents
        return .color(color.red, color.green, color.blue)
    }
    
    private var customColorComponents: (red: UInt8, green: UInt8, blue: UInt8) {
        guard let color = NSColor(customColor).usingColorSpace(.deviceRGB) else {
            return (128, 0, 128)
        }
        return (
            UInt8((color.redComponent * 255).rounded()),
            UInt8((color.greenComponent * 255).rounded()),
            UInt8((color.blueComponent * 255).rounded())
        )
    }
}

enum OutputDestination: String, CaseIterable, Identifiable {
    case esp32
    case busylight
    case both
    
    var id: Self { self }
    var title: String {
        switch self {
        case .esp32: "ESP32"
        case .busylight: "Busylight"
        case .both: "Both"
        }
    }
    var usesESP32: Bool { self != .busylight }
    var usesBusylight: Bool { self != .esp32 }
}

struct DiagnosticsView: View {
    @ObservedObject var controller: AppController
    var body: some View {
        Form {
            LabeledContent("Resolved status", value: controller.state.title);
            LabeledContent("ESP32 USB", value: controller.deviceName ?? "not connected");
            LabeledContent("Kuando Busylight", value: controller.busylightDeviceName ?? "not connected");
            LabeledContent("Serial response", value: controller.transportLastResponse);
            LabeledContent("Protocol response", value: controller.transportResponseStatus);
            Section("Raw provider states") {
                ForEach(controller.signals, id: \.provider) { signal in
                    LabeledContent(signal.provider, value: "\(signal.state.title): \(signal.detail)")
                }
            }
        }
        .padding().frame(minWidth: 500) }
}

private extension AppController {
    var transportLastResponse: String { transport.lastResponse }
    var transportResponseStatus: String {
        switch transport.lastResponseKind {
        case .pong: "Connected"
        case .ok: "Acknowledged"
        case .error: "Firmware error"
        case .unknown: "Waiting for response"
        }
    }
}

private extension PresenceState {
    var accentColor: Color {
        switch self {
        case .available:
            return .green
        case .away:
            return .yellow
        case .busy, .inCall:
            return .red
        case .dnd, .presenting:
            return .purple
        case .inMeeting:
            return .orange
        case .offline, .unknown:
            return .secondary
        }
    }
}
