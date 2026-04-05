import Foundation

struct CurrentOp: Identifiable {
    let id: Int  // opid
    let type: String
    let op: String
    let namespace: String
    let client: String
    let executionTimeMs: Int
    let description: String
}
