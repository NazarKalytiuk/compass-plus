import Foundation

struct SlowQueryEntry: Identifiable {
    let id = UUID()
    let operation: String
    let namespace: String
    let command: String
    let executionTimeMs: Int
    let keysExamined: Int
    let docsExamined: Int
    let planSummary: String
}
