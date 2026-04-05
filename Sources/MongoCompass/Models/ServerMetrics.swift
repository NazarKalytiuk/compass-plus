import Foundation

struct ServerMetrics {
    var connectionsActive: Int = 0
    var connectionsAvailable: Int = 0
    var connectionsTotalCreated: Int = 0
    var memoryResident: Int = 0
    var memoryVirtual: Int = 0
    var opcounters: [String: Int] = [:]
    var networkBytesIn: Int64 = 0
    var networkBytesOut: Int64 = 0
    var uptime: Int = 0
    var version: String = ""
    var host: String = ""
    var dbStats: [DatabaseStats] = []

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
    let opsPerSec: Double
    let memoryMB: Double
    let networkInPerSec: Double
    let networkOutPerSec: Double
}
