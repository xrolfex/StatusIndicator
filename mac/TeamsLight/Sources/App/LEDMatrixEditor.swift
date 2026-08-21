import SwiftUI

@MainActor
final class LEDMatrixWindowPresenter {
    static let shared = LEDMatrixWindowPresenter()

    private var window: NSWindow?

    private init() {}

    func show(controller: AppController) {
        controller.activateMatrixEditor()

        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "LED Matrix Editor"
            window.contentView = NSHostingView(rootView: LEDMatrixEditorView(controller: controller))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct LEDMatrixEditorView: View {
    @ObservedObject var controller: AppController
    @State private var selectedPixels: Set<MatrixCoordinate> = [MatrixCoordinate(row: 0, column: 0)]
    @State private var selectionAnchor = MatrixCoordinate(row: 0, column: 0)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LED Matrix")
                    .font(.title2.bold())
                Text("Click to select one pixel, Command-click to toggle pixels, or Shift-click to select a rectangle. The color applies to the entire selection.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Grid(horizontalSpacing: 7, verticalSpacing: 7) {
                GridRow {
                    Color.clear.frame(width: 20, height: 16)
                    ForEach(0..<LEDMatrix.width, id: \.self) { column in
                        Text("\(column + 1)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 40)
                    }
                }
                ForEach(0..<LEDMatrix.height, id: \.self) { row in
                    GridRow {
                        Text("\(row + 1)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        ForEach(0..<LEDMatrix.width, id: \.self) { column in
                            let coordinate = MatrixCoordinate(row: row, column: column)
                            MatrixPixelButton(
                                coordinate: coordinate,
                                color: controller.matrixColor(at: coordinate),
                                isSelected: selectedPixels.contains(coordinate)
                            ) {
                                select(coordinate)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            HStack {
                ColorPicker(
                    selectionTitle,
                    selection: selectedColor,
                    supportsOpacity: false
                )
                Spacer()
                Text(selectionColorDescription)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Select All") {
                    selectedPixels = Set(LEDMatrix.coordinates)
                    selectionAnchor = MatrixCoordinate(row: 0, column: 0)
                }
                Button("Clear Matrix") {
                    controller.clearMatrix()
                }
                Spacer()
                if !controller.isMatrixOverride {
                    Button("Show Matrix") {
                        controller.activateMatrixEditor()
                    }
                }
                Button("Use Presence") {
                    controller.setPresenceOverride(nil)
                }
            }
        }
        .padding(24)
        .frame(width: 480, height: 640)
    }

    private var selectedColor: Binding<Color> {
        Binding(
            get: { controller.matrixColor(at: referencePixel).displayColor },
            set: { controller.setMatrixColor($0, at: selectedPixels) }
        )
    }

    private var referencePixel: MatrixCoordinate {
        selectedPixels.contains(selectionAnchor) ? selectionAnchor : selectedPixels.first!
    }

    private var selectionTitle: String {
        if selectedPixels.count == 1 {
            return "Row \(referencePixel.row + 1), Column \(referencePixel.column + 1)"
        }
        return "\(selectedPixels.count) Pixels Selected"
    }

    private var selectionColorDescription: String {
        let colors = Set(selectedPixels.map { controller.matrixColor(at: $0) })
        guard colors.count == 1, let color = colors.first else { return "Mixed" }
        return "#\(color.hexValue)"
    }

    private func select(_ coordinate: MatrixCoordinate) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift) {
            selectedPixels.formUnion(MatrixCoordinate.rectangle(from: selectionAnchor, to: coordinate))
        } else if modifiers.contains(.command) {
            if selectedPixels.contains(coordinate), selectedPixels.count > 1 {
                selectedPixels.remove(coordinate)
            } else {
                selectedPixels.insert(coordinate)
            }
            selectionAnchor = coordinate
        } else {
            selectedPixels = [coordinate]
            selectionAnchor = coordinate
        }
    }
}

private struct MatrixPixelButton: View {
    let coordinate: MatrixCoordinate
    let color: LEDColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 5)
                .fill(color.displayColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.4),
                            lineWidth: isSelected ? 3 : 1
                        )
                }
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .help("Row \(coordinate.row + 1), Column \(coordinate.column + 1): #\(color.hexValue)")
        .accessibilityLabel("Row \(coordinate.row + 1), column \(coordinate.column + 1)")
        .accessibilityValue("#\(color.hexValue)")
    }
}

private extension LEDColor {
    var displayColor: Color {
        Color(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255
        )
    }
}
