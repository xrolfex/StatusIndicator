import Foundation

struct PresenceResolver: Sendable {
    func resolve(_ signals: [PresenceSignal]) -> PresenceState {
        let states = Set(signals.map(\.state))
        return PresenceState.resolutionOrder.first(where: states.contains) ?? .unknown
    }
}
