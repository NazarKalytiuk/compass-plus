import Foundation

struct SlowQueryEntry: Identifiable {
    let id = UUID()
    let operation: String
    let namespace: String
    let command: String
    let executionTimeMs: Int       // representative single-sample ms (max across the group)
    let keysExamined: Int
    let docsExamined: Int
    let planSummary: String

    // Aggregated stats across multiple system.profile samples sharing the same
    // pattern hash. Defaulted so single-sample entries still render cleanly.
    var meanMs: Int = 0
    var p99Ms: Int = 0
    var count: Int = 1
    var lastSeen: Date = Date()
}
