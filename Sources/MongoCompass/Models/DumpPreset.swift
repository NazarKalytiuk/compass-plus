import Foundation

/// Snapshot of the Dump/Restore form. Stored in UserDefaults via
/// StorageService so users can recall common backup configurations.
struct DumpPreset: Codable, Identifiable {
    let id: UUID
    var name: String

    // Dump side
    var dumpDatabase: String
    var dumpCollection: String
    var dumpScope: String          // raw value of DumpRestoreView.DumpScope
    var dumpOutputPath: String
    var dumpGzip: Bool
    var dumpParallel: Int
    var dumpOplog: Bool
    var dumpExcludeIndexes: Bool

    // Restore side
    var restoreInputPath: String
    var restoreTargetDatabase: String
    var restoreStrategy: String    // raw value of DumpRestoreView.RestoreStrategy
    var restoreGzip: Bool
    var restoreParallel: Int
    var restoreOplogReplay: Bool
    var restoreMaintainOrder: Bool
    var restoreNoIndexRestore: Bool

    init(
        id: UUID = UUID(),
        name: String,
        dumpDatabase: String = "",
        dumpCollection: String = "",
        dumpScope: String = "All collections",
        dumpOutputPath: String = "",
        dumpGzip: Bool = true,
        dumpParallel: Int = 4,
        dumpOplog: Bool = true,
        dumpExcludeIndexes: Bool = false,
        restoreInputPath: String = "",
        restoreTargetDatabase: String = "",
        restoreStrategy: String = "Drop + restore",
        restoreGzip: Bool = true,
        restoreParallel: Int = 6,
        restoreOplogReplay: Bool = true,
        restoreMaintainOrder: Bool = true,
        restoreNoIndexRestore: Bool = false
    ) {
        self.id = id
        self.name = name
        self.dumpDatabase = dumpDatabase
        self.dumpCollection = dumpCollection
        self.dumpScope = dumpScope
        self.dumpOutputPath = dumpOutputPath
        self.dumpGzip = dumpGzip
        self.dumpParallel = dumpParallel
        self.dumpOplog = dumpOplog
        self.dumpExcludeIndexes = dumpExcludeIndexes
        self.restoreInputPath = restoreInputPath
        self.restoreTargetDatabase = restoreTargetDatabase
        self.restoreStrategy = restoreStrategy
        self.restoreGzip = restoreGzip
        self.restoreParallel = restoreParallel
        self.restoreOplogReplay = restoreOplogReplay
        self.restoreMaintainOrder = restoreMaintainOrder
        self.restoreNoIndexRestore = restoreNoIndexRestore
    }
}
