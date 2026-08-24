import SwiftUI
import UniformTypeIdentifiers

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
        
        if let window { bringToForeground(window) }
    }
}

@MainActor
final class MatrixPresetWindowPresenter {
    static let shared = MatrixPresetWindowPresenter()
    private var window: NSWindow?

    private init() {}

    func show(controller: AppController) {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Matrix Presets"
            window.contentView = NSHostingView(rootView: MatrixPresetPickerView(controller: controller))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        if let window { bringToForeground(window) }
    }
}

@MainActor
final class DeskDisplayWindowPresenter {
    static let shared = DeskDisplayWindowPresenter()
    private var window: NSWindow?
    private init() {}

    func show(controller: AppController) {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            window.title = "Desk Display"
            window.contentView = NSHostingView(rootView: DeskDisplayView(controller: controller))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        if let window { bringToForeground(window) }
    }
}

struct DeskDisplayView: View {
    @ObservedObject var controller: AppController
    @State private var name = "My Scene"
    @State private var animation: MatrixAnimation = .pulse
    @State private var color = Color.cyan
    @State private var text = "HELLO"
    @State private var framesPerSecond = 8.0
    @State private var ruleCondition: SceneRuleCondition = .inMeeting
    @State private var ruleSceneID = DisplayScene.builtIns[0].id
    @State private var scenePackMessage: String?
    @State private var selectedSceneID = DisplayScene.builtIns[0].id

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Desk Display").font(.title2.bold())
                Text("Scenes can be shown manually, triggered by local presence rules, or used for short notifications. They adapt to the matrix size reported by your firmware.")
                    .foregroundStyle(.secondary)
                LabeledContent("Currently controls the matrix", value: controller.displayOwner)
                    .font(.callout)
                Section("Scenes") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 12) {
                        ForEach(controller.allScenes) { scene in
                            let configured = controller.configuredScene(scene)
                            VStack(spacing: 6) {
                                PresetThumbnail(matrix: configured.frame(geometry: controller.matrix.geometry))
                                Text(scene.name).font(.caption).lineLimit(1)
                                Button(controller.activeScene?.id == scene.id ? "Showing" : "Show") { controller.activateScene(scene) }
                                    .disabled(controller.activeScene?.id == scene.id)
                                Button("Options") { selectedSceneID = scene.id }
                                    .font(.caption2)
                                if !DisplayScene.builtIns.contains(where: { $0.id == scene.id }) {
                                    Button("Delete", role: .destructive) { controller.removeScene(scene) }.font(.caption2)
                                }
                            }
                            .padding(8).background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    HStack {
                        Button("Return to Presence") { controller.stopScene() }
                        Button("Test Alert") {
                            if let alert = DisplayScene.builtIns.first(where: { $0.name == "Incoming Alert" }) {
                                controller.enqueueNotification(title: "Test notification", scene: alert)
                            }
                        }
                        Button("Import Scene Pack…") { importScenePack() }
                        Button("Export Scene Pack…") { exportScenePack() }
                    }
                    if let scenePackMessage { Text(scenePackMessage).font(.caption).foregroundStyle(.secondary) }
                }
                if let selectedScene {
                    Divider()
                    Section("\(selectedScene.name) Options") {
                        Picker("Scene", selection: $selectedSceneID) {
                            ForEach(controller.allScenes) { Text($0.name).tag($0.id) }
                        }
                        HStack {
                            Text("Speed")
                            Slider(value: optionBinding(selectedScene, \.framesPerSecond), in: 1...20)
                            Text("\(Int(controller.options(for: selectedScene).framesPerSecond)) fps").monospacedDigit()
                        }
                        HStack {
                            Text("Intensity")
                            Slider(value: optionBinding(selectedScene, \.intensity), in: 5...100)
                            Text("\(Int(controller.options(for: selectedScene).intensity))%").monospacedDigit()
                        }
                        ColorPicker("Color", selection: colorOptionBinding(selectedScene), supportsOpacity: false)
                            .disabled(selectedScene.animation == .rainbow || selectedScene.animation == .screenAmbient || selectedScene.frames != nil)
                        if selectedScene.animation == .scrollText {
                            TextField("Message", text: textOptionBinding(selectedScene))
                            HStack {
                                ForEach(["HELLO", "FOCUS", "ON AIR", "BACK SOON"], id: \.self) { preset in
                                    Button(preset) { var options = controller.options(for: selectedScene); options.text = preset; controller.setOptions(options, for: selectedScene) }
                                }
                            }
                        }
                        animationSpecificOptions(for: selectedScene)
                        Text(optionHint(for: selectedScene)).font(.caption).foregroundStyle(.secondary)
                        TimelineView(.animation(minimumInterval: 0.1)) { context in
                            HStack(spacing: 14) {
                                PresetThumbnail(matrix: controller.previewFrame(for: selectedScene, at: context.date))
                                    .padding(8).background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                                Text("Live preview").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Divider()
                Section("Create a Scene") {
                    TextField("Name", text: $name)
                    Picker("Animation", selection: $animation) { ForEach(MatrixAnimation.allCases) { Text($0.title).tag($0) } }
                    ColorPicker("Color", selection: $color, supportsOpacity: false)
                    if animation == .scrollText { TextField("Message", text: $text) }
                    HStack { Text("Speed"); Slider(value: $framesPerSecond, in: 1...20); Text("\(Int(framesPerSecond)) fps").monospacedDigit() }
                    Button("Save Scene") {
                        guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return }
                        controller.saveScene(name: name, animation: animation, color: LEDColor(red: UInt8((rgb.redComponent * 255).rounded()), green: UInt8((rgb.greenComponent * 255).rounded()), blue: UInt8((rgb.blueComponent * 255).rounded())), text: text, framesPerSecond: framesPerSecond)
                    }
                    Button("Import Animated GIF…") { importGIF() }
                        .help("Converts up to 120 GIF frames to this matrix's discovered dimensions.")
                }
                Divider()
                Section("Automation Rules") {
                    HStack {
                        Picker("When", selection: $ruleCondition) { ForEach(SceneRuleCondition.allCases) { Text($0.title).tag($0) } }
                        Picker("Show", selection: $ruleSceneID) { ForEach(controller.allScenes) { Text($0.name).tag($0.id) } }
                        Button("Add Rule") {
                            controller.sceneRules.append(SceneRule(name: "\(ruleCondition.title) display", condition: ruleCondition, sceneID: ruleSceneID))
                        }
                    }
                    ForEach($controller.sceneRules) { $rule in
                        HStack {
                            Toggle(rule.name, isOn: $rule.isEnabled)
                            Spacer()
                            Button("Remove", role: .destructive) { controller.sceneRules.removeAll { $0.id == rule.id } }
                        }
                    }
                    if controller.sceneRules.isEmpty { Text("No rules yet. Add one to automatically show a scene when your desk state changes.").font(.caption).foregroundStyle(.secondary) }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 580, minHeight: 580)
    }

    private func importGIF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.gif]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let frames = MatrixImageConverter.matrices(from: url, geometry: controller.matrix.geometry, scaling: .fill)
        controller.saveFrameAnimation(name: url.deletingPathExtension().lastPathComponent, frames: frames, framesPerSecond: framesPerSecond)
    }
    private var selectedScene: DisplayScene? { controller.allScenes.first { $0.id == selectedSceneID } }
    private func optionBinding(_ scene: DisplayScene, _ keyPath: WritableKeyPath<SceneOptions, Double>) -> Binding<Double> {
        Binding(get: { controller.options(for: scene)[keyPath: keyPath] }, set: { value in
            var options = controller.options(for: scene); options[keyPath: keyPath] = value; controller.setOptions(options, for: scene)
        })
    }
    private func colorOptionBinding(_ scene: DisplayScene) -> Binding<Color> {
        Binding(get: {
            let color = controller.options(for: scene).color
            return Color(red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255)
        }, set: { color in
            guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return }
            var options = controller.options(for: scene)
            options.color = LEDColor(red: UInt8((rgb.redComponent * 255).rounded()), green: UInt8((rgb.greenComponent * 255).rounded()), blue: UInt8((rgb.blueComponent * 255).rounded()))
            controller.setOptions(options, for: scene)
        })
    }
    private func textOptionBinding(_ scene: DisplayScene) -> Binding<String> {
        Binding(get: { controller.options(for: scene).text }, set: { value in
            var options = controller.options(for: scene); options.text = value; controller.setOptions(options, for: scene)
        })
    }
    private func optionHint(for scene: DisplayScene) -> String {
        switch scene.animation {
        case .rainbow: return "Speed controls the colour cycle; hue and saturation are intentionally automatic."
        case .screenAmbient: return "Intensity scales the sampled screen colours; color is not used."
        case .equalizer: return "Use live microphone level in Settings for a responsive meter; speed is the fallback animation rate."
        case .scrollText: return "Message, color, intensity, and marquee speed are all live."
        default: return "Changes are saved locally and apply immediately when this scene is showing."
        }
    }
    @ViewBuilder
    private func animationSpecificOptions(for scene: DisplayScene) -> some View {
        switch scene.animation {
        case .scanner:
            Picker("Direction", selection: optionBinding(scene, \.direction)) { Text("Left to Right").tag(1); Text("Right to Left").tag(-1) }
            HStack { Text("Trail"); Slider(value: optionBinding(scene, \.trailLength), in: 1...6, step: 1); Text("\(Int(controller.options(for: scene).trailLength)) pixels") }
        case .sparkle:
            HStack { Text("Density"); Slider(value: optionBinding(scene, \.sparkleDensity), in: 5...70); Text("\(Int(controller.options(for: scene).sparkleDensity))%") }
        case .pulse:
            HStack { Text("Minimum glow"); Slider(value: optionBinding(scene, \.pulseMinimum), in: 0...80); Text("\(Int(controller.options(for: scene).pulseMinimum))%") }
        case .countdown:
            HStack { Text("Cycle"); Slider(value: optionBinding(scene, \.countdownDuration), in: 2...60, step: 1); Text("\(Int(controller.options(for: scene).countdownDuration)) sec") }
        default:
            EmptyView()
        }
    }
    private func optionBinding(_ scene: DisplayScene, _ keyPath: WritableKeyPath<SceneOptions, Int>) -> Binding<Int> {
        Binding(get: { controller.options(for: scene)[keyPath: keyPath] }, set: { value in
            var options = controller.options(for: scene); options[keyPath: keyPath] = value; controller.setOptions(options, for: scene)
        })
    }
    private func exportScenePack() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "TeamsLight-Scenes.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try controller.exportScenePack(to: url); scenePackMessage = "Scene pack exported" }
        catch { scenePackMessage = "Could not export scene pack" }
    }
    private func importScenePack() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let count = controller.importScenePack(from: url)
        scenePackMessage = count == 0 ? "No new scenes imported" : "Imported \(count) scene\(count == 1 ? "" : "s")"
    }
}

