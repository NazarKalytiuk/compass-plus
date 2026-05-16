import Foundation

struct CurrentOp: Identifiable {
    let id: Int  // opid
    let type: String
    let op: String
    let namespace: String
    let client: String
    let executionTimeMs: Int
    let description: String

    // Read / write lock acquire counts from `currentOp.locks.acquireCount`.
    // Default 0 keeps existing call sites compiling.
    var readLocks: Int = 0
    var writeLocks: Int = 0
}
