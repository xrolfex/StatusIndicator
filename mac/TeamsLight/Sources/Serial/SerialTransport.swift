import Darwin
import Foundation
import os

struct MatrixCapabilities: Equatable, Sendable {
    let geometry: MatrixGeometry
    let rotation: Int
    let serpentine: Bool
    static func parse(_ response: String) -> MatrixCapabilities? {
        let fields = response.split(separator: " ")
        guard let widthIndex = fields.firstIndex(of: "WIDTH"), let heightIndex = fields.firstIndex(of: "HEIGHT"), let pixelIndex = fields.firstIndex(of: "PIXELS"),
              widthIndex + 1 < fields.count, heightIndex + 1 < fields.count, pixelIndex + 1 < fields.count,
              let width = Int(fields[widthIndex + 1]), let height = Int(fields[heightIndex + 1]), let pixels = Int(fields[pixelIndex + 1]),
              width > 0, height > 0, pixels == width * height else { return nil }
        let rotation = fields.firstIndex(of: "ROTATION").flatMap { $0 + 1 < fields.count ? Int(fields[$0 + 1]) : nil } ?? 0
        let serpentine = fields.firstIndex(of: "SERPENTINE").flatMap { $0 + 1 < fields.count ? Int(fields[$0 + 1]) : nil } == 1
        return MatrixCapabilities(geometry: MatrixGeometry(width: width, height: height), rotation: rotation, serpentine: serpentine)
    }
}

struct FirmwareHealth: Equatable, Sendable {
    let uptimeSeconds: Int
    let freeHeapBytes: Int
    let resetReason: Int

    static func parse(_ response: String) -> FirmwareHealth? {
        let fields = response.split(separator: " ")
        func value(after name: Substring) -> Int? {
            guard let index = fields.firstIndex(of: name), index + 1 < fields.count else { return nil }
            return Int(fields[index + 1])
        }
        guard let uptimeSeconds = value(after: "UPTIME"), let freeHeapBytes = value(after: "HEAP"), let resetReason = value(after: "RESET") else { return nil }
        return FirmwareHealth(uptimeSeconds: uptimeSeconds, freeHeapBytes: freeHeapBytes, resetReason: resetReason)
    }
}

protocol SerialTransport: AnyObject, Sendable {
    var isConnected: Bool { get }
    var deviceName: String? { get }
    var lastResponse: String { get }
    func reconnect() async
    func send(_ command: String) async
    func close()
}

/// Uses standard BSD tty devices and a protocol handshake. No USB driver or elevated privilege is needed.
final class USBSerialTransport: SerialTransport, @unchecked Sendable {
    private static let candidatePrefixes = [
        "cu.usbmodem",
        "cu.usbserial",
        "cu.SLAB_USBtoUART",
        "cu.wchusbserial"
    ]
    private let logger = Logger(subsystem: "com.example.TeamsLight", category: "serial")
    private var fd: Int32 = -1
    private var preferredDevicePath: String?
    private(set) var deviceName: String?
    private(set) var lastResponse = "—"
    private(set) var lastResponseKind: USBResponse = .unknown("—")
    private(set) var isLegacyFirmware = false
    private(set) var matrixCapabilities: MatrixCapabilities?
    private(set) var recoveryHint: String?
    private(set) var firmwareHealth: FirmwareHealth?
    var isConnected: Bool { fd >= 0 }
    private let queue = DispatchQueue(label: "com.example.TeamsLight.serial")
    
