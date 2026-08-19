import AppKit
import CoreAudio
import CoreMediaIO
import CoreGraphics
import Foundation

struct TeamsProcessPresenceProvider: PresenceProvider {
    let name = "Teams process"
    func sample() -> PresenceSignal {
        let running = NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == "com.microsoft.teams" || app.localizedName?.localizedCaseInsensitiveContains("teams") == true
        }
        return PresenceSignal(provider: name, state: running ? .available : .unknown, detail: running ? "running" : "not running")
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

/// Combines public local signals. Teams + active mic is intentionally an inference, not app-level microphone attribution.
struct LocalPresenceSampler: Sendable {
    private let teams = TeamsProcessPresenceProvider()
    private let microphone = MicrophonePresenceProvider()
    private let camera = CameraPresenceProvider()
    private let idle = IdlePresenceProvider()
    func sample() -> [PresenceSignal] {
        let teamSignal = teams.sample(); let micSignal = microphone.sample(); let cameraSignal = camera.sample()
        var result = [teamSignal, cameraSignal, idle.sample()]
        if micSignal.state == .busy && teamSignal.detail == "running" {
            result.append(PresenceSignal(provider: "Teams + microphone", state: .inCall, detail: "inferred from active input"))
        } else { result.append(micSignal) }
        return result
    }
}
