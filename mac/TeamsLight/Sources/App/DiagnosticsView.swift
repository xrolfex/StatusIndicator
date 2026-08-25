import SwiftUI

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
        
        if let window { bringToForeground(window) }
    }
}
struct DiagnosticsView: View {
    @ObservedObject var controller: AppController
    var body: some View {
        Form {
            LabeledContent("Resolved status", value: controller.state.title);
            LabeledContent("Selected ESP32", value: controller.selectedESP32Path.isEmpty ? "automatic" : controller.selectedESP32Path);
            LabeledContent("Selected Busylight", value: controller.selectedBusylightID.isEmpty ? "all compatible devices" : controller.selectedBusylightID);
            LabeledContent("ESP32 USB", value: controller.deviceName ?? "not connected");
            LabeledContent("Kuando Busylight", value: controller.busylightDeviceName ?? "not connected");
            LabeledContent("Serial response", value: controller.transportLastResponse);
            LabeledContent("Protocol response", value: controller.transportResponseStatus);
            LabeledContent("Firmware", value: controller.transportFirmwareStatus);
            LabeledContent("App version", value: controller.appVersion);
            if let health = controller.transportFirmwareHealth {
                LabeledContent("Firmware uptime", value: "\(health.uptimeSeconds / 3600)h \((health.uptimeSeconds % 3600) / 60)m")
                LabeledContent("Free memory", value: "\(health.freeHeapBytes.formatted()) bytes")
                LabeledContent("Reset reason", value: "\(health.resetReason)")
            }
            if let hint = controller.transportRecoveryHint {
                LabeledContent("USB recovery", value: hint)
            }
            LabeledContent("Next calendar event", value: controller.nextMeetingSummary);
            Button("Reconnect Devices") { controller.reconnectDevices() }
            Section("Raw provider states") {
                ForEach(controller.signals, id: \.provider) { signal in
                    LabeledContent(signal.provider, value: "\(signal.state.title): \(signal.detail)")
                }
            }
        }
        .padding().frame(minWidth: 500) }
}

extension AppController {
    var transportLastResponse: String { transport.lastResponse }
    var transportResponseStatus: String {
        switch transport.lastResponseKind {
        case .pong: "Connected"
        case .ok: "Acknowledged"
        case .error: "Firmware error"
        case .unknown: "Waiting for response"
        }
    }
    var transportFirmwareStatus: String { transport.isLegacyFirmware ? "Legacy compatible" : "Current protocol" }
    var transportRecoveryHint: String? { transport.recoveryHint }
    var transportFirmwareHealth: FirmwareHealth? { transport.firmwareHealth }
    var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }
}

extension PresenceState {
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
