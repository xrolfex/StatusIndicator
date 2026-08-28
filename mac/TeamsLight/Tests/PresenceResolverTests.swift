import XCTest
import AppKit
@testable import TeamsLight

final class PresenceResolverTests: XCTestCase {
    let resolver = PresenceResolver()
    func signal(_ state: PresenceState) -> PresenceSignal { .init(provider: state.rawValue, state: state, detail: "test") }
    func testPresentingWins() { XCTAssertEqual(resolver.resolve([signal(.available), signal(.inCall), signal(.presenting)]), .presenting) }
    func testCallWinsOverBusyAndAway() { XCTAssertEqual(resolver.resolve([signal(.busy), signal(.away), signal(.inCall)]), .inCall) }
    func testEachStateResolvesWhenItIsTheOnlySignal() {
        for state in PresenceState.allCases {
            XCTAssertEqual(resolver.resolve([signal(state)]), state, "Expected \(state) to resolve itself")
        }
    }
    func testResolutionOrderIsIndependentOfSignalOrder() {
        let signals = [signal(.unknown), signal(.offline), signal(.available), signal(.away), signal(.busy), signal(.dnd), signal(.inMeeting), signal(.inCall), signal(.presenting)]
        XCTAssertEqual(resolver.resolve(signals), .presenting)
        XCTAssertEqual(resolver.resolve(Array(signals.reversed())), .presenting)
    }
    func testUnknownWhenNoSignals() { XCTAssertEqual(resolver.resolve([]), .unknown) }
    func testUSBCommandWireValuesAndBrightnessBounds() {
        XCTAssertEqual(USBCommand.presence(.dnd).wireValue, "DND")
        XCTAssertEqual(USBCommand.brightness(99).wireValue, "BRIGHTNESS 15")
        XCTAssertEqual(USBCommand.brightness(-1).wireValue, "BRIGHTNESS 0")
        XCTAssertEqual(USBCommand.brightness(12).wireValue, "BRIGHTNESS 12")
        XCTAssertEqual(USBCommand.color(1, 2, 3).wireValue, "COLOR 1 2 3")
        XCTAssertEqual(
            USBCommand.pixel(
                MatrixCoordinate(row: 2, column: 5),
                LEDColor(red: 1, green: 2, blue: 3)
            ).wireValue,
            "PIXEL 2 5 1 2 3"
        )
        XCTAssertEqual(USBCommand.ping.wireValue, "PING")
        XCTAssertEqual(USBCommand.status.wireValue, "STATUS")
        XCTAssertEqual(USBCommand.info.wireValue, "INFO")
        XCTAssertEqual(USBCommand.fiveThree.wireValue, "FIVE_THREE")
        XCTAssertEqual(USBCommand.off.wireValue, "OFF")
    }
    func testUSBResponsesClassifyAcknowledgementsAndErrors() {
        XCTAssertEqual(USBResponse(line: "PONG\n"), .pong)
        XCTAssertEqual(USBResponse(line: "OK INFO TEAMSLIGHT_PROTOCOL 1 MATRIX_8X8"), .ok("OK INFO TEAMSLIGHT_PROTOCOL 1 MATRIX_8X8"))
        XCTAssertEqual(USBResponse(line: "ERR BRIGHTNESS_RANGE"), .error("ERR BRIGHTNESS_RANGE"))
        XCTAssertEqual(USBResponse(line: "unexpected"), .unknown("unexpected"))
    }
    func testAutomaticPresencePolicyUsesTeamsAttributionByDefault() {
        XCTAssertEqual(LocalPresencePolicy(), LocalPresencePolicy(
            useMicrophone: true,
            useCamera: true,
            useIdleTime: true,
            requireTeamsForCallActivity: true
        ))
        var policy = LocalPresencePolicy()
        XCTAssertEqual(policy.attributedActivityState(isActive: true, teamsRunning: false, state: .busy), .unknown)
        XCTAssertEqual(policy.attributedActivityState(isActive: true, teamsRunning: true, state: .inCall), .inCall)
        policy.requireTeamsForCallActivity = false
        XCTAssertFalse(policy.requireTeamsForCallActivity)
        XCTAssertEqual(policy.attributedActivityState(isActive: true, teamsRunning: false, state: .busy), .busy)
    }
    func testAutomaticTransitionsAreDebouncedButCanBeDisabled() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var filter = PresenceTransitionFilter(initial: .available, delay: 10)
        XCTAssertEqual(filter.resolve(.busy, now: start), .available)
        XCTAssertEqual(filter.resolve(.available, now: start.addingTimeInterval(5)), .available)
        XCTAssertEqual(filter.resolve(.busy, now: start.addingTimeInterval(6)), .available)
        XCTAssertEqual(filter.resolve(.busy, now: start.addingTimeInterval(15)), .available)
        XCTAssertEqual(filter.resolve(.busy, now: start.addingTimeInterval(16)), .busy)

