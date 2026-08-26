import SwiftUI

@MainActor
final class AutomationWindowPresenter {
    static let shared = AutomationWindowPresenter()

    private var window: NSWindow?

    private init() {}

    func show(controller: AppController) {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Teams Light Automation"
            window.contentView = NSHostingView(rootView: AutomationSettingsView(controller: controller))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct AutomationSettingsView: View {
    @ObservedObject var controller: AppController

    private let brightnessStates: [PresenceState] = [
        .available, .busy, .inCall, .inMeeting, .dnd, .presenting, .away, .offline
    ]

    var body: some View {
        Form {
            Section("Quiet Hours") {
                Toggle("Enable quiet hours", isOn: $controller.automationSettings.quietHoursEnabled)
                HStack {
                    Picker("Start", selection: $controller.automationSettings.quietStartHour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(hourLabel(hour)).tag(hour)
                        }
                    }
                    Picker("End", selection: $controller.automationSettings.quietEndHour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(hourLabel(hour)).tag(hour)
                        }
                    }
                }
                LabeledSlider(
                    title: "Maximum brightness",
                    value: $controller.automationSettings.quietBrightnessPercent
                )
            }

            Section("Presence Signals") {
                Toggle(
                    "Calendar meetings",
                    isOn: Binding(
                        get: { controller.automationSettings.calendarMeetingsEnabled },
                        set: { controller.setCalendarAutomationEnabled($0) }
                    )
                )
                Toggle(
                    "macOS Focus",
                    isOn: Binding(
                        get: { controller.automationSettings.focusEnabled },
                        set: { controller.setFocusAutomationEnabled($0) }
                    )
                )
                Text("Calendar access only checks whether a non-free event is active; event titles are never displayed or stored. macOS does not expose a public system-wide screen-sharing signal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Per-State Brightness") {
                ForEach(brightnessStates, id: \.self) { state in
                    LabeledSlider(
                        title: state.title,
                        value: Binding(
                            get: { controller.automationSettings.brightnessPercent(for: state) },
                            set: { controller.setStateBrightness($0, for: state) }
                        )
                    )
                }
                Text("These percentages scale the main brightness setting. Quiet hours apply an additional maximum.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let message = controller.automationMessage {
                Section("Status") {
                    Text(message)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 520, minHeight: 620)
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        return components.date.map {
            $0.formatted(date: .omitted, time: .shortened)
        } ?? "\(hour):00"
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(title)
                .frame(width: 150, alignment: .leading)
            Slider(value: $value, in: 0...100)
            Text("\(value, format: .number.precision(.fractionLength(0)))%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }
}