struct MatrixPresetPickerView: View {
    @ObservedObject var controller: AppController
    @StateObject private var store = MatrixPresetStore()
    @State private var newPresetName = "My Preset"
    @State private var transferMessage: String?
    @State private var imageScaling: MatrixImageScaling = .fit
    @State private var importedImage: NSImage?
    @State private var imageBrightness = 0.0
    @State private var imageContrast = 1.0
    @State private var imageGrayscale = false

    private var presets: [MatrixPreset] { MatrixPreset.builtIns + store.customPresets }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Matrix Presets")
                .font(.title2.bold())
            Text("Choose a preset to show it immediately, or save the current matrix as a reusable local preset.")
                .foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(presets) { preset in
                        PresetTile(preset: preset, isCustom: !preset.isBuiltIn) {
                            controller.applyMatrixPreset(preset)
                        } onDelete: {
                            store.remove(preset)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            Divider()
            HStack {
                TextField("Preset name", text: $newPresetName)
                Button("Save Current") {
                    store.save(name: newPresetName, matrix: controller.matrix)
                }
                .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Undo") { controller.undoMatrix() }
                    .disabled(!controller.canUndoMatrix)
                Button("Use Presence") {
                    controller.setPresenceOverride(nil)
                }
            }
            if let previewMatrix {
                Divider()
                HStack(alignment: .center, spacing: 16) {
                    PresetThumbnail(matrix: previewMatrix)
                        .padding(8)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading) {
                        Slider(value: $imageBrightness, in: -0.5...0.5) { Text("Brightness") }
                        Slider(value: $imageContrast, in: 0.5...2) { Text("Contrast") }
                        Toggle("Grayscale", isOn: $imageGrayscale)
                        Button("Apply Image") {
                            controller.applyImportedImageMatrix(previewMatrix)
                            transferMessage = "Image applied — save it as a preset to keep it"
                        }
                    }
                }
            }
            HStack {
                Picker("Image", selection: $imageScaling) {
                    ForEach(MatrixImageScaling.allCases) { scaling in
                        Text(scaling.title).tag(scaling)
                    }
                }
                .labelsHidden()
                Button("Import Image…") { importImage() }
                Button("Import…") { importPresets() }
                Button("Export…") { exportPresets() }
                if let transferMessage {
                    Text(transferMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .frame(width: 520, height: 560)
    }

    private func exportPresets() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "TeamsLight-Presets.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.export(to: url)
            transferMessage = "Presets exported"
        } catch {
            transferMessage = "Could not export presets"
        }
    }

    private func importPresets() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let count = store.importPresets(from: url)
        transferMessage = count == 1 ? "Imported 1 preset" : "Imported \(count) presets"
    }