    func reconnect() async { await withCheckedContinuation { continuation in queue.async { self.closeLocked(); self.connectLocked(); continuation.resume() } } }
    func setPreferredDevicePath(_ path: String?) async { await withCheckedContinuation { continuation in queue.async { if self.preferredDevicePath != path { self.preferredDevicePath = path; self.closeLocked() }; continuation.resume() } } }
    func send(_ command: String) async { await withCheckedContinuation { continuation in queue.async { self.writeLocked(command + "\n"); continuation.resume() } } }
    func close() { queue.sync { closeLocked() } }
    static func isCandidateDeviceName(_ name: String) -> Bool {
        candidatePrefixes.contains { name.hasPrefix($0) }
    }
    static func candidatePaths() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return names.filter(Self.isCandidateDeviceName).map { "/dev/\($0)" }.sorted()
    }
    private func connectLocked() {
        let candidates = Self.candidatePaths()
        let ordered = preferredDevicePath.flatMap { preferred in
            candidates.contains(preferred) ? [preferred] + candidates.filter { $0 != preferred } : candidates
        } ?? candidates
        for path in ordered where openAndHandshake(path) {
            logger.info("ESP32 connected")
            recoveryHint = nil
            return
        }
        recoveryHint = candidates.isEmpty ? "No USB matrix found. Reconnect the board with a data-capable cable." : "A serial device was found but could not complete the handshake. Close serial monitors and retry."
        logger.debug("No verified ESP32 serial device found")
    }
    private func openAndHandshake(_ path: String) -> Bool {
        let candidate = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard candidate >= 0 else { return false }
        var options = termios(); guard tcgetattr(candidate, &options) == 0 else { Darwin.close(candidate); return false }
        cfmakeraw(&options)
        options.c_cflag |= tcflag_t(CLOCAL | CREAD)
        guard cfsetspeed(&options, speed_t(B115200)) == 0 else { Darwin.close(candidate); return false }
        withUnsafeMutablePointer(to: &options.c_cc) { controlCharacters in
            controlCharacters.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) {
                $0[Int(VMIN)] = 0
                $0[Int(VTIME)] = 2
            }
        }
        guard tcsetattr(candidate, TCSANOW, &options) == 0 else { Darwin.close(candidate); return false }
        var bytes = [UInt8](repeating: 0, count: 64)
        let deadline = Date().addingTimeInterval(1.5)
        var nextPing = Date.distantPast
        var response = ""
        while Date() < deadline {
            if Date() >= nextPing {
                _ = Darwin.write(candidate, "PING\n", 5)
                nextPing = Date().addingTimeInterval(0.25)
            }
            let count = Darwin.read(candidate, &bytes, bytes.count)
            if count > 0 {
                response += String(decoding: bytes[0..<Int(count)], as: UTF8.self)
                if response.contains("PONG") {
                    fd = candidate
                    deviceName = path
                    recordResponseLocked("PONG")
                    _ = writeAndReadLocked("INFO\n", timeout: 0.35, suppressErrors: true)
                    if lastResponse == "ERR UNKNOWN_COMMAND" {
                        isLegacyFirmware = true
                        lastResponse = "Legacy firmware (INFO unsupported)"
                        lastResponseKind = .ok(lastResponse)
                    }
                    return true
                }
            }
            usleep(20_000)
        }
        Darwin.close(candidate); return false
    }
    private func writeLocked(_ text: String) {
        if fd < 0 { connectLocked() }
        guard fd >= 0 else { return }
        let data = Array(text.utf8)
        let deadline = Date().addingTimeInterval(1)
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBufferPointer { buffer in
                Darwin.write(fd, buffer.baseAddress?.advanced(by: offset), buffer.count - offset)
            }
            if written > 0 {
                offset += written
            } else if written < 0 && errno == EINTR {
                continue
            } else if written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) && Date() < deadline {
                usleep(10_000)
            } else {
                logger.error("Serial write failed")
                recoveryHint = "The USB connection was interrupted or is in use by another app. Close serial monitors, reconnect the board, then choose Reconnect Devices."
                closeLocked()
                return
            }
        }
        _ = writeAndReadLocked(nil, timeout: 0.35)
    }
    /// Serial commands reply with one newline-delimited frame. Reading it here
    /// gives Diagnostics useful errors and prevents stale replies accumulating
    /// before the next command.
    @discardableResult
    private func writeAndReadLocked(_ text: String?, timeout: TimeInterval, suppressErrors: Bool = false) -> String? {
        if let text {
            let data = Array(text.utf8)
            let written = data.withUnsafeBufferPointer { Darwin.write(fd, $0.baseAddress, $0.count) }
            guard written == data.count else { return nil }
        }
        let deadline = Date().addingTimeInterval(timeout)
        var bytes = [UInt8](repeating: 0, count: 128)
        var response = ""
        while Date() < deadline {
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count > 0 {
                response += String(decoding: bytes[0..<Int(count)], as: UTF8.self)
                if let newline = response.firstIndex(of: "\n") {
                    let line = String(response[..<newline])
                    recordResponseLocked(line, suppressErrors: suppressErrors)
                    return line
                }
            } else if count < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
                logger.error("Serial read failed")
                recoveryHint = "The USB connection was interrupted or is in use by another app. Close serial monitors, reconnect the board, then choose Reconnect Devices."
                closeLocked()
                return nil
            }
            usleep(10_000)
        }
        return nil
    }
    private func recordResponseLocked(_ response: String, suppressErrors: Bool = false) {
        lastResponse = response
        lastResponseKind = USBResponse(line: response)
        if let capabilities = MatrixCapabilities.parse(response) { matrixCapabilities = capabilities }
        if let health = FirmwareHealth.parse(response) { firmwareHealth = health }
        if case .error = lastResponseKind, !suppressErrors { logger.error("Firmware rejected a command: \(response, privacy: .public)") }
    }
    private func closeLocked() { if fd >= 0 { Darwin.close(fd); fd = -1 }; deviceName = nil }
}
