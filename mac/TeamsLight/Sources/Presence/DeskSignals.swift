import AVFoundation
import Combine
import EventKit
import Foundation

@MainActor
final class CalendarMonitor: ObservableObject {
    @Published private(set) var nextMeetingTitle: String?
    @Published private(set) var nextMeetingDate: Date?
    private let store = EKEventStore()
    private var lastRefresh = Date.distantPast

    var hasUpcomingMeeting: Bool {
        guard let nextMeetingDate else { return false }
        return nextMeetingDate.timeIntervalSinceNow <= 10 * 60 && nextMeetingDate > .now
    }

    func refreshIfNeeded() {
        guard Date().timeIntervalSince(lastRefresh) > 60 else { return }
        lastRefresh = .now
        Task { await refresh() }
    }

    func clear() {
        nextMeetingTitle = nil
        nextMeetingDate = nil
        lastRefresh = .distantPast
    }

    func refresh() async {
        do {
            let granted = try await store.requestAccess(to: .event)
            guard granted else { nextMeetingTitle = nil; nextMeetingDate = nil; return }
            let start = Date(); let end = start.addingTimeInterval(24 * 60 * 60)
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            let next = store.events(matching: predicate)
                .filter { !$0.isAllDay && $0.startDate > start }
                .sorted { $0.startDate < $1.startDate }
                .first
            nextMeetingTitle = next?.title
            nextMeetingDate = next?.startDate
        } catch {
            nextMeetingTitle = nil; nextMeetingDate = nil
        }
    }
}

@MainActor
final class AudioMeter: ObservableObject {
    @Published private(set) var level = 0.0
    @Published private(set) var isRunning = false
    private let engine = AVAudioEngine()

    func start() {
        guard !isRunning else { return }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor in
                guard granted, let self else { return }
                let input = self.engine.inputNode
                let format = input.outputFormat(forBus: 0)
                input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
                    guard let data = buffer.floatChannelData else { return }
                    let samples = UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength))
                    let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(1, samples.count)))
                    let normalized = min(1, max(0, (Double(rms) + 0.01) * 12))
                    Task { @MainActor in self?.level = normalized }
                }
                do { try self.engine.start(); self.isRunning = true } catch { input.removeTap(onBus: 0) }
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop(); isRunning = false; level = 0
    }
}
