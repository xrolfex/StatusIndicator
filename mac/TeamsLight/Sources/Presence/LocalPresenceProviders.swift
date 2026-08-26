import AppKit
import CoreAudio
import CoreMediaIO
import CoreGraphics
import Foundation

struct TeamsProcessPresenceProvider: PresenceProvider {
    private static let bundleIdentifierPrefixes = [
        "com.microsoft.teams",
        "com.microsoft.teams2"
    ]

    let name = "Teams process"

    static func matches(bundleIdentifier: String) -> Bool {
        let identifier = bundleIdentifier.lowercased()
        return bundleIdentifierPrefixes.contains {
            identifier == $0 || identifier.hasPrefix("\($0).")
        }
    }

    func sample() -> PresenceSignal {
        let running = NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier.map(Self.matches) == true
                || app.localizedName?.localizedCaseInsensitiveContains("teams") == true
        }
        return PresenceSignal(provider: name, state: running ? .available : .unknown, detail: running ? "running" : "not running")
    }
}

struct AudioProcessActivity: Equatable, Sendable {
    let bundleIdentifier: String
    let isRunningInput: Bool
    let isRunningOutput: Bool
}

struct AudioProcessActivitySummary: Equatable, Sendable {
    let teamsInputActive: Bool
    let anyInputActive: Bool
    let notificationOutputActive: Bool

    init(activities: [AudioProcessActivity]) {
        teamsInputActive = activities.contains {
            $0.isRunningInput && TeamsProcessPresenceProvider.matches(bundleIdentifier: $0.bundleIdentifier)
        }
        anyInputActive = activities.contains(where: \.isRunningInput)
        notificationOutputActive = activities.contains {
            guard $0.isRunningOutput else { return false }
            let identifier = $0.bundleIdentifier.lowercased()
            return identifier == "systemsoundserverd"
                || identifier == "com.apple.systemsoundserverd"
                || TeamsProcessPresenceProvider.matches(bundleIdentifier: identifier)
        }
    }
}

/// Uses the macOS process-level HAL properties when available. Unlike device
/// state, these distinguish microphone capture from playback on duplex devices.
struct CoreAudioProcessActivityProvider: Sendable {
    func sample() -> AudioProcessActivitySummary? {
        guard let activities = processActivities() else { return nil }
        return AudioProcessActivitySummary(activities: activities)
    }

    private func processActivities() -> [AudioProcessActivity]? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(system, &address) else { return nil }
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
        if size == 0 { return [] }
        var objects = Array(
            repeating: AudioObjectID(),
            count: Int(size) / MemoryLayout<AudioObjectID>.size
        )
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return nil }
        return objects.compactMap(activity)
    }

    private func activity(for process: AudioObjectID) -> AudioProcessActivity? {
        guard let isRunningInput = boolProperty(kAudioProcessPropertyIsRunningInput, process: process),
              let isRunningOutput = boolProperty(kAudioProcessPropertyIsRunningOutput, process: process),
              isRunningInput || isRunningOutput else {
            return nil
        }
        return AudioProcessActivity(
            bundleIdentifier: bundleIdentifier(process: process) ?? "",
            isRunningInput: isRunningInput,
            isRunningOutput: isRunningOutput
        )
    }

    private func boolProperty(
        _ selector: AudioObjectPropertySelector,
        process: AudioObjectID
    ) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(process, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value != 0
    }

    private func bundleIdentifier(process: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr,
              let value else {
            return nil
        }
        let identifier = value.takeRetainedValue() as String
        return identifier.isEmpty ? nil : identifier
    }
}

/// Public CoreAudio device state only. This neither opens an input nor reads audio.
struct MicrophonePresenceProvider: PresenceProvider {
    let name = "Microphone activity"
    func sample() -> PresenceSignal {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return PresenceSignal(provider: name, state: .unknown, detail: "CoreAudio unavailable")
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = Array(repeating: AudioDeviceID(), count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else {
            return PresenceSignal(provider: name, state: .unknown, detail: "device list unavailable")
        }
        for device in devices where hasInput(device) && isRunning(device) {
            return PresenceSignal(provider: name, state: .busy, detail: "input device active")
        }
        return PresenceSignal(provider: name, state: .unknown, detail: "no active input")
    }
    private func hasInput(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer) == noErr else { return false }
        return buffer.assumingMemoryBound(to: AudioBufferList.self).pointee.mNumberBuffers > 0
    }
    private func isRunning(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr && running != 0
    }
}

struct CameraPresenceProvider: PresenceProvider {
    let name = "Camera activity"
    func sample() -> PresenceSignal {
        let active = hasRunningCamera()
        return PresenceSignal(provider: name, state: active ? .busy : .unknown, detail: active ? "camera device active" : "no active camera")
    }
    /// CoreMediaIO reports whether a video device is running without opening,
    /// capturing from, or inspecting that device.
    private func hasRunningCamera() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: UInt32(kCMIOHardwarePropertyDevices),
            mScope: UInt32(kCMIOObjectPropertyScopeGlobal),
            mElement: UInt32(kCMIOObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == noErr else { return false }
        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var devices = Array(repeating: CMIOObjectID(), count: count)
        var dataUsed = size
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &dataUsed, &devices) == noErr else { return false }
        for device in devices {
            var runningAddress = CMIOObjectPropertyAddress(
                mSelector: UInt32(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: UInt32(kCMIOObjectPropertyScopeGlobal),
                mElement: UInt32(kCMIOObjectPropertyElementMain)
            )
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            if CMIOObjectGetPropertyData(device, &runningAddress, 0, nil, runningSize, &runningSize, &running) == noErr, running != 0 {
                return true
            }
        }
        return false
    }
}