    private func importImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else {
            return
        }
        importedImage = image
        transferMessage = "Adjust the preview, then apply it"
    }

    private var previewMatrix: LEDMatrix? {
        importedImage.flatMap { MatrixImageConverter.matrix(from: $0, geometry: controller.matrix.geometry, scaling: imageScaling, brightness: imageBrightness, contrast: imageContrast, grayscale: imageGrayscale) }
    }
}

private struct PresetTile: View {
    let preset: MatrixPreset
    let isCustom: Bool
    let apply: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button(action: apply) {
                PresetThumbnail(matrix: preset.matrix)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            Text(preset.name)
                .font(.caption)
                .lineLimit(1)
            if isCustom {
                Button("Delete", role: .destructive, action: onDelete)
                    .font(.caption2)
                    .buttonStyle(.link)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Matrix preset \(preset.name)")
    }
}

private struct PresetThumbnail: View {
    let matrix: LEDMatrix

    var body: some View {
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            ForEach(0..<matrix.geometry.height, id: \.self) { row in
                GridRow {
                    ForEach(0..<matrix.geometry.width, id: \.self) { column in
                        Rectangle()
                            .fill(matrix[MatrixCoordinate(row: row, column: column)].displayColor)
                            .frame(width: 11, height: 11)
                    }
                }
            }
        }
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
            
