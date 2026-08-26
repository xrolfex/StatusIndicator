import Combine
import Foundation
import AppKit
import ImageIO

struct LEDColor: Codable, Equatable, Hashable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    
    static let black = LEDColor(red: 0, green: 0, blue: 0)
    static let white = LEDColor(red: 255, green: 255, blue: 255)
    
    var hexValue: String {
        String(format: "%02X%02X%02X", red, green, blue)
    }
}

struct MatrixGeometry: Codable, Equatable, Sendable {
    let width: Int
    let height: Int
    var pixelCount: Int { width * height }
    static let legacy = MatrixGeometry(width: 8, height: 8)
}

struct MatrixCoordinate: Hashable, Sendable {
    let row: Int
    let column: Int
    
    init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
    
    fileprivate func index(width: Int) -> Int { row * width + column }
    
    static func rectangle(from start: MatrixCoordinate, to end: MatrixCoordinate, geometry: MatrixGeometry = .legacy) -> Set<MatrixCoordinate> {
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
    static let width = MatrixGeometry.legacy.width
    static let height = MatrixGeometry.legacy.height
    static let count = MatrixGeometry.legacy.pixelCount
    static let coordinates = (0..<height).flatMap { row in
        (0..<width).map { column in
            MatrixCoordinate(row: row, column: column)
        }
    }
    
    let geometry: MatrixGeometry
    private(set) var pixels: [LEDColor]
    
    init(geometry: MatrixGeometry = .legacy, fill color: LEDColor = .black) {
        self.geometry = geometry
        pixels = Array(repeating: color, count: geometry.pixelCount)
    }

    init?(hexPayload: String, geometry: MatrixGeometry = .legacy) {
        guard hexPayload.count == geometry.pixelCount * 6 else { return nil }
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
        self.geometry = geometry
        pixels = restored
    }
    
    subscript(coordinate: MatrixCoordinate) -> LEDColor {
        get { pixels[coordinate.index(width: geometry.width)] }
        set { pixels[coordinate.index(width: geometry.width)] = newValue }
    }
    
    mutating func fill(with color: LEDColor) {
        pixels = Array(repeating: color, count: geometry.pixelCount)
    }
    
    mutating func setColor(_ color: LEDColor, at coordinates: Set<MatrixCoordinate>) {
        for coordinate in coordinates {
            self[coordinate] = color
        }
    }
    var coordinates: [MatrixCoordinate] {
        (0..<geometry.height).flatMap { row in (0..<geometry.width).map { MatrixCoordinate(row: row, column: $0) } }
    }
    
    var hexPayload: String {
        pixels.reduce(into: "") { payload, color in
            payload.append(color.hexValue)
        }
    }

    /// Nearest-neighbour conversion keeps saved 8×8 artwork useful on any
    /// matrix discovered from the firmware.
    func resampled(to target: MatrixGeometry) -> LEDMatrix {
        guard geometry != target else { return self }
        var result = LEDMatrix(geometry: target)
        for row in 0..<target.height {
            for column in 0..<target.width {
                let sourceRow = min(geometry.height - 1, row * geometry.height / target.height)
                let sourceColumn = min(geometry.width - 1, column * geometry.width / target.width)
                result[MatrixCoordinate(row: row, column: column)] = self[MatrixCoordinate(row: sourceRow, column: sourceColumn)]
            }
        }
        return result
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
    static let storageKey = "matrixPresets"
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

    func export(to url: URL) throws {
        let data = try JSONEncoder().encode(customPresets)
        try data.write(to: url, options: .atomic)
    }

    @discardableResult
    func importPresets(from url: URL) -> Int {
        guard let data = try? Data(contentsOf: url), let imported = try? JSONDecoder().decode([MatrixPreset].self, from: data) else { return 0 }
        let valid = imported.filter { !$0.isBuiltIn && LEDMatrix(hexPayload: $0.payload) != nil }
        let existingPayloads = Set(customPresets.map(\.payload))
        let additions = valid.filter { !existingPayloads.contains($0.payload) }
        customPresets.append(contentsOf: additions)
        if !additions.isEmpty { persist() }
        return additions.count
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(customPresets) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    static func backupData(defaults: UserDefaults = .standard) -> Data? { defaults.data(forKey: storageKey) }
    static func restoreBackupData(_ data: Data, defaults: UserDefaults = .standard) {
        guard (try? JSONDecoder().decode([MatrixPreset].self, from: data)) != nil else { return }
        defaults.set(data, forKey: storageKey)
    }
}

enum MatrixImageScaling: String, CaseIterable, Identifiable {
    case fit
    case fill

    var id: Self { self }
    var title: String { self == .fit ? "Fit" : "Crop to Fill" }
}

enum MatrixImageConverter {
    static func matrices(from url: URL, geometry: MatrixGeometry, scaling: MatrixImageScaling, brightness: Double = 0, contrast: Double = 1, grayscale: Bool = false, maximumFrames: Int = 120) -> [LEDMatrix] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }
        return (0..<min(CGImageSourceGetCount(source), maximumFrames)).compactMap { index in
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }
            return matrix(from: NSImage(cgImage: image, size: .zero), geometry: geometry, scaling: scaling, brightness: brightness, contrast: contrast, grayscale: grayscale)
        }
    }
    static func matrix(from image: NSImage, geometry: MatrixGeometry = .legacy, scaling: MatrixImageScaling, brightness: Double = 0, contrast: Double = 1, grayscale: Bool = false) -> LEDMatrix? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else { return nil }
        let width = geometry.width
        let height = geometry.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let sourceSize = CGSize(width: cgImage.width, height: cgImage.height)
        let xScale = CGFloat(width) / sourceSize.width
        let yScale = CGFloat(height) / sourceSize.height
        let scale = scaling == .fit ? min(xScale, yScale) : max(xScale, yScale)
        let drawSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let drawRect = CGRect(
            x: (CGFloat(width) - drawSize.width) / 2,
            y: (CGFloat(height) - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        context.draw(cgImage, in: drawRect)

        var matrix = LEDMatrix(geometry: geometry)
        for row in 0..<height {
            for column in 0..<width {
                let offset = (row * width + column) * 4
                var red = Double(rgba[offset]) / 255
                var green = Double(rgba[offset + 1]) / 255
                var blue = Double(rgba[offset + 2]) / 255
                if grayscale {
                    let luminance = red * 0.299 + green * 0.587 + blue * 0.114
                    red = luminance; green = luminance; blue = luminance
                }
                func adjusted(_ value: Double) -> UInt8 {
                    UInt8((min(1, max(0, (value - 0.5) * contrast + 0.5 + brightness)) * 255).rounded())
                }
                matrix[MatrixCoordinate(row: row, column: column)] = LEDColor(red: adjusted(red), green: adjusted(green), blue: adjusted(blue))
            }
        }
        return matrix
    }
}