struct IdlePresenceProvider: PresenceProvider {
    let name = "Idle time"
    let threshold: TimeInterval = 300
    func sample() -> PresenceSignal {
        // CoreGraphics defines kCGAnyInputEventType as all bits set. `.null`
        // only asks for a synthetic null event and can therefore look idle for
        // many hours while the user is actively using the Mac.
        let anyInputEvent = CGEventType(rawValue: UInt32.max)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputEvent)
        return PresenceSignal(provider: name, state: idle >= threshold ? .away : .unknown, detail: String(format: "%.0f seconds", idle))
    }
}

/// Controls which local signals contribute to automatic presence. The default
/// keeps activity attribution conservative: a camera or microphone only means
/// "in a call" while Teams is running.
struct LocalPresencePolicy: Codable, Sendable, Equatable {
    var useMicrophone = true
    var useCamera = true
    var useIdleTime = true
    var requireTeamsForCallActivity = true

    func attributedActivityState(isActive: Bool, teamsRunning: Bool, state: PresenceState) -> PresenceState {
        guard isActive && (teamsRunning || !requireTeamsForCallActivity) else { return .unknown }
        return state
    }
}

/// Combines public local signals without opening or capturing media devices.
struct LocalPresenceSampler: Sendable {
    static let teamsMicrophoneProvider = "Teams + microphone"
    static let notificationAudioProvider = "Notification audio"
    static let notificationAudioActiveDetail = "active"
    static let notificationAudioInactiveDetail = "inactive"

    private let teams = TeamsProcessPresenceProvider()
    private let processAudio = CoreAudioProcessActivityProvider()
    private let microphone = MicrophonePresenceProvider()
    private let camera = CameraPresenceProvider()
    private let idle = IdlePresenceProvider()
    func sample(policy: LocalPresencePolicy = .init()) -> [PresenceSignal] {
        let teamSignal = teams.sample()
        let processAudioSummary = processAudio.sample()
        let cameraSignal = camera.sample()
        let teamsRunning = teamSignal.detail == "running"
        var result = [teamSignal]
        if let processAudioSummary {
            result.append(PresenceSignal(
                provider: Self.notificationAudioProvider,
                state: .unknown,
                detail: processAudioSummary.notificationOutputActive
                    ? Self.notificationAudioActiveDetail
                    : Self.notificationAudioInactiveDetail
            ))
        }
        if policy.useCamera {
            let cameraState = policy.attributedActivityState(isActive: cameraSignal.state == .busy, teamsRunning: teamsRunning, state: .busy)
            if cameraState == .busy {
                result.append(PresenceSignal(provider: "Camera activity", state: cameraState, detail: teamsRunning ? "camera active while Teams is running" : "camera device active"))
            } else if cameraSignal.state == .busy {
                result.append(PresenceSignal(provider: "Camera activity", state: .unknown, detail: "active, ignored because Teams is not running"))
            } else {
                result.append(cameraSignal)
            }
        }
        if policy.useIdleTime { result.append(idle.sample()) }
        if policy.useMicrophone {
            if let processAudioSummary {
                if processAudioSummary.teamsInputActive {
                    result.append(PresenceSignal(
                        provider: Self.teamsMicrophoneProvider,
                        state: .inCall,
                        detail: "Teams input active"
                    ))
                } else if !policy.requireTeamsForCallActivity && processAudioSummary.anyInputActive {
                    result.append(PresenceSignal(
                        provider: "Microphone activity",
                        state: .busy,
                        detail: "non-Teams input active"
                    ))
                } else {
                    result.append(PresenceSignal(
                        provider: "Microphone activity",
                        state: .unknown,
                        detail: "no attributed active input"
                    ))
                }
                return result
            }

            let micSignal = microphone.sample()
            let micState = policy.attributedActivityState(
                isActive: micSignal.state == .busy,
                teamsRunning: teamsRunning,
                state: teamsRunning ? .inCall : .busy
            )
            if micState == .inCall {
                result.append(PresenceSignal(provider: Self.teamsMicrophoneProvider, state: micState, detail: "inferred from active input"))
            } else if micState == .busy {
                result.append(PresenceSignal(provider: "Microphone activity", state: micState, detail: "input device active"))
            } else {
                result.append(PresenceSignal(
                    provider: micSignal.provider,
                    state: micSignal.state == .busy ? .unknown : micSignal.state,
                    detail: micSignal.state == .busy ? "active, ignored because Teams is not running" : micSignal.detail
                ))
            }
        }
        return result
    }
}
