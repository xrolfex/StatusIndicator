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
            Divider()
            QuickActionsSection(controller: controller)
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
                Text(deviceDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Menu {
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

    private var deviceDescription: String {
        if controller.connected {
            return controller.deviceName ?? "Connected"
        }
        return "Device disconnected"
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
        .buttonStyle(PresenceChipButtonStyle(isSelected: !controller.isCustomColorOverride && controller.override == choice.state))
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

struct QuickActionsSection: View {
    @ObservedObject var controller: AppController

    var body: some View {
        HStack(spacing: 8) {
            Button {
                controller.test()
            } label: {
                Label("Test LEDs", systemImage: "lightbulb")
                    .frame(maxWidth: .infinity)
            }
            Button {
                DiagnosticsWindowPresenter.shared.show(controller: controller)
            } label: {
                Label("Diagnostics", systemImage: "waveform.path.ecg")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
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
    @Published var brightnessPercent = 100.0
    @Published var override: PresenceState?
    @Published var customColor = Color.purple
    @Published var isCustomColorOverride = false
    @Published var startAtLogin = false { didSet { setLoginItem() } }
    private let transport = USBSerialTransport()
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
        let command = isCustomColorOverride ? customColorCommand.wireValue : USBCommand.presence(next).wireValue
        Task { if !transport.isConnected { await transport.reconnect() }; if transport.isConnected { await transport.send(command) }; connected = transport.isConnected; deviceName = transport.deviceName }
        if next != state { Logger(subsystem: "com.example.TeamsLight", category: "presence").info("Presence changed \(self.state.rawValue) -> \(next.rawValue)"); state = next }
    }
    func setPresenceOverride(_ state: PresenceState?) {
        isCustomColorOverride = false
        override = state
        tick()
    }
    func activateCustomColor() {
        isCustomColorOverride = true
        tick()
    }
    func setCustomColor(_ color: Color) {
        customColor = color
        isCustomColorOverride = true
        Task { await transport.send(customColorCommand.wireValue) }
    }
    func setBrightness() {
        let deviceLevel = Int((brightnessPercent * 15 / 100).rounded())
        Task { await transport.send(USBCommand.brightness(deviceLevel).wireValue) }
    }
    func adjustBrightness(by amount: Double) {
        brightnessPercent = min(100, max(0, brightnessPercent + amount))
        setBrightness()
    }
    func test() { Task { await transport.send(USBCommand.test.wireValue) } }
    private func setLoginItem() { do { if startAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { Logger(subsystem: "com.example.TeamsLight", category: "app").error("Login item update failed") } }

    var displayTitle: String { isCustomColorOverride ? "Custom Color" : state.title }
    var displayAccentColor: Color { isCustomColorOverride ? customColor : state.accentColor }
    var menuBarSystemImage: String { isCustomColorOverride ? "paintpalette.fill" : state.menuBarSystemImage }

    private var customColorCommand: USBCommand {
        guard let color = NSColor(customColor).usingColorSpace(.deviceRGB) else {
            return .color(128, 0, 128)
        }
        return .color(
            UInt8((color.redComponent * 255).rounded()),
            UInt8((color.greenComponent * 255).rounded()),
            UInt8((color.blueComponent * 255).rounded())
        )
    }
}

struct DiagnosticsView: View {
    @ObservedObject var controller: AppController
    var body: some View { Form { LabeledContent("Resolved status", value: controller.state.title); LabeledContent("USB device", value: controller.deviceName ?? "not connected"); LabeledContent("Serial response", value: controller.transportLastResponse); Section("Raw provider states") { ForEach(controller.signals, id: \.provider) { signal in LabeledContent(signal.provider, value: "\(signal.state.title): \(signal.detail)") } } }.padding().frame(minWidth: 500) }
}

private extension AppController { var transportLastResponse: String { transport.lastResponse } }

private extension PresenceState {
    var accentColor: Color {
        switch self {
        case .available:
            return .green
        case .away:
            return .yellow
        case .busy, .dnd, .inCall, .presenting:
            return .red
        case .inMeeting:
            return .orange
        case .offline, .unknown:
            return .secondary
        }
    }
}
