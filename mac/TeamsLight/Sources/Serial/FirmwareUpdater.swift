import CryptoKit
import Foundation

struct BundledFirmwareImage: Sendable {
    let board: String
    let version: String
    let data: Data
    let md5: String
    let sha256: String

    static let version = "2.0.0"

    static func load(
        for board: String,
        bundle: Bundle = .main
    ) throws -> BundledFirmwareImage {
        guard let environment = environmentName(for: board) else {
            throw FirmwareImageError.unsupportedBoard(board)
        }
        let bundledURL = bundle.url(
            forResource: "firmware",
            withExtension: "bin",
            subdirectory: "Firmware/\(environment)"
        )
        let url = bundledURL ?? developmentFirmwareURL(environment: environment, bundle: bundle)
        guard let url else { throw FirmwareImageError.imageMissing(environment) }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard !data.isEmpty else { throw FirmwareImageError.imageEmpty }
        let digest = Insecure.MD5.hash(data: data)
        let md5 = digest.map { String(format: "%02x", $0) }.joined()
        let sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return BundledFirmwareImage(
            board: board,
            version: version,
            data: data,
            md5: md5,
            sha256: sha256
        )
    }

    private static func environmentName(for board: String) -> String? {
        switch board {
        case "WAVESHARE_ESP32_S3_MATRIX":
            return "waveshare_esp32_s3_matrix"
        case "ESP32_WROOM_32D_WS2812B_64":
            return "esp32_wroom_32d_ws2812b_64"
        default:
            return nil
        }
    }

    private static func developmentFirmwareURL(
        environment: String,
        bundle: Bundle
    ) -> URL? {
        var directory = bundle.bundleURL
        for _ in 0..<10 {
            let candidate = directory
                .appendingPathComponent("firmware/.pio/build", isDirectory: true)
                .appendingPathComponent(environment, isDirectory: true)
                .appendingPathComponent("firmware.bin")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }
}

enum FirmwareImageError: LocalizedError {
    case unsupportedBoard(String)
    case imageMissing(String)
    case imageEmpty

    var errorDescription: String? {
        switch self {
        case .unsupportedBoard(let board):
            return "No firmware is available for \(board)."
        case .imageMissing(let environment):
            return "The bundled firmware for \(environment) is missing."
        case .imageEmpty:
            return "The bundled firmware image is empty."
        }
    }
}
