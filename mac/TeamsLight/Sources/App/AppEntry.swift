import SwiftUI

@main
struct TeamsLightApp: App {
    @StateObject private var controller = AppController()

    var body: some Scene {
        MenuBarExtra("Teams Light", systemImage: controller.menuBarSystemImage) {
            TeamsLightPopover(controller: controller)
        }
        .menuBarExtraStyle(.window)
    }
}
