import Foundation

enum MatrixAnimation: String, CaseIterable, Codable, Identifiable, Sendable {
    case solid, pulse, blink, rainbow, scanner, sparkle, equalizer, countdown, scrollText, screenAmbient

    var id: Self { self }
    var title: String { rawValue.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized }

    func frame(geometry: MatrixGeometry, color: LEDColor, progress: Double, text: String = "", audioLevel: Double = 0, options: SceneOptions? = nil) -> LEDMatrix {
        let phase = progress - floor(progress)
        var matrix = LEDMatrix(geometry: geometry)
        for row in 0..<geometry.height {
            for column in 0..<geometry.width {
                let coordinate = MatrixCoordinate(row: row, column: column)
                switch self {
                case .solid:
                    matrix[coordinate] = color
                case .pulse:
                    let minimum = (options?.pulseMinimum ?? 15) / 100
                    let level = minimum + (1 - minimum) * (sin(phase * .pi * 2) + 1) / 2
                    matrix[coordinate] = color.scaled(by: level)
                case .blink:
                    matrix[coordinate] = phase < 0.5 ? color : .black
                case .rainbow:
                    matrix[coordinate] = .hsv(hue: Double(column) / Double(max(1, geometry.width)) + phase, saturation: 0.9, value: 1)
                case .scanner:
                    let rawPosition = Int((phase * Double(max(1, geometry.width))).rounded()) % max(1, geometry.width)
                    let position = options?.direction == -1 ? geometry.width - 1 - rawPosition : rawPosition
                    let distance = abs(column - position)
                    let trail = max(1, options?.trailLength ?? 1)
                    matrix[coordinate] = color.scaled(by: distance == 0 ? 1 : distance <= Int(trail) ? pow(0.24, Double(distance) / trail) : 0)
                case .sparkle:
                    let seed = (row * 31 + column * 17 + Int(progress * 9)) % 11
                    matrix[coordinate] = Double(seed) < (options?.sparkleDensity ?? 20) * 0.11 ? color : .black
                case .equalizer:
                    let wave = audioLevel > 0 ? audioLevel : (sin((Double(column) / Double(max(1, geometry.width)) + phase) * .pi * 2) + 1) / 2
                    let bar = Int((wave * Double(geometry.height)).rounded())
                    matrix[coordinate] = row >= geometry.height - bar ? color : .black
                case .countdown:
                    let filled = Int((1 - phase) * Double(geometry.pixelCount))
                    matrix[coordinate] = row * geometry.width + column < filled ? color : .black
                case .scrollText:
                    let glyphs = PixelText.glyphs(for: text.isEmpty ? "TEAMSLIGHT" : text)
                    let contentWidth = PixelText.contentWidth(of: glyphs)
                    let offset = Int(phase * Double(contentWidth + geometry.width)) - geometry.width
                    if PixelText.isLit(x: column + offset, y: row, glyphs: glyphs, displayHeight: geometry.height) {
                        matrix[coordinate] = color
                    }
                case .screenAmbient:
                    // AppController replaces this fallback with a sampled screen frame.
                    matrix[coordinate] = color.scaled(by: 0.2 + 0.8 * Double(row + column) / Double(max(1, geometry.width + geometry.height - 2)))
                }
            }
        }
        return matrix
    }
}

struct DisplayScene: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var animation: MatrixAnimation
    var color: LEDColor
    var text: String
    var framesPerSecond: Double
    var frames: [String]?
    var options: SceneOptions?

    init(id: UUID = UUID(), name: String, animation: MatrixAnimation, color: LEDColor, text: String = "", framesPerSecond: Double = 6, frames: [String]? = nil, options: SceneOptions? = nil) {
        self.id = id; self.name = name; self.animation = animation; self.color = color; self.text = text
        self.framesPerSecond = min(20, max(1, framesPerSecond))
        self.frames = frames
        self.options = options
    }

    func frame(geometry: MatrixGeometry, now: Date = .now, audioLevel: Double = 0) -> LEDMatrix {
        if let frames, !frames.isEmpty {
            let index = Int(now.timeIntervalSinceReferenceDate * framesPerSecond) % frames.count
            if let frame = LEDMatrix(hexPayload: frames[index], geometry: geometry) { return frame }
        }
        // `framesPerSecond` is a user-facing tempo control, not the length of
        // an entire animation. In particular, a marquee needs several seconds
        // to travel its full width rather than restarting every frame.
        let tuning = options ?? SceneOptions(scene: self)
        let speed = framesPerSecond / 8
        let duration: Double
        switch animation {
        case .scrollText:
            duration = max(2.5, Double(max(1, text.count)) * 0.5 / speed)
        case .rainbow: duration = 4 / speed
        case .pulse: duration = 1.8 / speed
        case .blink: duration = 2 / min(6, max(1, framesPerSecond))
        case .scanner: duration = 1 / speed
        case .sparkle: duration = 0.7 / speed
        case .equalizer: duration = 0.25 / speed
        case .countdown: duration = tuning.countdownDuration / speed
        case .solid, .screenAmbient: duration = 1
        }
        return animation.frame(geometry: geometry, color: color, progress: now.timeIntervalSinceReferenceDate / duration, text: text, audioLevel: audioLevel, options: tuning)
    }

    static let notificationFlash = DisplayScene(
        name: "Incoming Alert",
        animation: .blink,
        color: .white,
        framesPerSecond: 4
    )

    static let builtIns = [
        DisplayScene(name: "Focus Pulse", animation: .pulse, color: .init(red: 0, green: 120, blue: 255)),
        DisplayScene(name: "Rainbow", animation: .rainbow, color: .black, framesPerSecond: 8),
        notificationFlash,
        DisplayScene(name: "Audio Meter", animation: .equalizer, color: .init(red: 0, green: 255, blue: 110), framesPerSecond: 10),
        DisplayScene(name: "Desk Message", animation: .scrollText, color: .init(red: 255, green: 255, blue: 255), text: "HELLO", framesPerSecond: 8),
        DisplayScene(name: "Screen Ambient", animation: .screenAmbient, color: .init(red: 100, green: 150, blue: 255), framesPerSecond: 1)
    ]
}

