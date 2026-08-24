import Combine
import Foundation

struct LEDColor: Equatable, Hashable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    
    static let black = LEDColor(red: 0, green: 0, blue: 0)
    
    var hexValue: String {
        String(format: "%02X%02X%02X", red, green, blue)
    }
}

struct MatrixCoordinate: Hashable, Sendable {
    let row: Int
    let column: Int
    
    init(row: Int, column: Int) {
        precondition((0..<LEDMatrix.height).contains(row))
        precondition((0..<LEDMatrix.width).contains(column))
        self.row = row
        self.column = column
    }
    
    fileprivate var index: Int { row * LEDMatrix.width + column }
    
    static func rectangle(from start: MatrixCoordinate, to end: MatrixCoordinate) -> Set<MatrixCoordinate> {
        let rows = min(start.row, end.row)...max(start.row, end.row)
        let columns = min(start.column, end.column)...max(start.column, end.column)
        return Set(rows.flatMap { row in
            columns.map { column in
                MatrixCoordinate(row: row, column: column)
            }
        })
    }
}

struct LEDMatrix: Equatable, Sendable {
    static let width = 8
    static let height = 8
    static let count = width * height
    static let coordinates = (0..<height).flatMap { row in
        (0..<width).map { column in
            MatrixCoordinate(row: row, column: column)
        }
    }
    
    private(set) var pixels: [LEDColor]
    
    init(fill color: LEDColor = .black) {
        pixels = Array(repeating: color, count: Self.count)
    }

    init?(hexPayload: String) {
        guard hexPayload.count == Self.count * 6 else { return nil }
        var restored: [LEDColor] = []
        for offset in stride(from: 0, to: hexPayload.count, by: 6) {
            let start = hexPayload.index(hexPayload.startIndex, offsetBy: offset)
            let end = hexPayload.index(start, offsetBy: 6)
            guard let value = UInt32(hexPayload[start..<end], radix: 16) else { return nil }
            restored.append(LEDColor(
                red: UInt8((value >> 16) & 0xFF),
                green: UInt8((value >> 8) & 0xFF),
                blue: UInt8(value & 0xFF)
            ))
        }
        pixels = restored
    }
    
    subscript(coordinate: MatrixCoordinate) -> LEDColor {
        get { pixels[coordinate.index] }
        set { pixels[coordinate.index] = newValue }
    }
    
    mutating func fill(with color: LEDColor) {
        pixels = Array(repeating: color, count: Self.count)
    }
    
    mutating func setColor(_ color: LEDColor, at coordinates: Set<MatrixCoordinate>) {
        for coordinate in coordinates {
            self[coordinate] = color
        }
    }
    
    var hexPayload: String {
        pixels.reduce(into: "") { payload, color in
            payload.append(color.hexValue)
        }
    }
}

struct MatrixPreset: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let payload: String
    let isBuiltIn: Bool

    init(id: UUID = UUID(), name: String, matrix: LEDMatrix, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        payload = matrix.hexPayload
        self.isBuiltIn = isBuiltIn
    }

    var matrix: LEDMatrix { LEDMatrix(hexPayload: payload) ?? LEDMatrix() }

    static let builtIns: [MatrixPreset] = [
        preset("Available", id: "D05FAE0A-9F1F-4D61-8B4A-000000000001", fill: LEDColor(red: 0, green: 255, blue: 0)),
        preset("Busy", id: "D05FAE0A-9F1F-4D61-8B4A-000000000002", fill: LEDColor(red: 255, green: 0, blue: 0)),
        preset("DND", id: "D05FAE0A-9F1F-4D61-8B4A-000000000003", fill: LEDColor(red: 255, green: 0, blue: 255)),
        patternedPreset("Focus Border", id: "D05FAE0A-9F1F-4D61-8B4A-000000000004", color: LEDColor(red: 0, green: 120, blue: 255)) { row, column in
            row == 0 || row == 7 || column == 0 || column == 7
        },
        patternedPreset("Break", id: "D05FAE0A-9F1F-4D61-8B4A-000000000005", color: LEDColor(red: 255, green: 145, blue: 0)) { row, column in
            (row + column).isMultiple(of: 3)
        },
        patternedPreset("Checkmark", id: "D05FAE0A-9F1F-4D61-8B4A-000000000006", color: LEDColor(red: 0, green: 255, blue: 110)) { row, column in
            (column == row - 2 && (3...5).contains(row)) || (column == 6 - row && (2...6).contains(row))
        }
    ]

    private static func preset(_ name: String, id: String, fill color: LEDColor) -> MatrixPreset {
        MatrixPreset(id: UUID(uuidString: id)!, name: name, matrix: LEDMatrix(fill: color), isBuiltIn: true)
    }

    private static func patternedPreset(_ name: String, id: String, color: LEDColor, includes: (Int, Int) -> Bool) -> MatrixPreset {
        var matrix = LEDMatrix()
        for coordinate in LEDMatrix.coordinates where includes(coordinate.row, coordinate.column) {
            matrix[coordinate] = color
        }
        return MatrixPreset(id: UUID(uuidString: id)!, name: name, matrix: matrix, isBuiltIn: true)
    }
}

@MainActor
final class MatrixPresetStore: ObservableObject {
    private static let storageKey = "matrixPresets"
    private let defaults: UserDefaults
    @Published private(set) var customPresets: [MatrixPreset]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.storageKey), let presets = try? JSONDecoder().decode([MatrixPreset].self, from: data) else {
            customPresets = []
            return
        }
        customPresets = presets.filter { !$0.isBuiltIn }
    }

    func save(name: String, matrix: LEDMatrix) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        customPresets.append(MatrixPreset(name: trimmedName, matrix: matrix))
        persist()
    }

    func remove(_ preset: MatrixPreset) {
        customPresets.removeAll { $0.id == preset.id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(customPresets) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
