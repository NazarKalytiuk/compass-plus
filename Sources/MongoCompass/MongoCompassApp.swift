import SwiftUI
import AppKit

@main
struct MongoCompassApp: App {
    @State private var appViewModel = AppViewModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appViewModel)
                .frame(minWidth: 1200, minHeight: 800)
                .preferredColorScheme(.dark)
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
        .background(Theme.midnight)
    }
}
