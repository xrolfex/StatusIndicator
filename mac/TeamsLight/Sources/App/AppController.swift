import ServiceManagement
import SwiftUI
import os
import AVFoundation
import EventKit

@MainActor
final class AppController: ObservableObject {
    private enum DefaultsKey {
        static let output = "outputDestination"
        static let brightness = "brightnessPercent"
        static let override = "presenceOverride"
        static let customRed = "customColor.red"
        static let customGreen = "customColor.green"
        static let customBlue = "customColor.blue"
        static let matrix = "matrix.hexPayload"
        static let microphone = "presencePolicy.microphone"
        static let camera = "presencePolicy.camera"
        static let idle = "presencePolicy.idle"
        static let requireTeams = "presencePolicy.requireTeams"
        static let transitionDelay = "presenceTransitionDelay"
        static let inactiveBehavior = "inactiveDisplayBehavior"
        static let overrideTimeout = "manualOverrideTimeout"
        static let esp32Path = "selectedESP32Path"
        static let busylightID = "selectedBusylightID"
        static let appearanceProfiles = "stateAppearanceProfiles"
        static let customScenes = "deskDisplay.customScenes"
        static let sceneRules = "deskDisplay.sceneRules"
        static let sceneOptions = "deskDisplay.sceneOptions"
        static let sceneSafety = "deskDisplay.sceneSafety"
        static let scenePriority = "deskDisplay.scenePriority"
        static let audioReactive = "deskDisplay.audioReactive"
        static let calendarIntegration = "deskDisplay.calendarIntegration"
        static let notificationFlashes = "deskDisplay.notificationFlashes"
    }
    private let defaults = UserDefaults.standard
    @Published var state: PresenceState = .unknown
    @Published var signals: [PresenceSignal] = []
    @Published var connected = false
    @Published var deviceName: String?
    @Published var busylightDeviceName: String?
    @Published var outputDestination: OutputDestination = .both { didSet { defaults.set(outputDestination.rawValue, forKey: DefaultsKey.output); tick() } }
    // Level 1 is the lowest visible ESP32 matrix brightness (level 0 turns it off).
    private static let lowestVisibleBrightnessPercent = 100.0 / 15.0
    @Published private(set) var isFiveThirdMode = false
    @Published var brightnessPercent = 100.0 { didSet { defaults.set(brightnessPercent, forKey: DefaultsKey.brightness) } }
    @Published var override: PresenceState? {
        didSet {
            if let override { defaults.set(override.rawValue, forKey: DefaultsKey.override) }
            else { defaults.removeObject(forKey: DefaultsKey.override) }
        }
    }
    @Published var customColor = Color.purple
    @Published var isCustomColorOverride = false
    @Published private(set) var matrix = LEDMatrix()
    @Published private(set) var canUndoMatrix = false
    @Published private(set) var isMatrixOverride = false
    @Published var startAtLogin = false { didSet { setLoginItem() } }
    @Published var presencePolicy = LocalPresencePolicy() { didSet { persistPresencePolicy(); tick() } }
    @Published var automaticTransitionDelay = 10.0 {
        didSet {
            let normalized: Double = automaticTransitionDelay == 30 ? 30 : automaticTransitionDelay == 0 ? 0 : 10
            if automaticTransitionDelay != normalized {
                automaticTransitionDelay = normalized
                return
            }
            transitionFilter.delay = automaticTransitionDelay
            defaults.set(automaticTransitionDelay, forKey: DefaultsKey.transitionDelay)
        }
    }
    @Published var inactiveDisplayBehavior: InactiveDisplayBehavior = .away {
        didSet { defaults.set(inactiveDisplayBehavior.rawValue, forKey: DefaultsKey.inactiveBehavior); setInactiveDisplay(isInactiveDisplay) }
    }
    @Published var manualOverrideTimeout = 0.0 { didSet { defaults.set(manualOverrideTimeout, forKey: DefaultsKey.overrideTimeout) } }
    @Published var selectedESP32Path = "" { didSet { defaults.set(selectedESP32Path, forKey: DefaultsKey.esp32Path); tick() } }
    @Published var selectedBusylightID = "" { didSet { defaults.set(selectedBusylightID, forKey: DefaultsKey.busylightID); tick() } }
    @Published private(set) var availableESP32Paths: [String] = []
    @Published private(set) var availableBusylights: [BusylightDeviceDescriptor] = []
    @Published private(set) var appearanceProfiles: [String: StateAppearanceProfile] = [:]
    @Published private(set) var calibrationRotation = 0
    @Published private(set) var calibrationSerpentine = false
    @Published private(set) var customScenes: [DisplayScene] = []
    @Published private(set) var sceneOptions: [UUID: SceneOptions] = [:]
    @Published private(set) var activeScene: DisplayScene?
    @Published private(set) var notifications: [DeskNotification] = []
    @Published private(set) var displayOwner = "Presence"
    @Published var sceneSafetyLimits = SceneSafetyLimits() { didSet { persistSceneSafetyLimits(); tick() } }
    @Published var scenePriority: ScenePriority = .notificationsFirst { didSet { defaults.set(scenePriority.rawValue, forKey: DefaultsKey.scenePriority); tick() } }
    @Published var sceneRules: [SceneRule] = [] { didSet { persistSceneRules(); tick() } }
    @Published var audioReactiveEnabled = false { didSet { defaults.set(audioReactiveEnabled, forKey: DefaultsKey.audioReactive); audioReactiveEnabled ? audioMeter.start() : audioMeter.stop() } }
    @Published var calendarIntegrationEnabled = false { didSet { defaults.set(calendarIntegrationEnabled, forKey: DefaultsKey.calendarIntegration); if calendarIntegrationEnabled { calendarMonitor.refreshIfNeeded() } else { calendarMonitor.clear() }; tick() } }
    @Published var notificationFlashesEnabled = true { didSet { defaults.set(notificationFlashesEnabled, forKey: DefaultsKey.notificationFlashes); tick() } }
    let transport = USBSerialTransport()
    private let busylight = KuandoBusylightTransport()
    private let sampler = LocalPresenceSampler(); private let resolver = PresenceResolver()
    private let calendarMonitor = CalendarMonitor()
    private let audioMeter = AudioMeter()
    private var transitionFilter = PresenceTransitionFilter()
    private var notificationAudioClassifier = NotificationAudioClassifier()
    private var isInactiveDisplay = false
    private var overrideExpiryTask: Task<Void, Never>?
    private var matrixUndoStack: [LEDMatrix] = []
    private var timer: Timer?
    private var lastSentESP32Command: String?
    private var lastSentESP32Brightness: Int?
    private var screenMatrix = LEDMatrix()
    private var lastScreenCapture = Date.distantPast
    init() {
        if let rawValue = defaults.string(forKey: DefaultsKey.output), let destination = OutputDestination(rawValue: rawValue) {
            outputDestination = destination
        }
        if let brightness = defaults.object(forKey: DefaultsKey.brightness) as? Double {
            brightnessPercent = min(100, max(0, brightness))
        }
        if let rawValue = defaults.string(forKey: DefaultsKey.override) {
            override = PresenceState(rawValue: rawValue)
        }
        let red = defaults.object(forKey: DefaultsKey.customRed) as? Double ?? 0.5
        let green = defaults.object(forKey: DefaultsKey.customGreen) as? Double ?? 0
        let blue = defaults.object(forKey: DefaultsKey.customBlue) as? Double ?? 0.5
        customColor = Color(red: red, green: green, blue: blue)
        if let payload = defaults.string(forKey: DefaultsKey.matrix), let restoredMatrix = LEDMatrix(hexPayload: payload) {
            matrix = restoredMatrix
        }
        presencePolicy = LocalPresencePolicy(
            useMicrophone: defaults.object(forKey: DefaultsKey.microphone) as? Bool ?? true,
            useCamera: defaults.object(forKey: DefaultsKey.camera) as? Bool ?? true,
            useIdleTime: defaults.object(forKey: DefaultsKey.idle) as? Bool ?? true,
            requireTeamsForCallActivity: defaults.object(forKey: DefaultsKey.requireTeams) as? Bool ?? true
        )
        if let delay = defaults.object(forKey: DefaultsKey.transitionDelay) as? Double, [0.0, 10.0, 30.0].contains(delay) {
            automaticTransitionDelay = delay
        }
        if let rawValue = defaults.string(forKey: DefaultsKey.inactiveBehavior), let behavior = InactiveDisplayBehavior(rawValue: rawValue) {
            inactiveDisplayBehavior = behavior
        }
        if let timeout = defaults.object(forKey: DefaultsKey.overrideTimeout) as? Double, [0.0, 900.0, 1800.0, 3600.0].contains(timeout) {
            manualOverrideTimeout = timeout
        }
        selectedESP32Path = defaults.string(forKey: DefaultsKey.esp32Path) ?? ""
        selectedBusylightID = defaults.string(forKey: DefaultsKey.busylightID) ?? ""
        if let data = defaults.data(forKey: DefaultsKey.appearanceProfiles), let restored = try? JSONDecoder().decode([String: StateAppearanceProfile].self, from: data) {
            appearanceProfiles = restored
        }
        if let data = defaults.data(forKey: DefaultsKey.customScenes), let restored = try? JSONDecoder().decode([DisplayScene].self, from: data) { customScenes = restored }
        if let data = defaults.data(forKey: DefaultsKey.sceneRules), let restored = try? JSONDecoder().decode([SceneRule].self, from: data) { sceneRules = restored }
        if let data = defaults.data(forKey: DefaultsKey.sceneOptions), let restored = try? JSONDecoder().decode([UUID: SceneOptions].self, from: data) { sceneOptions = restored }
        if let data = defaults.data(forKey: DefaultsKey.sceneSafety), let restored = try? JSONDecoder().decode(SceneSafetyLimits.self, from: data) { sceneSafetyLimits = restored }
        if let raw = defaults.string(forKey: DefaultsKey.scenePriority), let restored = ScenePriority(rawValue: raw) { scenePriority = restored }
        audioReactiveEnabled = defaults.object(forKey: DefaultsKey.audioReactive) as? Bool ?? false
        calendarIntegrationEnabled = defaults.object(forKey: DefaultsKey.calendarIntegration) as? Bool ?? false
        notificationFlashesEnabled = defaults.object(forKey: DefaultsKey.notificationFlashes) as? Bool ?? true
        transitionFilter.delay = automaticTransitionDelay
        startAtLogin = SMAppService.mainApp.status == .enabled
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        NotificationCenter.default.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.setInactiveDisplay(true) } }
        NotificationCenter.default.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.setInactiveDisplay(false) } }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.setInactiveDisplay(true) } }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.setInactiveDisplay(false) } }
    }
    func tick() {
        availableESP32Paths = USBSerialTransport.candidatePaths()
        signals = sampler.sample(policy: presencePolicy)
        let classifiedActivity = notificationAudioClassifier.classify(signals)
        if classifiedActivity.detectedNotification, notificationFlashesEnabled {
            notifications.append(DeskNotification(
                title: "Teams notification",
                scene: .notificationFlash,
                expiresAt: .now.addingTimeInterval(3)
            ))
        }
        if calendarIntegrationEnabled { calendarMonitor.refreshIfNeeded() }
        let resolved = resolver.resolve(classifiedActivity.presenceSignals)
        let next: PresenceState
        if let override {
            transitionFilter.reset(to: override)
            next = override
        } else {
            next = transitionFilter.resolve(resolved)
        }
        let displayState = isInactiveDisplay ? inactiveDisplayBehavior.presenceState ?? next : next
        notifications.removeAll { $0.expiresAt <= .now }
        let ruleScene = sceneRules.first(where: { $0.isEnabled && $0.condition.matches(state: next, signals: signals, upcomingMeeting: calendarIntegrationEnabled && calendarMonitor.hasUpcomingMeeting) }).flatMap { rule in
            allScenes.first { $0.id == rule.sceneID }.map(configuredScene)
        }
        let notificationScene = notificationFlashesEnabled ? notifications.last?.scene : nil
        let candidates: [(scene: DisplayScene?, owner: String)] = switch scenePriority {
        case .notificationsFirst: [(notificationScene, "Notification"), (activeScene, "Manual scene"), (ruleScene, "Automation rule")]
        case .manualFirst: [(activeScene, "Manual scene"), (notificationScene, "Notification"), (ruleScene, "Automation rule")]
        case .automationFirst: [(ruleScene, "Automation rule"), (notificationScene, "Notification"), (activeScene, "Manual scene")]
        }
        let selected = candidates.first { $0.scene != nil }
        let displayedScene = selected?.scene
        displayOwner = selected?.owner ?? (isMatrixOverride ? "Matrix editor" : isCustomColorOverride ? "Custom color" : "Presence")
        let displayedSceneFrame = displayedScene.map(sceneFrame)
        let notificationFlashIsDisplayed = !isInactiveDisplay && selected?.owner == "Notification"
        let profile = appearanceProfile(for: displayState)
        let retainsInactiveDisplay = isInactiveDisplay && inactiveDisplayBehavior == .retain
        let command: USBCommand
        if isInactiveDisplay {
            command = .presence(displayState)
        } else if let displayedSceneFrame {
            command = .matrix(displayedSceneFrame)
        } else if isMatrixOverride {
            command = .matrix(matrix)
        } else if isFiveThirdMode {
            command = .fiveThree
        } else if isCustomColorOverride {
            command = customColorCommand
        } else if hasCustomAppearance(for: next) {
            command = .color(profile.esp32Color.red, profile.esp32Color.green, profile.esp32Color.blue)
        } else {
            command = .presence(next)
        }
        let destination = outputDestination
        Task {
            await transport.setPreferredDevicePath(selectedESP32Path.isEmpty ? nil : selectedESP32Path)
            await busylight.setSelectedDeviceID(selectedBusylightID.isEmpty ? nil : selectedBusylightID)
            if !retainsInactiveDisplay && destination.usesESP32 && !transport.isConnected {
                await transport.reconnect()
                lastSentESP32Command = nil
                lastSentESP32Brightness = nil
            }
            if !retainsInactiveDisplay && destination.usesBusylight && !busylight.isConnected { await busylight.reconnect() }
            if !retainsInactiveDisplay && destination.usesESP32 && transport.isConnected {
                // Ensure the special mark is rendered at its lowest visible brightness.
                let brightnessLevel: Int
                if isFiveThirdMode { brightnessLevel = 1 }
                else if notificationFlashIsDisplayed {
                    brightnessLevel = Int((brightnessPercent * 15 / 100).rounded())
                }
                else {
                    let multiplier = hasCustomAppearance(for: displayState) ? profile.esp32Brightness : 100
                    brightnessLevel = Int((brightnessPercent * multiplier * 15 / 10_000).rounded())
                }
                if lastSentESP32Brightness != brightnessLevel {
                    await transport.send(USBCommand.brightness(brightnessLevel).wireValue)
                    lastSentESP32Brightness = brightnessLevel
                }
                if lastSentESP32Command != command.wireValue {
                    await transport.send(command.wireValue)
                    lastSentESP32Command = command.wireValue
                }
            }
            if !retainsInactiveDisplay && destination.usesBusylight && busylight.isConnected {
                if isInactiveDisplay {
                    await busylight.send(displayState, brightnessPercent: brightnessPercent)
                } else if notificationFlashIsDisplayed, let flashColor = displayedSceneFrame?.pixels.first {
                    await busylight.send(
                        red: flashColor.red,
                        green: flashColor.green,
                        blue: flashColor.blue,
                        brightnessPercent: brightnessPercent
                    )
                } else if isMatrixOverride || isFiveThirdMode {
                    // Matrix-specific displays have no Busylight equivalent;
                    // keep the secondary device dark rather than showing stale presence.
                    await busylight.send(.offline, brightnessPercent: brightnessPercent)
                } else if isCustomColorOverride {
                    let color = customColorComponents
                    await busylight.send(red: color.red, green: color.green, blue: color.blue, brightnessPercent: brightnessPercent)
                } else {
                    if hasCustomAppearance(for: displayState) {
                        await busylight.send(
                            red: profile.busylightColor.red,
                            green: profile.busylightColor.green,
                            blue: profile.busylightColor.blue,
                            brightnessPercent: brightnessPercent * profile.busylightBrightness / 100
                        )
                    } else {
                        await busylight.send(displayState, brightnessPercent: brightnessPercent)
                    }
                }
            }
            connected = (destination.usesESP32 && transport.isConnected) || (destination.usesBusylight && busylight.isConnected)
            deviceName = transport.deviceName
            busylightDeviceName = busylight.deviceName
            availableBusylights = busylight.availableDevices
            if let geometry = transport.matrixCapabilities?.geometry, matrix.geometry != geometry {
                configureMatrixGeometry(geometry)
            }
            if let capabilities = transport.matrixCapabilities {
                calibrationRotation = capabilities.rotation
                calibrationSerpentine = capabilities.serpentine
            }
        }
        if next != state {
            Logger(subsystem: "com.example.TeamsLight", category: "presence").info(
                "Presence changed \(self.state.rawValue, privacy: .public) -> \(next.rawValue, privacy: .public)"
            )
            state = next
        }
    }
    func setPresenceOverride(_ state: PresenceState?) {
        isFiveThirdMode = false
        isMatrixOverride = false
        isCustomColorOverride = false
        override = state
        scheduleOverrideExpiry(for: state)
        tick()
    }
    private func scheduleOverrideExpiry(for state: PresenceState?) {
        overrideExpiryTask?.cancel()
        guard state != nil, manualOverrideTimeout > 0 else { return }
        let timeout = manualOverrideTimeout
        overrideExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.override == state else { return }
                self?.setPresenceOverride(nil)
            }
        }
    }
    private func setInactiveDisplay(_ inactive: Bool) {
        isInactiveDisplay = inactive
        tick()
    }
    func setFiveThirdMode(_ enabled: Bool) {
        isFiveThirdMode = enabled
        if enabled {
            isMatrixOverride = false
            isCustomColorOverride = false
            brightnessPercent = Self.lowestVisibleBrightnessPercent
        }
        tick()
    }
    func activateCustomColor() {
        isFiveThirdMode = false
        isMatrixOverride = false
        isCustomColorOverride = true
        tick()
    }
    func setCustomColor(_ color: Color) {
        customColor = color
        persistCustomColor()
        isFiveThirdMode = false
        isMatrixOverride = false
        isCustomColorOverride = true
        let components = customColorComponents
        Task {
            if outputDestination.usesESP32 { await transport.send(customColorCommand.wireValue) }
            if outputDestination.usesBusylight { await busylight.send(red: components.red, green: components.green, blue: components.blue, brightnessPercent: brightnessPercent) }
        }
    }
    func activateMatrixEditor() {
        isFiveThirdMode = false
        isCustomColorOverride = false
        isMatrixOverride = true
        tick()
    }
    var supportsMatrixCalibration: Bool { transport.matrixCapabilities != nil && !transport.isLegacyFirmware }
    func setMatrixCalibration(rotation: Int, serpentine: Bool) {
        guard supportsMatrixCalibration else { return }
        calibrationRotation = rotation
        calibrationSerpentine = serpentine
        Task { await transport.send(USBCommand.calibrate(rotation: rotation, serpentine: serpentine).wireValue) }
    }
    func resetMatrixCalibration() {
        Task {
            await transport.send(USBCommand.resetCalibration.wireValue)
            await transport.send(USBCommand.info.wireValue)
            if let capabilities = transport.matrixCapabilities {
                calibrationRotation = capabilities.rotation
                calibrationSerpentine = capabilities.serpentine
            }
        }
    }
    func showCalibrationTestPattern() {
        var test = LEDMatrix(geometry: matrix.geometry)
        let lastRow = matrix.geometry.height - 1; let lastColumn = matrix.geometry.width - 1
        test[MatrixCoordinate(row: 0, column: 0)] = .init(red: 255, green: 0, blue: 0)
        test[MatrixCoordinate(row: 0, column: lastColumn)] = .init(red: 0, green: 255, blue: 0)
        test[MatrixCoordinate(row: lastRow, column: 0)] = .init(red: 0, green: 0, blue: 255)
        test[MatrixCoordinate(row: lastRow, column: lastColumn)] = .init(red: 255, green: 255, blue: 255)
        applyMatrix(test)
    }
    var allScenes: [DisplayScene] { DisplayScene.builtIns + customScenes }
    func configuredScene(_ scene: DisplayScene) -> DisplayScene {
        guard let options = sceneOptions[scene.id] else { return scene }
        var adjusted = options
        adjusted.framesPerSecond = min(sceneSafetyLimits.maximumFramesPerSecond, adjusted.framesPerSecond)
        adjusted.intensity = min(sceneSafetyLimits.maximumIntensity, adjusted.intensity)
        return DisplayScene(id: scene.id, name: scene.name, animation: scene.animation, color: adjusted.color.scaled(by: adjusted.intensity / 100), text: adjusted.text, framesPerSecond: adjusted.framesPerSecond, frames: scene.frames, options: adjusted)
    }
    func options(for scene: DisplayScene) -> SceneOptions { sceneOptions[scene.id] ?? SceneOptions(scene: scene) }
    func setOptions(_ options: SceneOptions, for scene: DisplayScene) {
        sceneOptions[scene.id] = options
        persistSceneOptions()
        if activeScene?.id == scene.id { activeScene = configuredScene(scene) }
        tick()
    }
    var nextMeetingSummary: String {
        guard calendarIntegrationEnabled else { return "Calendar access is off" }
        guard let title = calendarMonitor.nextMeetingTitle, let date = calendarMonitor.nextMeetingDate else { return "No upcoming calendar event" }
        return "\(title) — \(date.formatted(date: .omitted, time: .shortened))"
    }
    func saveScene(name: String, animation: MatrixAnimation, color: LEDColor, text: String, framesPerSecond: Double) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        customScenes.append(DisplayScene(name: name, animation: animation, color: color, text: text, framesPerSecond: framesPerSecond))
        persistScenes()
    }
    func saveFrameAnimation(name: String, frames: [LEDMatrix], framesPerSecond: Double) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !frames.isEmpty else { return }
        customScenes.append(DisplayScene(name: name, animation: .solid, color: .black, framesPerSecond: framesPerSecond, frames: frames.map(\.hexPayload)))
        persistScenes()
    }
    func removeScene(_ scene: DisplayScene) {
        customScenes.removeAll { $0.id == scene.id }
        sceneRules.removeAll { $0.sceneID == scene.id }
        if activeScene?.id == scene.id { activeScene = nil }
        persistScenes()
    }
    func exportScenePack(to url: URL) throws {
        let pack = ScenePack(formatVersion: 1, scenes: customScenes, rules: sceneRules)
        try JSONEncoder().encode(pack).write(to: url, options: .atomic)
    }
    @discardableResult
    func importScenePack(from url: URL) -> Int {
        guard let data = try? Data(contentsOf: url), let pack = try? JSONDecoder().decode(ScenePack.self, from: data), pack.formatVersion == 1 else { return 0 }
        let newScenes = pack.scenes.filter { candidate in !customScenes.contains(where: { $0.name == candidate.name && $0.frames == candidate.frames && $0.animation == candidate.animation }) }
        customScenes.append(contentsOf: newScenes)
        let sceneIDs = Set(allScenes.map(\.id))
        let existingRuleIDs = Set(sceneRules.map(\.id))
        sceneRules.append(contentsOf: pack.rules.filter { sceneIDs.contains($0.sceneID) && !existingRuleIDs.contains($0.id) })
        persistScenes()
        return newScenes.count
    }
    func activateScene(_ scene: DisplayScene) {
        isFiveThirdMode = false; isCustomColorOverride = false; isMatrixOverride = false
        activeScene = configuredScene(scene); tick()
    }
    func stopScene() { activeScene = nil; tick() }
    func enqueueNotification(title: String, duration: Double = 3) {
        notifications.append(DeskNotification(title: title, scene: .notificationFlash, expiresAt: .now.addingTimeInterval(max(1, duration))))
        tick()
    }
    func previewFrame(for scene: DisplayScene, at date: Date) -> LEDMatrix {
        configuredScene(scene).frame(geometry: matrix.geometry, now: date, audioLevel: audioMeter.level)
    }
    private func sceneFrame(for scene: DisplayScene) -> LEDMatrix {
        if scene.animation == .screenAmbient {
            refreshScreenAmbientIfNeeded()
            return screenMatrix.geometry == matrix.geometry ? screenMatrix : screenMatrix.resampled(to: matrix.geometry)
        }
        return scene.frame(geometry: matrix.geometry, audioLevel: audioMeter.level)
    }
    private func refreshScreenAmbientIfNeeded() {
        guard Date().timeIntervalSince(lastScreenCapture) >= 1 else { return }
        lastScreenCapture = .now
        guard let image = CGDisplayCreateImage(CGMainDisplayID()),
              let converted = MatrixImageConverter.matrix(from: NSImage(cgImage: image, size: .zero), geometry: matrix.geometry, scaling: .fill) else { return }
        screenMatrix = converted
    }
    func applyMatrixPreset(_ preset: MatrixPreset) {
        applyMatrix(preset.matrix)
    }
    func applyImportedImageMatrix(_ importedMatrix: LEDMatrix) {
        applyMatrix(importedMatrix)
    }
    private func configureMatrixGeometry(_ geometry: MatrixGeometry) {
        matrix = LEDMatrix(hexPayload: matrix.hexPayload, geometry: geometry) ?? LEDMatrix(geometry: geometry)
        defaults.set(matrix.hexPayload, forKey: DefaultsKey.matrix)
    }
    private func applyMatrix(_ updatedMatrix: LEDMatrix) {
        pushMatrixUndo()
        matrix = updatedMatrix.resampled(to: matrix.geometry)
        defaults.set(matrix.hexPayload, forKey: DefaultsKey.matrix)
        isFiveThirdMode = false
        isCustomColorOverride = false
        isMatrixOverride = true
        tick()
    }
    func matrixColor(at coordinate: MatrixCoordinate) -> LEDColor {
        matrix[coordinate]
    }
    func setMatrixColor(_ color: Color, at coordinates: Set<MatrixCoordinate>) {
        guard !coordinates.isEmpty else {
            Logger(subsystem: "com.example.TeamsLight", category: "matrix").error("Cannot set a matrix color without selected pixels")
            return
        }
        guard let converted = NSColor(color).usingColorSpace(.deviceRGB) else {
            Logger(subsystem: "com.example.TeamsLight", category: "matrix").error("Could not convert the selected matrix color to RGB")
            return
        }
        func byte(_ component: CGFloat) -> UInt8 {
            UInt8((min(1, max(0, component)) * 255).rounded())
        }
        let ledColor = LEDColor(
            red: byte(converted.redComponent),
            green: byte(converted.greenComponent),
            blue: byte(converted.blueComponent)
        )
        var updatedMatrix = matrix
        updatedMatrix.setColor(ledColor, at: coordinates)
        pushMatrixUndo()
        let wasMatrixOverride = isMatrixOverride
        matrix = updatedMatrix
        defaults.set(updatedMatrix.hexPayload, forKey: DefaultsKey.matrix)
        isFiveThirdMode = false
        isCustomColorOverride = false
        isMatrixOverride = true
        let command: USBCommand
        if wasMatrixOverride, coordinates.count == 1, let coordinate = coordinates.first {
            command = .pixel(coordinate, ledColor)
        } else {
            command = .matrix(updatedMatrix)
        }
        Task {
            if outputDestination.usesESP32 {
                await transport.send(command.wireValue)
            }
        }
    }
    func clearMatrix() {
        pushMatrixUndo()
        matrix = LEDMatrix(geometry: matrix.geometry)
        defaults.set(matrix.hexPayload, forKey: DefaultsKey.matrix)
        activateMatrixEditor()
    }
    func undoMatrix() {
        guard let previous = matrixUndoStack.popLast() else { return }
        matrix = previous
        canUndoMatrix = !matrixUndoStack.isEmpty
        defaults.set(matrix.hexPayload, forKey: DefaultsKey.matrix)
        isFiveThirdMode = false
        isCustomColorOverride = false
        isMatrixOverride = true
        tick()
    }
    private func pushMatrixUndo() {
        matrixUndoStack.append(matrix)
        if matrixUndoStack.count > 20 { matrixUndoStack.removeFirst() }
        canUndoMatrix = true
    }
    func setBrightness() {
        let deviceLevel = Int((brightnessPercent * 15 / 100).rounded())
        Task {
            if outputDestination.usesESP32 { await transport.send(USBCommand.brightness(deviceLevel).wireValue) }
            guard outputDestination.usesBusylight else { return }
            if isCustomColorOverride {
                let color = customColorComponents
                await busylight.send(red: color.red, green: color.green, blue: color.blue, brightnessPercent: brightnessPercent)
            } else {
                await busylight.send(isInactiveDisplay ? inactiveDisplayBehavior.presenceState ?? state : state, brightnessPercent: brightnessPercent)
            }
        }
    }
    func adjustBrightness(by amount: Double) {
        brightnessPercent = min(100, max(0, brightnessPercent + amount))
        setBrightness()
    }
    func reconnectDevices() {
        Task {
            if outputDestination.usesESP32 { await transport.reconnect() }
            if outputDestination.usesBusylight { await busylight.reconnect() }
            connected = (outputDestination.usesESP32 && transport.isConnected) || (outputDestination.usesBusylight && busylight.isConnected)
            deviceName = transport.deviceName
            busylightDeviceName = busylight.deviceName
            availableBusylights = busylight.availableDevices
        }
    }
    func setPresencePolicy(_ update: (inout LocalPresencePolicy) -> Void) {
        var updated = presencePolicy
        update(&updated)
        presencePolicy = updated
    }
    func appearanceProfile(for state: PresenceState) -> StateAppearanceProfile {
        appearanceProfiles[state.rawValue] ?? StateAppearanceProfiles.default(for: state)
    }
    func setAppearanceProfile(_ profile: StateAppearanceProfile, for state: PresenceState) {
        appearanceProfiles[state.rawValue] = profile
        persistAppearanceProfiles()
        tick()
    }
    func resetAppearanceProfile(for state: PresenceState) {
        appearanceProfiles.removeValue(forKey: state.rawValue)
        persistAppearanceProfiles()
        tick()
    }
    private func hasCustomAppearance(for state: PresenceState) -> Bool { appearanceProfiles[state.rawValue] != nil }
    private func setLoginItem() {
        do {
            if startAtLogin {
                try SMAppService.mainApp.register() } else {
                    try SMAppService.mainApp.unregister()
                }
        } catch { Logger(subsystem: "com.example.TeamsLight", category: "app").error("Login item update failed") } }
    private func persistCustomColor() {
        let color = customColorComponents
        defaults.set(Double(color.red) / 255, forKey: DefaultsKey.customRed)
        defaults.set(Double(color.green) / 255, forKey: DefaultsKey.customGreen)
        defaults.set(Double(color.blue) / 255, forKey: DefaultsKey.customBlue)
    }
    private func persistPresencePolicy() {
        defaults.set(presencePolicy.useMicrophone, forKey: DefaultsKey.microphone)
        defaults.set(presencePolicy.useCamera, forKey: DefaultsKey.camera)
        defaults.set(presencePolicy.useIdleTime, forKey: DefaultsKey.idle)
        defaults.set(presencePolicy.requireTeamsForCallActivity, forKey: DefaultsKey.requireTeams)
    }
    private func persistAppearanceProfiles() {
        guard let data = try? JSONEncoder().encode(appearanceProfiles) else { return }
        defaults.set(data, forKey: DefaultsKey.appearanceProfiles)
    }
    private func persistScenes() {
        guard let data = try? JSONEncoder().encode(customScenes) else { return }
        defaults.set(data, forKey: DefaultsKey.customScenes)
    }
    private func persistSceneRules() {
        guard let data = try? JSONEncoder().encode(sceneRules) else { return }
        defaults.set(data, forKey: DefaultsKey.sceneRules)
    }
    private func persistSceneOptions() {
        guard let data = try? JSONEncoder().encode(sceneOptions) else { return }
        defaults.set(data, forKey: DefaultsKey.sceneOptions)
    }
    private func persistSceneSafetyLimits() {
        guard let data = try? JSONEncoder().encode(sceneSafetyLimits) else { return }
        defaults.set(data, forKey: DefaultsKey.sceneSafety)
    }
    func exportBackup(to url: URL) throws {
        let backup = TeamsLightBackup(formatVersion: 1, brightness: brightnessPercent, matrixPayload: matrix.hexPayload, scenes: customScenes, rules: sceneRules, sceneOptions: sceneOptions, appearanceProfiles: appearanceProfiles, presencePolicy: presencePolicy, safetyLimits: sceneSafetyLimits, scenePriority: scenePriority, matrixPresets: MatrixPresetStore.backupData(), calibrationRotation: calibrationRotation, calibrationSerpentine: calibrationSerpentine, notificationFlashesEnabled: notificationFlashesEnabled)
        try JSONEncoder().encode(backup).write(to: url, options: .atomic)
    }
    @discardableResult
    func importBackup(from url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), let backup = try? JSONDecoder().decode(TeamsLightBackup.self, from: data), backup.formatVersion == 1 else { return false }
        brightnessPercent = backup.brightness
        customScenes = backup.scenes; sceneRules = backup.rules; sceneOptions = backup.sceneOptions
        appearanceProfiles = backup.appearanceProfiles; presencePolicy = backup.presencePolicy; sceneSafetyLimits = backup.safetyLimits; scenePriority = backup.scenePriority
        if let notificationFlashesEnabled = backup.notificationFlashesEnabled { self.notificationFlashesEnabled = notificationFlashesEnabled }
        if let presets = backup.matrixPresets { MatrixPresetStore.restoreBackupData(presets) }
        setMatrixCalibration(rotation: backup.calibrationRotation, serpentine: backup.calibrationSerpentine)
        if let restored = LEDMatrix(hexPayload: backup.matrixPayload) { applyMatrix(restored) }
        persistScenes(); persistSceneRules(); persistSceneOptions(); persistAppearanceProfiles(); persistSceneSafetyLimits()
        return true
    }
    var permissionSummary: [(name: String, status: String)] {
        func media(_ status: AVAuthorizationStatus) -> String { switch status { case .authorized: "Allowed"; case .notDetermined: "Not requested"; case .denied, .restricted: "Not allowed"; @unknown default: "Unknown" } }
        let calendar: String = switch EKEventStore.authorizationStatus(for: .event) { case .fullAccess, .writeOnly: "Allowed"; case .notDetermined: "Not requested"; case .denied, .restricted: "Not allowed"; @unknown default: "Unknown" }
        return [("Microphone", media(AVCaptureDevice.authorizationStatus(for: .audio))), ("Camera", media(AVCaptureDevice.authorizationStatus(for: .video))), ("Calendar", calendarIntegrationEnabled ? calendar : "Off"), ("Screen Recording", CGPreflightScreenCaptureAccess() ? "Allowed" : "Not allowed")]
    }
    
    var displayTitle: String {
        if displayOwner == "Notification", let notification = notifications.last { return notification.title }
        if let activeScene { return activeScene.name }
        if isMatrixOverride { return "Custom Matrix" }
        if isFiveThirdMode { return "5/3 Matrix" }
        return isCustomColorOverride ? "Custom Color" : state.title
    }
    var supportsFiveThree: Bool { matrix.geometry == .legacy }
    var displayAccentColor: Color {
        if isMatrixOverride { return .cyan }
        if isFiveThirdMode { return .green }
        return isCustomColorOverride ? customColor : state.accentColor
    }
    var menuBarSystemImage: String {
        if isMatrixOverride || isFiveThirdMode { return "square.grid.3x3.fill" }
        return isCustomColorOverride ? "paintpalette.fill" : state.menuBarSystemImage
    }
    
    private var customColorCommand: USBCommand {
        let color = customColorComponents
        return .color(color.red, color.green, color.blue)
    }
    
    private var customColorComponents: (red: UInt8, green: UInt8, blue: UInt8) {
        guard let color = NSColor(customColor).usingColorSpace(.deviceRGB) else {
            return (128, 0, 128)
        }
        return (
            UInt8((color.redComponent * 255).rounded()),
            UInt8((color.greenComponent * 255).rounded()),
            UInt8((color.blueComponent * 255).rounded())
        )
    }
}

enum OutputDestination: String, CaseIterable, Identifiable {
    case esp32
    case busylight
    case both
    
    var id: Self { self }
    var title: String {
        switch self {
        case .esp32: "ESP32"
        case .busylight: "Busylight"
        case .both: "Both"
        }
    }
    var usesESP32: Bool { self != .busylight }
    var usesBusylight: Bool { self != .esp32 }
}
