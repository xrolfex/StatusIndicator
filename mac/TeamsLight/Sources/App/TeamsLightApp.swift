import ServiceManagement
import SwiftUI
import os
import AVFoundation
import EventKit

@MainActor
func bringToForeground(_ window: NSWindow) {
    NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    window.orderFrontRegardless()
    window.makeKeyAndOrderFront(nil)
}
