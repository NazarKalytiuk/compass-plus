import Foundation
import Sparkle
import SwiftUI

// MARK: - Sparkle auto-update bridge
//
// Wraps `SPUStandardUpdaterController` so SwiftUI can both:
//   - drive a "Check for Updates…" menu item, and
//   - reflect updater state (whether a check is allowed right now) so the
//     button can disable itself when an update is already in flight.
//
// One global instance lives on `MongoCompassApp`. The standard updater
// controller owns its own window/dialog UI — we don't render anything here.

@MainActor
final class UpdateService: ObservableObject {
    private let controller: SPUStandardUpdaterController

    /// Mirrors `SPUUpdater.canCheckForUpdates`. Bound to the menu item's
    /// `disabled` state so the user can't fire a second check while one is
    /// already running.
    @Published private(set) var canCheckForUpdates: Bool = true

    init() {
        // `startingUpdater: true` makes Sparkle do the first scheduled check
        // soon after launch (respecting SUScheduledCheckInterval from
        // Info.plist). Nil delegates → Sparkle uses its standard UI for
        // alerts, release notes, and the install step. Good defaults for us.
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // KVO bridge: `canCheckForUpdates` changes whenever an update flow
        // starts or ends. SwiftUI views observe `@Published`.
        self.controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// Wired to the "Check for Updates…" menu command.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
