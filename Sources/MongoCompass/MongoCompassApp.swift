import SwiftUI
import AppKit

@main
struct MongoCompassApp: App {
    @State private var appViewModel = AppViewModel()
    @StateObject private var updateService = UpdateService()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appViewModel)
                .frame(minWidth: 1200, minHeight: 800)
                .preferredColorScheme(.light)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Tab") {
                    appViewModel.addTab()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Close Tab") {
                    appViewModel.closeCurrentTab()
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            // Standard macOS placement: app menu, right after "About".
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updateService.checkForUpdates()
                }
                .disabled(!updateService.canCheckForUpdates)
            }
        }
    }
}

// MARK: - App Delegate (needed for SPM executables to show as GUI app)

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Root View

@MainActor
struct RootView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        Group {
            if viewModel.isConnected {
                HomeView()
            } else {
                ConnectView()
            }
        }
        .background(Theme.canvas)
    }
}
