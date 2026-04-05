import Foundation

struct TabState: Identifiable {
    let id: UUID
    var selectedDatabase: String?
    var selectedCollection: String?
    var filter: String
    var sort: String
    var projection: String
    var skip: Int
    var limit: Int
    var navSection: NavSection

    init(id: UUID = UUID(), selectedDatabase: String? = nil, selectedCollection: String? = nil, filter: String = "", sort: String = "", projection: String = "", skip: Int = 0, limit: Int = 20, navSection: NavSection = .explorer) {
        self.id = id
        self.selectedDatabase = selectedDatabase
        self.selectedCollection = selectedCollection
        self.filter = filter
        self.sort = sort
        self.projection = projection
        self.skip = skip
        self.limit = limit
        self.navSection = navSection
    }
}
