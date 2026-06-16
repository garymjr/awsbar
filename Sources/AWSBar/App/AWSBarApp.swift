import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct AWSBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var profileStore = AWSProfileStore()

    var body: some Scene {
        MenuBarExtra("AWS", systemImage: profileStore.menuBarSystemImage) {
            AWSMenuView(store: profileStore)
        }
        .menuBarExtraStyle(.menu)
    }
}
