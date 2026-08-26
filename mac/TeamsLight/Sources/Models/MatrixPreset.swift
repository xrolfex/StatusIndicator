import Foundation

struct MatrixPreset: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var matrix: LEDMatrix

    init(id: UUID = UUID(), name: String, matrix: LEDMatrix) {
        self.id = id
        self.name = name
        self.matrix = matrix
    }
}

struct MatrixLibrary: Codable, Equatable, Sendable {
    var currentMatrix: LEDMatrix
    var presets: [MatrixPreset]

    static let empty = MatrixLibrary(currentMatrix: LEDMatrix(), presets: [])
}

enum MatrixLibraryPersistence {
    static let defaultsKey = "matrixLibrary.v1"

    static func load(from defaults: UserDefaults = .standard) throws -> MatrixLibrary {
        guard let data = defaults.data(forKey: defaultsKey) else { return .empty }
        return try JSONDecoder().decode(MatrixLibrary.self, from: data)
    }

    static func save(_ library: MatrixLibrary, to defaults: UserDefaults = .standard) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        defaults.set(try encoder.encode(library), forKey: defaultsKey)
    }

    static func encodeMatrix(_ matrix: LEDMatrix) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(matrix), as: UTF8.self)
    }

    static func decodeMatrix(_ json: String) throws -> LEDMatrix {
        try JSONDecoder().decode(LEDMatrix.self, from: Data(json.utf8))
    }
}
