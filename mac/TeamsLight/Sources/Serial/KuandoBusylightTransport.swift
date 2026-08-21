import Foundation
import IOKit.hid

/// Protocol-compatible HID output for Kuando/Plenom Busylight Alpha and Omega devices.
enum KuandoBusylightCommand {
    static let outputReportLength = 64
    static let legacyVendorID: UInt16 = 0x04D8
    static let plenomVendorID: UInt16 = 0x27BB
    static let plenomProductIDs: Set<UInt16> = [0x3BCA, 0x3BCB, 0x3BCC, 0x3BCD, 0x3BCE, 0x3BCF]
    
    static func matches(vendorID: Int, productID: Int) -> Bool {
        guard let vendor = UInt16(exactly: vendorID), let product = UInt16(exactly: productID) else { return false }
        return vendor == legacyVendorID || (vendor == plenomVendorID && plenomProductIDs.contains(product))
    }
    
    /// Complete HIDAPI-style report: report ID 0 followed by the 64-byte
    /// Busylight command frame used by Alpha, UC, and Omega devices.
    static func colorReport(for state: PresenceState) -> [UInt8] {
        let color: (UInt8, UInt8, UInt8)
        switch state {
        case .available: color = (0, 255, 0)
        case .busy, .inCall, .inMeeting: color = (255, 0, 0)
        case .dnd: color = (255, 0, 255)
        case .presenting: color = (170, 0, 255)
        case .away: color = (255, 145, 0)
        case .unknown: color = (64, 64, 64)
        case .offline: color = (0, 0, 0)
        }
        return colorReport(red: color.0, green: color.1, blue: color.2)
    }
    
    static func scaled(red: UInt8, green: UInt8, blue: UInt8, brightnessPercent: Double) -> (UInt8, UInt8, UInt8) {
        let multiplier = min(100, max(0, brightnessPercent)) / 100
        return (
            UInt8((Double(red) * multiplier).rounded()),
            UInt8((Double(green) * multiplier).rounded()),
            UInt8((Double(blue) * multiplier).rounded())
        )
    }
    
    static func colorReport(red: UInt8, green: UInt8, blue: UInt8) -> [UInt8] {
        var payload = Array(repeating: UInt8(0), count: outputReportLength)
        
        // One 8-byte "single-step" command. The remaining six steps are empty.
        payload[0] = 0x10
        payload[2] = red
        payload[3] = green
        payload[4] = blue
        payload[5] = 1
        payload[7] = 128 // no ringtone
        
        // Global defaults required by the SDK's ReportOut prefill.
        payload[57] = 0xFF
        payload[58] = 0xFF
        payload[59] = 0xFF
        payload[60] = 0xFF
        payload[61] = 0xFF
        
        let checksum = payload.prefix(63).reduce(UInt16(0)) { $0 &+ UInt16($1) }
        payload[62] = UInt8(checksum >> 8)
        payload[63] = UInt8(truncatingIfNeeded: checksum)
        return [0] + payload
    }
}

/// Standard macOS IOKit HID transport; no bundled Kuando SDK, driver, or elevated privilege is required.
final class KuandoBusylightTransport: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.example.TeamsLight.busylight")
    private var manager: IOHIDManager?
    private var devices: [IOHIDDevice] = []
    private(set) var deviceName: String?
    var isConnected: Bool { !devices.isEmpty }
    
    func reconnect() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.closeLocked()
                self.connectLocked()
                continuation.resume()
            }
        }
    }
    
    func send(_ state: PresenceState, brightnessPercent: Double = 100) async {
        let report = KuandoBusylightCommand.colorReport(for: state)
        let color = KuandoBusylightCommand.scaled(red: report[3], green: report[4], blue: report[5], brightnessPercent: brightnessPercent)
        let scaledReport = KuandoBusylightCommand.colorReport(red: color.0, green: color.1, blue: color.2)
        await send(scaledReport)
    }
    
    func send(red: UInt8, green: UInt8, blue: UInt8, brightnessPercent: Double = 100) async {
        let color = KuandoBusylightCommand.scaled(red: red, green: green, blue: blue, brightnessPercent: brightnessPercent)
        await send(KuandoBusylightCommand.colorReport(red: color.0, green: color.1, blue: color.2))
    }
    
    private func send(_ report: [UInt8]) async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.writeLocked(report)
                continuation.resume()
            }
        }
    }
    
    private func connectLocked() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matchers: [[String: Int]] = [
            [kIOHIDVendorIDKey as String: Int(KuandoBusylightCommand.legacyVendorID)],
            [kIOHIDVendorIDKey as String: Int(KuandoBusylightCommand.plenomVendorID)]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matchers as CFArray)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return }
        let matched = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        devices = matched.filter { device in
            let vendor = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue ?? -1
            let product = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? -1
            return KuandoBusylightCommand.matches(vendorID: vendor, productID: product)
        }
        self.manager = manager
        updateDeviceNameLocked()
    }
    
    private func writeLocked(_ report: [UInt8]) {
        if devices.isEmpty { connectLocked() }
        guard !devices.isEmpty else { return }
        let reportID = CFIndex(report[0])
        let payload = Array(report.dropFirst())
        devices.removeAll { device in
            let result = payload.withUnsafeBytes { bytes in
                IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, reportID, bytes.baseAddress!.assumingMemoryBound(to: UInt8.self), payload.count)
            }
            return result != kIOReturnSuccess
        }
        if devices.isEmpty { closeLocked() } else { updateDeviceNameLocked() }
    }
    
    private func closeLocked() {
        if let manager { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        manager = nil
        devices = []
        deviceName = nil
    }
    
    private func updateDeviceNameLocked() {
        if devices.count == 1, let device = devices.first {
            deviceName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Kuando Busylight"
        } else if devices.count > 1 {
            deviceName = "\(devices.count) Busylights (all selected)"
        } else {
            deviceName = nil
        }
    }
}