            ScrollView([.horizontal, .vertical]) {
            Grid(horizontalSpacing: 7, verticalSpacing: 7) {
                GridRow {
                    Color.clear.frame(width: 20, height: 16)
                    ForEach(0..<controller.matrix.geometry.width, id: \.self) { column in
                        Text("\(column + 1)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: cellSize)
                    }
                }
                ForEach(0..<controller.matrix.geometry.height, id: \.self) { row in
                    GridRow {
                        Text("\(row + 1)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        ForEach(0..<controller.matrix.geometry.width, id: \.self) { column in
                            let coordinate = MatrixCoordinate(row: row, column: column)
                            MatrixPixelButton(
                                coordinate: coordinate,
                                color: controller.matrixColor(at: coordinate),
                                isSelected: selectedPixels.contains(coordinate),
                                size: cellSize
                            ) {
                                select(coordinate)
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: 360)
            
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
                    selectedPixels = Set(controller.matrix.coordinates)
                    selectionAnchor = MatrixCoordinate(row: 0, column: 0)
                }
                Button("Clear Matrix") {
                    controller.clearMatrix()
                }
                Button("Undo") {
                    controller.undoMatrix()
                }
                .disabled(!controller.canUndoMatrix)
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
    private var cellSize: CGFloat { max(18, min(40, 380 / CGFloat(max(1, controller.matrix.geometry.width)))) }
    
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
            selectedPixels.formUnion(MatrixCoordinate.rectangle(from: selectionAnchor, to: coordinate, geometry: controller.matrix.geometry))
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
    let size: CGFloat
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
                .frame(width: size, height: size)
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
