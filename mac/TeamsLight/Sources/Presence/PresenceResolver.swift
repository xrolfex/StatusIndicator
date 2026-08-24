import Foundation

struct PresenceResolver: Sendable {
    func resolve(_ signals: [PresenceSignal]) -> PresenceState {
        let states = Set(signals.map(\.state))
        return PresenceState.resolutionOrder.first(where: states.contains) ?? .unknown
    }
}

/// Holds an automatic state until a different proposed state has remained
/// stable for the configured interval. Manual overrides remain immediate.
struct PresenceTransitionFilter: Sendable {
    private(set) var committed: PresenceState
    private var candidate: PresenceState?
    private var candidateSince: Date?
    var delay: TimeInterval

    init(initial: PresenceState = .unknown, delay: TimeInterval = 10) {
        committed = initial
        self.delay = delay
    }

    mutating func resolve(_ proposed: PresenceState, now: Date = .now) -> PresenceState {
        guard proposed != committed else {
            candidate = nil
            candidateSince = nil
            return committed
        }
        guard delay > 0 else {
            reset(to: proposed)
            return committed
        }
        guard candidate == proposed, let candidateSince else {
            candidate = proposed
            self.candidateSince = now
            return committed
        }
        if now.timeIntervalSince(candidateSince) >= delay { reset(to: proposed) }
        return committed
    }

    mutating func reset(to state: PresenceState) {
        committed = state
        candidate = nil
        candidateSince = nil
    }
}
