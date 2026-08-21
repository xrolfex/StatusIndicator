import Foundation

enum USBCommand: Equatable, Sendable {
    case presence(PresenceState)
    case brightness(Int)
    case color(UInt8, UInt8, UInt8)
    case matrix(LEDMatrix)
    case pixel(MatrixCoordinate, LEDColor)
    case ping, status, test, fiveThree, off

    var wireValue: String {
        switch self {
        case .presence(let state): return state.rawValue
        case .brightness(let value): return "BRIGHTNESS \(min(15, max(0, value)))"
        case .color(let r, let g, let b): return "COLOR \(r) \(g) \(b)"
        case .matrix(let matrix): return "MATRIX \(matrix.hexPayload)"
        case .pixel(let coordinate, let color):
            return "PIXEL \(coordinate.row) \(coordinate.column) \(color.red) \(color.green) \(color.blue)"
        case .ping: return "PING"; case .status: return "STATUS"; case .test: return "TEST"; case .fiveThree: return "FIVE_THREE"; case .off: return "OFF"
        }
    }
}
