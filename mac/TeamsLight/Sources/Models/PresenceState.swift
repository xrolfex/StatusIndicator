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
