import AppKit
import SwiftUI

@MainActor
final class LEDMatrixWindowPresenter {
    static let shared = LEDMatrixWindowPresenter()
    private var window: NSWindow?
    private init() {}
    func show(controller: AppController) {
        controller.activateMatrixEditor()
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 640), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "LED Matrix Editor"
            window.contentView = NSHostingView(rootView: LEDMatrixEditorView(controller: controller))
            window.isReleasedWhenClosed = false; window.center(); self.window = window
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
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Matrix Presets"
            window.contentView = NSHostingView(rootView: MatrixPresetPickerView(controller: controller))
            window.isReleasedWhenClosed = false; window.center(); self.window = window
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
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 620), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Desk Display"
            window.contentView = NSHostingView(rootView: DeskDisplayView(controller: controller))
            window.isReleasedWhenClosed = false; window.center(); self.window = window
        }
        if let window { bringToForeground(window) }
    }
}
