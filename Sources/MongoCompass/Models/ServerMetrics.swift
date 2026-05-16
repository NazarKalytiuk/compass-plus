import Foundation

struct ServerMetrics {
    // Connections
    var connectionsActive: Int = 0
    var connectionsAvailable: Int = 0
    var connectionsTotalCreated: Int = 0

    // Memory (mongod process, MB)
    var memoryResident: Int = 0
    var memoryVirtual: Int = 0

    // Operation counters (cumulative since process start)
    var opcounters: [String: Int] = [:]

    // Network (cumulative bytes since process start)
    var networkBytesIn: Int64 = 0
    var networkBytesOut: Int64 = 0

    // Process stats from `extra_info`. Microseconds since process start.
    // Available on macOS / Linux mongod builds; fall back to 0 elsewhere.
    var cpuUserTimeUs: Int64 = 0
    var cpuSystemTimeUs: Int64 = 0
    var pageFaults: Int64 = 0

    // WiredTiger cache (only present when storage engine is WiredTiger).
    var cacheBytesUsed: Int64 = 0
    var cacheBytesConfigured: Int64 = 0
    var cachePagesReadIntoCache: Int64 = 0          // counter
    var cachePagesRequestedFromCache: Int64 = 0     // counter

    // WiredTiger block manager — physical disk I/O.
    var diskBytesRead: Int64 = 0                     // counter
    var diskBytesWritten: Int64 = 0                  // counter

    // Server identity
    var uptime: Int = 0
    var version: String = ""
    var host: String = ""

    // Replication: lag between PRIMARY and the most-behind SECONDARY in ms.
    // nil for standalone deployments (replSetGetStatus returns "no replset
    // config has been received" — we treat that as not-applicable).
    var replLagMs: Int? = nil

    // Per-database storage stats
    var dbStats: [DatabaseStats] = []

    /// True if `extra_info` was populated by the server (CPU%, page faults
    /// can be computed). False on builds where mongod doesn't expose it.
    var hasProcessStats: Bool {
        cpuUserTimeUs != 0 || cpuSystemTimeUs != 0 || pageFaults != 0
    }

    /// True if WiredTiger cache stats were populated. False for non-WT
    /// engines (inMemory, mmapv1) or older servers.
    var hasCacheStats: Bool {
        cacheBytesConfigured != 0
    }

    /// True if WiredTiger block-manager stats were populated. False for
    /// non-WT engines.
    var hasDiskStats: Bool {
        diskBytesRead != 0 || diskBytesWritten != 0
    }

    struct DatabaseStats: Identifiable {
        let id = UUID()
        let name: String
        let dataSize: Int64
        let storageSize: Int64
        let collections: Int
    }
}

struct MetricsSnapshot {
    let timestamp: Date

    // Derived per-second values from cumulative-counter deltas.
    let opsPerSec: Double
    let memoryMB: Double
    let networkInPerSec: Double          // bytes/sec
    let networkOutPerSec: Double         // bytes/sec

    // mongod process CPU usage as a percentage of one core.
    // > 100% indicates multi-core utilisation. `nil` when extra_info
    // was not reported by the server in either of the two samples.
    let cpuPercent: Double?

    // Fraction in 0...1. `nil` if WiredTiger cache stats unavailable
    // or if no cache requests occurred in the window.
    let cacheHitRatio: Double?

    // Physical disk I/O in bytes/sec from WiredTiger block-manager.
    // `nil` when WT stats unavailable.
    let diskReadPerSec: Double?
    let diskWritePerSec: Double?

    let pageFaultsPerSec: Double?

    // Replica-set lag at this snapshot in ms. `nil` for standalones.
    let replLagMs: Double?

    // WiredTiger cache footprint in MB. `nil` when not on a WT engine.
    let wtCacheMB: Double?
}
