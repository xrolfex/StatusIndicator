import SwiftUI

struct TeamsLightPopover: View {
    @ObservedObject var controller: AppController
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatusHeader(controller: controller); Divider()
            PresenceOverrideSection(controller: controller); BrightnessSection(controller: controller)
        }.padding().frame(width: 320)
    }
}

private struct StatusHeader: View {
    @ObservedObject var controller: AppController
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(controller.displayAccentColor).frame(width: 10, height: 10).shadow(color: controller.displayAccentColor.opacity(0.45), radius: 3).accessibilityHidden(true)
            Text(controller.displayTitle).font(.headline)
            Spacer()
            Menu {
                Button { SettingsWindowPresenter.shared.show(controller: controller) } label: { Label("Open Settings…", systemImage: "gearshape") }
                Divider()
                Button { DiagnosticsWindowPresenter.shared.show(controller: controller) } label: { Label("Diagnostics", systemImage: "waveform.path.ecg") }
                Button { DeskDisplayWindowPresenter.shared.show(controller: controller) } label: { Label("Desk Display…", systemImage: "sparkles") }
                Menu("Matrix & Appearance") {
                    Button { MatrixPresetWindowPresenter.shared.show(controller: controller) } label: { Label("Matrix Presets…", systemImage: "square.grid.2x2") }.disabled(!controller.outputDestination.usesESP32)
                    Button { LEDMatrixWindowPresenter.shared.show(controller: controller) } label: { Label("LED Matrix Editor…", systemImage: "square.grid.3x3.fill") }.disabled(!controller.outputDestination.usesESP32)
                    Toggle("5/3 Matrix Pattern", isOn: Binding(get: { controller.isFiveThirdMode }, set: { controller.setFiveThirdMode($0) })).disabled(!controller.outputDestination.usesESP32 || !controller.supportsFiveThree)
                    Button { CustomColorPanelPresenter.shared.show(controller: controller) } label: { Label("Custom Color…", systemImage: "paintpalette") }
                }
                Divider(); Button("Quit Teams Light") { NSApplication.shared.terminate(nil) }
            } label: { Image(systemName: "gearshape").frame(width: 22, height: 22) }.menuStyle(.borderlessButton).help("Settings")
        }
    }
}

private struct PresenceOverrideSection: View {
    @ObservedObject var controller: AppController
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Presence").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(PresenceChoice.all) { choice in PresenceChoiceButton(choice: choice, controller: controller) }
            }.frame(maxWidth: .infinity)
        }
    }
}

private struct PresenceChoiceButton: View {
    let choice: PresenceChoice
    @ObservedObject var controller: AppController
    var body: some View {
        Button(choice.title) { controller.setPresenceOverride(choice.state) }
            .buttonStyle(PresenceChipButtonStyle(isSelected: !controller.isCustomColorOverride && !controller.isMatrixOverride && !controller.isFiveThirdMode && controller.override == choice.state))
    }
}

private struct PresenceChoice: Identifiable {
    let id: String; let title: String; let state: PresenceState?
    static let all = [
        PresenceChoice(id: "auto", title: "Auto", state: nil), PresenceChoice(id: "available", title: "Available", state: .available), PresenceChoice(id: "busy", title: "Busy", state: .busy), PresenceChoice(id: "in-call", title: "In Call", state: .inCall), PresenceChoice(id: "in-meeting", title: "Meeting", state: .inMeeting), PresenceChoice(id: "presenting", title: "Presenting", state: .presenting), PresenceChoice(id: "dnd", title: "DND", state: .dnd), PresenceChoice(id: "away", title: "Away", state: .away), PresenceChoice(id: "offline", title: "Offline", state: .offline)
    ]
}

@MainActor
final class CustomColorPanelPresenter: NSObject {
    static let shared = CustomColorPanelPresenter(); private weak var controller: AppController?
    func show(controller: AppController) {
        self.controller = controller; let panel = NSColorPanel.shared; panel.color = NSColor(controller.customColor); panel.showsAlpha = false; panel.isContinuous = true; panel.setTarget(self); panel.setAction(#selector(colorDidChange(_:))); panel.orderFrontRegardless(); panel.makeKeyAndOrderFront(nil)
    }
    @objc private func colorDidChange(_ sender: NSColorPanel) { controller?.setCustomColor(Color(sender.color)) }
}

private struct PresenceChipButtonStyle: ButtonStyle {
    let isSelected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.caption).lineLimit(1).frame(maxWidth: .infinity, minHeight: 26).foregroundStyle(isSelected ? Color.white : Color.primary).background(isSelected ? Color.accentColor : Color.secondary.opacity(configuration.isPressed ? 0.25 : 0.12), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct BrightnessSection: View {
    @ObservedObject var controller: AppController
    var body: some View {
        VStack(spacing: 7) {
            HStack { Text("Brightness").font(.caption).foregroundStyle(.secondary); Spacer(); Text("\(controller.brightnessPercent, format: .number.precision(.fractionLength(0)))%").font(.caption).monospacedDigit().foregroundStyle(.secondary) }
            HStack(spacing: 8) { Image(systemName: "sun.min").foregroundStyle(.secondary); Slider(value: $controller.brightnessPercent, in: 0...100, onEditingChanged: { if !$0 { controller.setBrightness() } }).accessibilityLabel("Brightness"); Image(systemName: "sun.max.fill").foregroundStyle(.secondary) }
        }
    }
}
