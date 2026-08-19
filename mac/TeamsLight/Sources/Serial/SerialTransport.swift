import Darwin
import Foundation
import os

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
    private let logger = Logger(subsystem: "com.example.TeamsLight", category: "serial")
    private var fd: Int32 = -1
    private(set) var deviceName: String?
    private(set) var lastResponse = "—"
    var isConnected: Bool { fd >= 0 }
    private let queue = DispatchQueue(label: "com.example.TeamsLight.serial")

    func reconnect() async { await withCheckedContinuation { continuation in queue.async { self.closeLocked(); self.connectLocked(); continuation.resume() } } }
    func send(_ command: String) async { await withCheckedContinuation { continuation in queue.async { self.writeLocked(command + "\n"); continuation.resume() } } }
    func close() { queue.sync { closeLocked() } }
    private func candidatePaths() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return names.filter { $0.hasPrefix("cu.usbmodem") || $0.hasPrefix("cu.usbserial") }.map { "/dev/\($0)" }.sorted()
    }
    private func connectLocked() {
        for path in candidatePaths() where openAndHandshake(path) {
            logger.info("ESP32 connected")
            return
        }
        logger.debug("No verified ESP32 serial device found")
    }
    private func openAndHandshake(_ path: String) -> Bool {
        let candidate = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard candidate >= 0 else { return false }
        var options = termios(); guard tcgetattr(candidate, &options) == 0 else { Darwin.close(candidate); return false }
        cfmakeraw(&options)
        options.c_cflag |= tcflag_t(CLOCAL | CREAD)
        withUnsafeMutablePointer(to: &options.c_cc) { controlCharacters in
            controlCharacters.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) {
                $0[Int(VMIN)] = 0
                $0[Int(VTIME)] = 2
            }
        }
        guard tcsetattr(candidate, TCSANOW, &options) == 0 else { Darwin.close(candidate); return false }
        _ = Darwin.write(candidate, "PING\n", 5)
        var bytes = [UInt8](repeating: 0, count: 64)
        let deadline = Date().addingTimeInterval(1)
        var response = ""
        while Date() < deadline {
            let count = Darwin.read(candidate, &bytes, bytes.count)
            if count > 0 { response += String(decoding: bytes[0..<Int(count)], as: UTF8.self); if response.contains("PONG") { fd = candidate; deviceName = path; lastResponse = "PONG"; return true } }
            usleep(20_000)
        }
        Darwin.close(candidate); return false
    }
    private func writeLocked(_ text: String) {
        if fd < 0 { connectLocked() }
        guard fd >= 0 else { return }
        let data = Array(text.utf8)
        if Darwin.write(fd, data, data.count) < 0 { logger.error("Serial write failed"); closeLocked() }
    }
    private func closeLocked() { if fd >= 0 { Darwin.close(fd); fd = -1 }; deviceName = nil }
}
