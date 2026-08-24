import Foundation

enum USBCommand: Equatable, Sendable {
    case presence(PresenceState)
    case brightness(Int)
    case color(UInt8, UInt8, UInt8)
    case matrix(LEDMatrix)
    case pixel(MatrixCoordinate, LEDColor)
    case ping, status, info, fiveThree, off
    
    var wireValue: String {
        switch self {
        case .presence(let state): return state.rawValue
        case .brightness(let value): return "BRIGHTNESS \(min(15, max(0, value)))"
        case .color(let r, let g, let b): return "COLOR \(r) \(g) \(b)"
        case .matrix(let matrix): return "MATRIX \(matrix.hexPayload)"
        case .pixel(let coordinate, let color):
            return "PIXEL \(coordinate.row) \(coordinate.column) \(color.red) \(color.green) \(color.blue)"
        case .ping: return "PING"; case .status: return "STATUS"; case .info: return "INFO"; case .fiveThree: return "FIVE_THREE"; case .off: return "OFF"
        }
    }
}

enum USBResponse: Equatable, Sendable {
    case pong
    case ok(String)
    case error(String)
    case unknown(String)

    init(line: String) {
        let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized == "PONG" { self = .pong }
        else if normalized.hasPrefix("OK") { self = .ok(normalized) }
        else if normalized.hasPrefix("ERR") { self = .error(normalized) }
        else { self = .unknown(normalized) }
    }
}
