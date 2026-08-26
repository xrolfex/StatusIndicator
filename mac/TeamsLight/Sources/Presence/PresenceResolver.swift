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

struct TeamsMicrophoneActivityClassifier: Sendable {
    // Teams chat chimes briefly run an input-capable CoreAudio device. Holding
    // call state avoids rendering that short pulse as an actual call.
    static let callConfirmationInterval: TimeInterval = 2

    private var activityStartedAt: Date?
    private var lastNotificationAt: Date?

    mutating func classify(
        _ signals: [PresenceSignal],
        now: Date = .now
    ) -> (presenceSignals: [PresenceSignal], detectedNotification: Bool) {
        let isActive = signals.contains {
            $0.provider == LocalPresenceSampler.teamsMicrophoneProvider && $0.state == .inCall
        }

        if isActive {
            if activityStartedAt == nil { activityStartedAt = now }
            guard let activityStartedAt,
                  now.timeIntervalSince(activityStartedAt) < Self.callConfirmationInterval else {
                return (signals, false)
            }
            return (
                signals.filter { $0.provider != LocalPresenceSampler.teamsMicrophoneProvider },
                false
            )
        }

        guard let activityStartedAt else { return (signals, false) }
        self.activityStartedAt = nil
        let wasBrief = now.timeIntervalSince(activityStartedAt) < Self.callConfirmationInterval
        let isOutsideCooldown = lastNotificationAt.map {
            now.timeIntervalSince($0) >= Self.callConfirmationInterval
        } ?? true
        let detectedNotification = wasBrief && isOutsideCooldown
        if detectedNotification { lastNotificationAt = now }
        return (signals, detectedNotification)
    }
}