struct SceneOptions: Codable, Equatable, Sendable {
    var framesPerSecond: Double
    var color: LEDColor
    var text: String
    var intensity: Double
    var direction: Int = 1
    var trailLength: Double = 1
    var sparkleDensity: Double = 20
    var pulseMinimum: Double = 15
    var countdownDuration: Double = 5

    init(scene: DisplayScene) {
        framesPerSecond = scene.framesPerSecond
        color = scene.color
        text = scene.text
        intensity = 100
    }

    private enum CodingKeys: String, CodingKey { case framesPerSecond, color, text, intensity, direction, trailLength, sparkleDensity, pulseMinimum, countdownDuration }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        framesPerSecond = try container.decode(Double.self, forKey: .framesPerSecond)
        color = try container.decode(LEDColor.self, forKey: .color)
        text = try container.decode(String.self, forKey: .text)
        intensity = try container.decode(Double.self, forKey: .intensity)
        direction = try container.decodeIfPresent(Int.self, forKey: .direction) ?? 1
        trailLength = try container.decodeIfPresent(Double.self, forKey: .trailLength) ?? 1
        sparkleDensity = try container.decodeIfPresent(Double.self, forKey: .sparkleDensity) ?? 20
        pulseMinimum = try container.decodeIfPresent(Double.self, forKey: .pulseMinimum) ?? 15
        countdownDuration = try container.decodeIfPresent(Double.self, forKey: .countdownDuration) ?? 5
    }
}

enum SceneRuleCondition: String, CaseIterable, Codable, Identifiable, Sendable {
    case anyPresence, available, busy, inCall, inMeeting, presenting, dnd, away, microphoneActive, upcomingMeeting
    var id: Self { self }
    var title: String { rawValue.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized }
    func matches(state: PresenceState, signals: [PresenceSignal], upcomingMeeting: Bool) -> Bool {
        switch self {
        case .anyPresence: return true
        case .available: return state == .available
        case .busy: return state == .busy
        case .inCall: return state == .inCall
        case .inMeeting: return state == .inMeeting
        case .presenting: return state == .presenting
        case .dnd: return state == .dnd
        case .away: return state == .away
        case .microphoneActive: return signals.contains { $0.provider == "Microphone" && $0.state == .inCall }
        case .upcomingMeeting: return upcomingMeeting
        }
    }
}

struct SceneRule: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var condition: SceneRuleCondition
    var sceneID: UUID
    var duration: Double
    init(id: UUID = UUID(), name: String, isEnabled: Bool = true, condition: SceneRuleCondition, sceneID: UUID, duration: Double = 0) {
        self.id = id; self.name = name; self.isEnabled = isEnabled; self.condition = condition; self.sceneID = sceneID; self.duration = max(0, duration)
    }
}

struct DeskNotification: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let scene: DisplayScene
    let expiresAt: Date
}

struct ScenePack: Codable, Sendable {
    let formatVersion: Int
    let scenes: [DisplayScene]
    let rules: [SceneRule]
}

enum ScenePriority: String, CaseIterable, Codable, Identifiable, Sendable {
    case notificationsFirst, manualFirst, automationFirst
    var id: Self { self }
    var title: String {
        switch self { case .notificationsFirst: "Notifications First"; case .manualFirst: "Manual Scenes First"; case .automationFirst: "Automation First" }
    }
}

struct SceneSafetyLimits: Codable, Equatable, Sendable {
    var maximumFramesPerSecond = 10.0
    var maximumIntensity = 100.0
}