        filter.delay = 0
        XCTAssertEqual(filter.resolve(.away, now: start.addingTimeInterval(17)), .away)
    }
    func testBriefTeamsMicrophoneActivityBecomesNotificationWithoutCallState() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let teams = signal(.available)
        let microphone = PresenceSignal(
            provider: LocalPresenceSampler.teamsMicrophoneProvider,
            state: .inCall,
            detail: "inferred from active input"
        )
        var classifier = NotificationAudioClassifier()

        let started = classifier.classify([teams, microphone], now: start)
        XCTAssertEqual(started.presenceSignals, [teams])
        XCTAssertFalse(started.detectedNotification)

        let ended = classifier.classify([teams], now: start.addingTimeInterval(1.2))
        XCTAssertEqual(ended.presenceSignals, [teams])
        XCTAssertTrue(ended.detectedNotification)
    }
    func testSustainedTeamsMicrophoneActivityBecomesCallWithoutNotification() {
        let start = Date(timeIntervalSinceReferenceDate: 2_000)
        let teams = signal(.available)
        let microphone = PresenceSignal(
            provider: LocalPresenceSampler.teamsMicrophoneProvider,
            state: .inCall,
            detail: "inferred from active input"
        )
        var classifier = NotificationAudioClassifier()

        XCTAssertEqual(classifier.classify([teams, microphone], now: start).presenceSignals, [teams])
        let confirmed = classifier.classify(
            [teams, microphone],
            now: start.addingTimeInterval(NotificationAudioClassifier.maximumNotificationDuration)
        )
        XCTAssertEqual(confirmed.presenceSignals, [teams, microphone])
        XCTAssertFalse(confirmed.detectedNotification)
        XCTAssertFalse(classifier.classify([teams], now: start.addingTimeInterval(3)).detectedNotification)
    }
    func testProcessAudioSeparatesMicrophoneCaptureFromMusicAndNotificationSounds() {
        let summary = AudioProcessActivitySummary(activities: [
            AudioProcessActivity(
                bundleIdentifier: "com.apple.Music",
                isRunningInput: false,
                isRunningOutput: true
            ),
            AudioProcessActivity(
                bundleIdentifier: "systemsoundserverd",
                isRunningInput: false,
                isRunningOutput: true
            ),
            AudioProcessActivity(
                bundleIdentifier: "com.microsoft.teams2.helper",
                isRunningInput: true,
                isRunningOutput: false
            )
        ])

        XCTAssertTrue(summary.teamsInputActive)
        XCTAssertTrue(summary.anyInputActive)
        XCTAssertTrue(summary.notificationOutputActive)
        XCTAssertTrue(TeamsProcessPresenceProvider.matches(bundleIdentifier: "com.microsoft.teams"))
        XCTAssertTrue(TeamsProcessPresenceProvider.matches(bundleIdentifier: "com.microsoft.teams2.helper"))
        XCTAssertFalse(TeamsProcessPresenceProvider.matches(bundleIdentifier: "com.apple.Music"))
    }
    func testBriefProcessAttributedNotificationAudioDoesNotFilterPresence() {
        let start = Date(timeIntervalSinceReferenceDate: 3_000)
        let available = signal(.available)
        let active = PresenceSignal(
            provider: LocalPresenceSampler.notificationAudioProvider,
            state: .unknown,
            detail: LocalPresenceSampler.notificationAudioActiveDetail
        )
        let inactive = PresenceSignal(
            provider: LocalPresenceSampler.notificationAudioProvider,
            state: .unknown,
            detail: LocalPresenceSampler.notificationAudioInactiveDetail
        )
        var classifier = NotificationAudioClassifier()

        let started = classifier.classify([available, active], now: start)
        XCTAssertEqual(started.presenceSignals, [available, active])
        XCTAssertFalse(started.detectedNotification)

        let ended = classifier.classify([available, inactive], now: start.addingTimeInterval(1.2))
        XCTAssertEqual(ended.presenceSignals, [available, inactive])
        XCTAssertTrue(ended.detectedNotification)
    }
    func testInactiveDisplayBehaviorMapsToExpectedPresence() {
        XCTAssertNil(InactiveDisplayBehavior.retain.presenceState)
        XCTAssertEqual(InactiveDisplayBehavior.away.presenceState, .away)
        XCTAssertEqual(InactiveDisplayBehavior.off.presenceState, .offline)
    }
    @MainActor
    func testMatrixPresetsRestoreFramesAndPersistOnlyPersonalPresets() {
        let preset = MatrixPreset.builtIns.first { $0.name == "Checkmark" }
        XCTAssertNotNil(preset)
        XCTAssertEqual(preset?.matrix.hexPayload.count, 384)

        let suiteName = "TeamsLightTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let matrix = LEDMatrix(fill: LEDColor(red: 1, green: 2, blue: 3))
        let store = MatrixPresetStore(defaults: defaults)
        store.save(name: " Desk focus ", matrix: matrix)
        XCTAssertEqual(store.customPresets.map(\.name), ["Desk focus"])
        XCTAssertEqual(store.customPresets.first?.matrix, matrix)
        let restoredStore = MatrixPresetStore(defaults: defaults)
        XCTAssertEqual(restoredStore.customPresets, store.customPresets)
    }
    func testImageConverterCreatesAnEightByEightRGBMatrix() {
        let context = CGContext(
            data: nil, width: 16, height: 8, bitsPerComponent: 8, bytesPerRow: 16 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )!
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 8))
        let image = NSImage(cgImage: context.makeImage()!, size: NSSize(width: 16, height: 8))
        let matrix = MatrixImageConverter.matrix(from: image, scaling: .fit)
        XCTAssertEqual(matrix?.pixels.count, 64)
        XCTAssertTrue(matrix?.pixels.contains { $0.red > 0 || $0.green > 0 || $0.blue > 0 } == true)
    }
    func testLEDMatrixUsesLogicalRowMajorRGBPayload() {
        var matrix = LEDMatrix()
        matrix[MatrixCoordinate(row: 0, column: 0)] = LEDColor(red: 255, green: 0, blue: 128)
        matrix[MatrixCoordinate(row: 7, column: 7)] = LEDColor(red: 1, green: 2, blue: 3)

        XCTAssertEqual(matrix.pixels.count, 64)
        XCTAssertEqual(matrix.hexPayload.count, 384)
        XCTAssertTrue(matrix.hexPayload.hasPrefix("FF0080"))
        XCTAssertTrue(matrix.hexPayload.hasSuffix("010203"))
        XCTAssertEqual(USBCommand.matrix(matrix).wireValue.count, 391)

        matrix.fill(with: .black)
        XCTAssertEqual(Set(matrix.pixels), [.black])
        XCTAssertEqual(LEDMatrix(hexPayload: "FF0080" + String(repeating: "000000", count: 62) + "010203")?[MatrixCoordinate(row: 0, column: 0)], LEDColor(red: 255, green: 0, blue: 128))
        XCTAssertNil(LEDMatrix(hexPayload: "000000"))
    }
    func testLEDMatrixRectangularSelectionUpdatesEverySelectedPixel() {
        let start = MatrixCoordinate(row: 1, column: 2)
        let end = MatrixCoordinate(row: 3, column: 4)
        let selection = MatrixCoordinate.rectangle(from: start, to: end)
        let color = LEDColor(red: 10, green: 20, blue: 30)
        var matrix = LEDMatrix()

        matrix.setColor(color, at: selection)

        XCTAssertEqual(selection.count, 9)
        XCTAssertTrue(selection.contains(start))
        XCTAssertTrue(selection.contains(end))
        XCTAssertEqual(matrix[MatrixCoordinate(row: 2, column: 3)], color)
        XCTAssertEqual(matrix[MatrixCoordinate(row: 0, column: 0)], .black)
        XCTAssertEqual(LEDMatrix.coordinates.count, LEDMatrix.count)
    }
    func testMatrixGeometryAndSavedArtworkResampleDynamically() {
        let geometry = MatrixGeometry(width: 16, height: 8)
        XCTAssertEqual(MatrixCapabilities.parse("OK INFO TEAMSLIGHT_PROTOCOL 2 MATRIX WIDTH 16 HEIGHT 8 PIXELS 128")?.geometry, geometry)
        XCTAssertNil(MatrixCapabilities.parse("OK INFO MATRIX WIDTH 16 HEIGHT 8 PIXELS 64"))
        var source = LEDMatrix(fill: .black)
        source[MatrixCoordinate(row: 0, column: 0)] = LEDColor(red: 1, green: 2, blue: 3)
        let resized = source.resampled(to: geometry)
        XCTAssertEqual(resized.geometry, geometry)
        XCTAssertEqual(resized.pixels.count, 128)
        XCTAssertEqual(resized[MatrixCoordinate(row: 0, column: 0)], LEDColor(red: 1, green: 2, blue: 3))
        var fill = LEDMatrix(geometry: geometry)
        fill.fill(with: LEDColor(red: 10, green: 20, blue: 30))
        XCTAssertEqual(fill.pixels.count, 128)
    }
    func testMatrixCapabilitiesRejectInvalidGeometryAndDefaultOptionalFields() {
        XCTAssertEqual(
            MatrixCapabilities.parse("OK INFO TEAMSLIGHT_PROTOCOL 4 MATRIX WIDTH 8 HEIGHT 8 PIXELS 64"),
            MatrixCapabilities(geometry: .legacy, rotation: 0, serpentine: false)
        )
        XCTAssertNil(MatrixCapabilities.parse("OK INFO MATRIX WIDTH 0 HEIGHT 8 PIXELS 0"))
        XCTAssertNil(MatrixCapabilities.parse("OK INFO MATRIX WIDTH 8 HEIGHT 8 PIXELS 63"))
        XCTAssertNil(MatrixCapabilities.parse("OK INFO MATRIX WIDTH eight HEIGHT 8 PIXELS 64"))
    }
    func testFirmwareHealthParsingRequiresEveryValue() {
        XCTAssertEqual(
            FirmwareHealth.parse("OK INFO UPTIME 120 HEAP 204800 RESET 3"),
            FirmwareHealth(uptimeSeconds: 120, freeHeapBytes: 204800, resetReason: 3)
        )
        XCTAssertNil(FirmwareHealth.parse("OK INFO UPTIME 120 HEAP 204800"))
        XCTAssertNil(FirmwareHealth.parse("OK INFO UPTIME none HEAP 204800 RESET 3"))
    }
    @MainActor
    func testPresetImportIgnoresInvalidBuiltInAndDuplicateArtwork() throws {
        let suiteName = "TeamsLightTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = MatrixPresetStore(defaults: defaults)
        let matrix = LEDMatrix(fill: LEDColor(red: 1, green: 2, blue: 3))
        store.save(name: "Original", matrix: matrix)
        let imported = [
            MatrixPreset(name: "Duplicate", matrix: matrix),
            MatrixPreset(name: "Allowed", matrix: LEDMatrix(fill: LEDColor(red: 3, green: 2, blue: 1))),
            MatrixPreset(name: "Pretend built-in", matrix: matrix, isBuiltIn: true)
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TeamsLightTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONEncoder().encode(imported).write(to: url)
        XCTAssertEqual(store.importPresets(from: url), 1)
        XCTAssertEqual(store.customPresets.map(\.name), ["Original", "Allowed"])
    }
    func testScenesProduceFramesForEveryAnimation() {
        let geometry = MatrixGeometry(width: 10, height: 5)
        for animation in MatrixAnimation.allCases {
            let frame = animation.frame(geometry: geometry, color: LEDColor(red: 20, green: 100, blue: 200), progress: 0.4, text: "HI", audioLevel: 0.6)
            XCTAssertEqual(frame.geometry, geometry)
            XCTAssertEqual(frame.pixels.count, geometry.pixelCount)
        }
    }
    func testNotificationFlashAlternatesBetweenWhiteAndOff() {
        let geometry = MatrixGeometry(width: 3, height: 2)
        let lit = MatrixAnimation.blink.frame(geometry: geometry, color: .white, progress: 0.25)
        let off = MatrixAnimation.blink.frame(geometry: geometry, color: .white, progress: 0.75)

        XCTAssertEqual(DisplayScene.notificationFlash.animation, .blink)
        XCTAssertEqual(DisplayScene.notificationFlash.color, .white)
        XCTAssertEqual(Set(lit.pixels), [.white])
        XCTAssertEqual(Set(off.pixels), [.black])
    }
    func testScrollingSceneAdvancesInsteadOfRestartingEveryFrame() {
        let scene = DisplayScene(name: "Message", animation: .scrollText, color: LEDColor(red: 255, green: 255, blue: 255), text: "HELLO", framesPerSecond: 8)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let first = scene.frame(geometry: .legacy, now: start)
        let later = scene.frame(geometry: .legacy, now: start.addingTimeInterval(1))
        XCTAssertNotEqual(first, later)
    }
    func testScrollingTextRendersStraightAndCurlyApostrophes() {
        let color = LEDColor(red: 255, green: 255, blue: 255)
        let straight = MatrixAnimation.scrollText.frame(geometry: .legacy, color: color, progress: 0.45, text: "N'")
        let curly = MatrixAnimation.scrollText.frame(geometry: .legacy, color: color, progress: 0.45, text: "N’")

        // At this phase the message starts in the first display column. The
        // apostrophe follows the five-column N, with its upper-right pixel at
        // row 1, column 7 on an 8×8 panel.
        XCTAssertEqual(straight[MatrixCoordinate(row: 1, column: 7)], color)
        XCTAssertEqual(curly, straight)
    }
    func testScrollingTextSupportsEveryEnglishKeyboardCharacter() throws {
        let unshifted = "`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./ "
        let shifted = "~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?"
        let keyboardCharacters = unshifted + shifted

        XCTAssertEqual(Set(keyboardCharacters).count, 95)
        for character in keyboardCharacters {
            let glyph = try XCTUnwrap(PixelText.glyph(for: character), "Missing glyph for \(character)")
            XCTAssertEqual(glyph.count, 5, "Invalid glyph height for \(character)")
            XCTAssertEqual(Set(glyph.map(\.count)).count, 1, "Inconsistent glyph width for \(character)")
            XCTAssertTrue(glyph.joined().allSatisfy { $0 == "0" || $0 == "1" }, "Invalid pixels for \(character)")
            if character != " " {
                XCTAssertTrue(glyph.joined().contains("1"), "Blank glyph for \(character)")
            }
        }
        XCTAssertNotEqual(PixelText.glyph(for: "`"), PixelText.glyph(for: "'"))
    }
    func testSceneOptionsRemainCompatibleWithOlderSavedOptions() throws {
        let legacy = """
        {"framesPerSecond":8,"color":{"red":1,"green":2,"blue":3},"text":"HELLO","intensity":75}
        """.data(using: .utf8)!
        let options = try JSONDecoder().decode(SceneOptions.self, from: legacy)
        XCTAssertEqual(options.direction, 1)
        XCTAssertEqual(options.trailLength, 1)
        XCTAssertEqual(options.sparkleDensity, 20)
        XCTAssertEqual(options.pulseMinimum, 15)
        XCTAssertEqual(options.countdownDuration, 5)
        XCTAssertEqual(ScenePriority.notificationsFirst.title, "Notifications First")
    }
    func testPresencePresentationAndSignalEquality() {
        XCTAssertEqual(PresenceState.inMeeting.title, "In Meeting")
        XCTAssertEqual(PresenceState.dnd.title, "Do Not Disturb")
        XCTAssertEqual(PresenceState.dnd.menuBarSystemImage, "hand.raised.fill")
        XCTAssertEqual(signal(.busy), signal(.busy))
        XCTAssertNotEqual(signal(.busy), signal(.away))
    }
    func testKuandoBusylightMatchingAndColorReports() {
        XCTAssertTrue(KuandoBusylightCommand.matches(vendorID: 0x04D8, productID: 0xF848))
        XCTAssertTrue(KuandoBusylightCommand.matches(vendorID: 0x27BB, productID: 0x3BCA))
        XCTAssertTrue(KuandoBusylightCommand.matches(vendorID: 0x27BB, productID: 0x3BCF))
        XCTAssertFalse(KuandoBusylightCommand.matches(vendorID: 0x27BB, productID: 0x1234))
        let available = KuandoBusylightCommand.colorReport(for: .available)
        XCTAssertEqual(available.count, 65) // report ID plus 64-byte HID payload
        XCTAssertEqual(Array(available.prefix(9)), [0, 0x10, 0, 0, 255, 0, 1, 0, 128])
        XCTAssertEqual(Array(available[58...62]), [0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        XCTAssertEqual(Array(available.suffix(2)), [0x06, 0x8B])
        XCTAssertEqual(Array(KuandoBusylightCommand.colorReport(for: .presenting).prefix(9)), [0, 0x10, 0, 170, 0, 255, 1, 0, 128])
        XCTAssertEqual(Array(KuandoBusylightCommand.colorReport(for: .dnd).prefix(9)), [0, 0x10, 0, 255, 0, 255, 1, 0, 128])
        XCTAssertEqual(Array(KuandoBusylightCommand.colorReport(for: .offline).prefix(9)), [0, 0x10, 0, 0, 0, 0, 1, 0, 128])
        let halfBrightness = KuandoBusylightCommand.scaled(red: 255, green: 100, blue: 1, brightnessPercent: 50)
        XCTAssertEqual([halfBrightness.0, halfBrightness.1, halfBrightness.2], [128, 50, 1])
        let zeroBrightness = KuandoBusylightCommand.scaled(red: 255, green: 255, blue: 255, brightnessPercent: -1)
        XCTAssertEqual([zeroBrightness.0, zeroBrightness.1, zeroBrightness.2], [0, 0, 0])
    }
    func testUnavailableTransportIsRepresentedByNoDevice() {
        let transport = USBSerialTransport()
        XCTAssertFalse(transport.isConnected)
        XCTAssertNil(transport.deviceName)
    }
    func testUSBSerialCandidateNamesCoverNativeAndBridgeDevices() {
        XCTAssertTrue(USBSerialTransport.isCandidateDeviceName("cu.usbmodem2101"))
        XCTAssertTrue(USBSerialTransport.isCandidateDeviceName("cu.usbserial-0001"))
        XCTAssertTrue(USBSerialTransport.isCandidateDeviceName("cu.SLAB_USBtoUART"))
        XCTAssertTrue(USBSerialTransport.isCandidateDeviceName("cu.wchusbserial1420"))
        XCTAssertFalse(USBSerialTransport.isCandidateDeviceName("tty.usbserial-0001"))
        XCTAssertFalse(USBSerialTransport.isCandidateDeviceName("cu.Bluetooth-Incoming-Port"))
    }
}
