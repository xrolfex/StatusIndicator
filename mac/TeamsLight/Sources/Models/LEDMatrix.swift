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
