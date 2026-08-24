import Foundation

enum PresenceState: String, CaseIterable, Sendable {
    case available = "AVAILABLE", busy = "BUSY", inCall = "IN_CALL", inMeeting = "IN_MEETING"
    case dnd = "DND", presenting = "PRESENTING", away = "AWAY", offline = "OFFLINE", unknown = "UNKNOWN"
    
    var title: String {
        switch self {
        case .dnd:
            return "Do Not Disturb"
        default:
            return rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    
    var menuBarSystemImage: String {
        switch self {
        case .available:
            return "checkmark.circle.fill"
        case .busy:
            return "minus.circle.fill"
        case .dnd:
            return "hand.raised.fill"
        case .away:
            return "clock.fill"
        case .inCall:
            return "phone.fill"
        case .inMeeting:
            return "person.2.fill"
        case .presenting:
            return "rectangle.on.rectangle"
        case .offline:
            return "circle.slash"
        case .unknown:
            return "questionmark.circle"
        }
    }
    static let resolutionOrder: [PresenceState] = [.presenting, .inCall, .inMeeting, .dnd, .busy, .away, .available, .offline, .unknown]
}

enum InactiveDisplayBehavior: String, CaseIterable, Identifiable, Sendable {
    case retain
    case away
    case off

    var id: Self { self }
    var title: String {
        switch self {
        case .retain: "Keep Current Light"
        case .away: "Show Away"
        case .off: "Turn Off"
        }
    }
    var presenceState: PresenceState? {
        switch self {
        case .retain: nil
        case .away: .away
        case .off: .offline
        }
    }
}

struct PresenceSignal: Sendable, Equatable {
    let provider: String
    let state: PresenceState
    let detail: String
}

protocol PresenceProvider: Sendable {
    var name: String { get }
    func sample() -> PresenceSignal
}

struct StateAppearanceProfile: Codable, Equatable, Sendable {
    var esp32Color: LEDColor
    var busylightColor: LEDColor
    var esp32Brightness: Double = 100
    var busylightBrightness: Double = 100
}

enum StateAppearanceProfiles {
    static func `default`(for state: PresenceState) -> StateAppearanceProfile {
        let color: LEDColor
        switch state {
        case .available: color = .init(red: 0, green: 255, blue: 0)
        case .busy, .inCall, .inMeeting: color = .init(red: 255, green: 0, blue: 0)
        case .dnd: color = .init(red: 255, green: 0, blue: 255)
        case .presenting: color = .init(red: 170, green: 0, blue: 255)
        case .away: color = .init(red: 255, green: 145, blue: 0)
        case .offline: color = .black
        case .unknown: color = .init(red: 64, green: 64, blue: 64)
        }
        return StateAppearanceProfile(esp32Color: color, busylightColor: color)
    }
}
