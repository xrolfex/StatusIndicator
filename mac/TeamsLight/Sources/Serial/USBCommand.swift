import Foundation

enum USBCommand: Equatable, Sendable {
    case presence(PresenceState), brightness(Int), color(UInt8, UInt8, UInt8), ping, status, test, off
    var wireValue: String {
        switch self {
        case .presence(let state): return state.rawValue
        case .brightness(let value): return "BRIGHTNESS \(min(15, max(0, value)))"
        case .color(let r, let g, let b): return "COLOR \(r) \(g) \(b)"
        case .ping: return "PING"; case .status: return "STATUS"; case .test: return "TEST"; case .off: return "OFF"
        }
    }
}
