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
                Divider()
                Button {
                    controller.test()
                } label: {
                    Label("Test Lights", systemImage: "lightbulb")
                }
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
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    ForEach(PresenceChoice.all.prefix(3)) { choice in
                        PresenceChoiceButton(choice: choice, controller: controller)
                    }
                }
                GridRow {
                    ForEach(PresenceChoice.all.suffix(3)) { choice in
                        PresenceChoiceButton(choice: choice, controller: controller)
                    }
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
    @Published var state: PresenceState = .unknown
    @Published var signals: [PresenceSignal] = []
    @Published var connected = false
    @Published var deviceName: String?
    @Published var busylightDeviceName: String?
    @Published var outputDestination: OutputDestination = .both { didSet { tick() } }
    // Level 1 is the lowest visible ESP32 matrix brightness (level 0 turns it off).
    private static let lowestVisibleBrightnessPercent = 100.0 / 15.0
    @Published private(set) var isFiveThirdMode = false
    @Published var brightnessPercent = 100.0
    @Published var override: PresenceState?
    @Published var customColor = Color.purple
    @Published var isCustomColorOverride = false
    @Published private(set) var matrix = LEDMatrix()
    @Published private(set) var isMatrixOverride = false
    @Published var startAtLogin = false { didSet { setLoginItem() } }
    private let transport = USBSerialTransport()
    private let busylight = KuandoBusylightTransport()
    private let sampler = LocalPresenceSampler(); private let resolver = PresenceResolver()
    private var timer: Timer?
    init() {
        startAtLogin = SMAppService.mainApp.status == .enabled
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        NotificationCenter.default.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    func tick() {
        signals = sampler.sample(); let next = override ?? resolver.resolve(signals)
        let command: USBCommand
        if isMatrixOverride {
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
            if destination.usesESP32 && !transport.isConnected { await transport.reconnect() }
            if destination.usesBusylight && !busylight.isConnected { await busylight.reconnect() }
            if destination.usesESP32 && transport.isConnected {
                // Ensure the special mark is rendered at its lowest visible brightness.
                if isFiveThirdMode { await transport.send(USBCommand.brightness(1).wireValue) }
                await transport.send(command.wireValue)
            }
            if destination.usesBusylight && busylight.isConnected {
                if isCustomColorOverride {
                    let color = customColorComponents
                    await busylight.send(red: color.red, green: color.green, blue: color.blue, brightnessPercent: brightnessPercent)
                } else {
                    await busylight.send(next, brightnessPercent: brightnessPercent)
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
                await busylight.send(override ?? resolver.resolve(signals), brightnessPercent: brightnessPercent)
            }
        }
    }
    func adjustBrightness(by amount: Double) {
        brightnessPercent = min(100, max(0, brightnessPercent + amount))
        setBrightness()
    }
    func test() { Task {
        if outputDestination.usesESP32 { await transport.send(USBCommand.test.wireValue) }
        if outputDestination.usesBusylight {
            for color in [(UInt8(255), UInt8(0), UInt8(0)), (0, 255, 0), (0, 0, 255)] {
                await busylight.send(red: color.0, green: color.1, blue: color.2, brightnessPercent: brightnessPercent)
                try? await Task.sleep(for: .milliseconds(350))
            }
            tick()
        }
    } }
    private func setLoginItem() { do { if startAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { Logger(subsystem: "com.example.TeamsLight", category: "app").error("Login item update failed") } }

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
    var body: some View { Form { LabeledContent("Resolved status", value: controller.state.title); LabeledContent("ESP32 USB", value: controller.deviceName ?? "not connected"); LabeledContent("Kuando Busylight", value: controller.busylightDeviceName ?? "not connected"); LabeledContent("Serial response", value: controller.transportLastResponse); Section("Raw provider states") { ForEach(controller.signals, id: \.provider) { signal in LabeledContent(signal.provider, value: "\(signal.state.title): \(signal.detail)") } } }.padding().frame(minWidth: 500) }
}

private extension AppController { var transportLastResponse: String { transport.lastResponse } }

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