struct TeamsLightBackup: Codable, Sendable {
    let formatVersion: Int
    let brightness: Double
    let matrixPayload: String
    let scenes: [DisplayScene]
    let rules: [SceneRule]
    let sceneOptions: [UUID: SceneOptions]
    let appearanceProfiles: [String: StateAppearanceProfile]
    let presencePolicy: LocalPresencePolicy
    let safetyLimits: SceneSafetyLimits
    let scenePriority: ScenePriority
    let matrixPresets: Data?
    let calibrationRotation: Int
    let calibrationSerpentine: Bool
    let notificationFlashesEnabled: Bool?
}

private enum PixelText {
    // A deliberately compact 3×5 alphabet: useful on very small displays and
    // gracefully scales to larger dynamically discovered matrices.
    static let alphabet: [Character: [String]] = [
        "A": ["010","101","111","101","101"], "B": ["110","101","110","101","110"],
        "C": ["011","100","100","100","011"], "D": ["110","101","101","101","110"],
        "E": ["111","100","110","100","111"], "F": ["111","100","110","100","100"],
        "G": ["011","100","101","101","011"], "H": ["101","101","111","101","101"],
        "I": ["111","010","010","010","111"], "J": ["001","001","001","101","010"],
        "K": ["101","101","110","101","101"], "L": ["100","100","100","100","111"],
        "M": ["101","111","111","101","101"],
        // A five-column N keeps its diagonal recognizable on the 8×8 panel.
        "N": ["10001","11001","10101","10011","10001"],
        "O": ["010","101","101","101","010"], "P": ["110","101","110","100","100"],
        "Q": ["010","101","101","011","001"], "R": ["110","101","110","101","101"],
        "S": ["011","100","010","001","110"],
        "T": ["111","010","010","010","010"], "U": ["101","101","101","101","111"],
        "V": ["101","101","101","101","010"], "W": ["101","101","111","111","101"],
        "X": ["101","101","010","101","101"], "Y": ["101","101","010","010","010"],
        "Z": ["111","001","010","100","111"],
        "0": ["111","101","101","101","111"], "1": ["010","110","010","010","111"],
        "2": ["110","001","010","100","111"], "3": ["110","001","010","001","110"],
        "4": ["101","101","111","001","001"], "5": ["111","100","110","001","110"],
        "6": ["011","100","110","101","010"], "7": ["111","001","010","010","010"],
        "8": ["010","101","010","101","010"], "9": ["010","101","011","001","110"],
        "'": ["010","010","000","000","000"], "\"": ["101","101","000","000","000"],
        ".": ["000","000","000","000","010"], ",": ["000","000","000","010","100"],
        "!": ["010","010","010","000","010"], "?": ["110","001","010","000","010"],
        "-": ["000","000","111","000","000"], "_": ["000","000","000","000","111"],
        "/": ["001","001","010","100","100"], ":": ["000","010","000","010","000"],
        " ": ["000","000","000","000","000"]
    ]
    static func glyphs(for text: String) -> [[String]] {
        text.uppercased().map { character in
            let normalized: Character
            switch character {
            case "’", "‘", "‛", "`": normalized = "'"
            case "“", "”", "„": normalized = "\""
            case "–", "—", "−": normalized = "-"
            default: normalized = character
            }
            return alphabet[normalized] ?? alphabet[" "]!
        }
    }
    static func contentWidth(of glyphs: [[String]]) -> Int {
        glyphs.reduce(0) { $0 + glyphWidth(of: $1) + 1 }
    }
    static func isLit(x: Int, y: Int, glyphs: [[String]], displayHeight: Int) -> Bool {
        var glyphX = x
        var glyph: [String]?
        for candidate in glyphs {
            let width = glyphWidth(of: candidate)
            if glyphX >= 0, glyphX < width {
                glyph = candidate
                break
            }
            glyphX -= width + 1
        }
        guard let glyph else { return false }
        let glyphY = y - max(0, (displayHeight - 5) / 2)
        guard glyphY >= 0, glyphY < 5 else { return false }
        return Array(glyph[glyphY])[glyphX] == "1"
    }
    private static func glyphWidth(of glyph: [String]) -> Int { glyph.first?.count ?? 0 }
}

extension LEDColor {
    func scaled(by factor: Double) -> LEDColor {
        LEDColor(red: UInt8((Double(red) * factor).rounded()), green: UInt8((Double(green) * factor).rounded()), blue: UInt8((Double(blue) * factor).rounded()))
    }
    static func hsv(hue: Double, saturation: Double, value: Double) -> LEDColor {
        let hue = hue - floor(hue); let sector = hue * 6; let x = value * (1 - saturation * abs(sector.truncatingRemainder(dividingBy: 2) - 1)); let m = value * (1 - saturation)
        let rgb: (Double, Double, Double)
        switch Int(sector) { case 0: rgb = (value, x, m); case 1: rgb = (x, value, m); case 2: rgb = (m, value, x); case 3: rgb = (m, x, value); case 4: rgb = (x, m, value); default: rgb = (value, m, x) }
        return LEDColor(red: UInt8((rgb.0 * 255).rounded()), green: UInt8((rgb.1 * 255).rounded()), blue: UInt8((rgb.2 * 255).rounded()))
    }
}
