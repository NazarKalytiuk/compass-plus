import Foundation

struct QueryLogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let operationType: OperationType
    let database: String
    let collection: String
    let query: String
    let executionTimeMs: Int
    let docsReturned: Int
    var isFavorite: Bool

    init(id: UUID = UUID(), timestamp: Date = Date(), operationType: OperationType, database: String, collection: String, query: String, executionTimeMs: Int, docsReturned: Int, isFavorite: Bool = false) {
        self.id = id
        self.timestamp = timestamp
        self.operationType = operationType
        self.database = database
        self.collection = collection
        self.query = query
        self.executionTimeMs = executionTimeMs
        self.docsReturned = docsReturned
        self.isFavorite = isFavorite
    }

    enum OperationType: String, Codable, CaseIterable {
        case find, insert, update, delete, aggregate

        var displayName: String { rawValue.capitalized }
    }
}
