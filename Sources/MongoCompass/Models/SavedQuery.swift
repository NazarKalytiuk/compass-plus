import Foundation

struct SavedQuery: Codable, Identifiable {
    let id: UUID
    var name: String
    var database: String
    var collection: String
    var filter: String
    var sort: String
    var projection: String
    var tags: [String]

    init(id: UUID = UUID(), name: String, database: String, collection: String, filter: String = "", sort: String = "", projection: String = "", tags: [String] = []) {
        self.id = id
        self.name = name
        self.database = database
        self.collection = collection
        self.filter = filter
        self.sort = sort
        self.projection = projection
        self.tags = tags
    }
}
