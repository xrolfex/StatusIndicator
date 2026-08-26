import Foundation

struct AutomationSettings: Codable, Equatable, Sendable {
    var quietHoursEnabled = false
    var quietStartHour = 22
    var quietEndHour = 7
    var quietBrightnessPercent = 20.0
    var calendarMeetingsEnabled = false
    var focusEnabled = false
    var stateBrightnessPercent: [String: Double] = [:]

    static let `default` = AutomationSettings()
    static let defaultsKey = "automationSettings.v1"

    func isQuietHours(at date: Date, calendar: Calendar = .current) -> Bool {
        guard quietHoursEnabled else { return false }
        let hour = calendar.component(.hour, from: date)
        if quietStartHour == quietEndHour { return true }
        if quietStartHour < quietEndHour {
            return hour >= quietStartHour && hour < quietEndHour
        }
        return hour >= quietStartHour || hour < quietEndHour
    }

    func effectiveBrightness(
        basePercent: Double,
        state: PresenceState,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> Double {
        let stateScale = stateBrightnessPercent[state.rawValue] ?? 100
        var result = min(100, max(0, basePercent * stateScale / 100))
        if isQuietHours(at: date, calendar: calendar) {
            result = min(result, min(100, max(0, quietBrightnessPercent)))
        }
        return result
    }

    func brightnessPercent(for state: PresenceState) -> Double {
        stateBrightnessPercent[state.rawValue] ?? 100
    }

    mutating func setBrightnessPercent(_ percent: Double, for state: PresenceState) {
        stateBrightnessPercent[state.rawValue] = min(100, max(0, percent))
    }

    static func load(from defaults: UserDefaults = .standard) throws -> AutomationSettings {
        guard let data = defaults.data(forKey: defaultsKey) else { return .default }
        return try JSONDecoder().decode(AutomationSettings.self, from: data)
    }

    func save(to defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }
}
