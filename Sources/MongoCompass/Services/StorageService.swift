import Foundation

final class StorageService {

    private let defaults: UserDefaults

    private enum Keys {
        static let savedConnections = "saved_connections"
        static let queryLog = "query_log"
        static let savedQueries = "saved_queries_v1"
        static let savedPipelines = "saved_pipelines_v1"
    }

    private static let maxConnections = 10
    private static let maxLogEntries = 500

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Connections

    func loadConnections() -> [ConnectionModel] {
        return decode([ConnectionModel].self, forKey: Keys.savedConnections)
    }

    func saveConnections(_ connections: [ConnectionModel]) {
        encode(connections, forKey: Keys.savedConnections)
    }

    func addConnection(_ connection: ConnectionModel) {
        var list = loadConnections()
        // Remove any existing entry with the same id
        list.removeAll { $0.id == connection.id }
        // Insert at the top
        list.insert(connection, at: 0)
        // Cap at max
        if list.count > Self.maxConnections {
            list = Array(list.prefix(Self.maxConnections))
        }
        saveConnections(list)
    }

    func removeConnection(id: UUID) {
        var list = loadConnections()
        list.removeAll { $0.id == id }
        saveConnections(list)
    }

    // MARK: - Query Log

    func loadQueryLog() -> [QueryLogEntry] {
        return decode([QueryLogEntry].self, forKey: Keys.queryLog)
    }

    func addLogEntry(_ entry: QueryLogEntry) {
        var log = loadQueryLog()
        log.insert(entry, at: 0)
        if log.count > Self.maxLogEntries {
            log = Array(log.prefix(Self.maxLogEntries))
        }
        encode(log, forKey: Keys.queryLog)
    }

    func clearLog() {
        defaults.removeObject(forKey: Keys.queryLog)
    }

    func toggleFavorite(id: UUID) {
        var log = loadQueryLog()
        if let index = log.firstIndex(where: { $0.id == id }) {
            log[index].isFavorite.toggle()
        }
        encode(log, forKey: Keys.queryLog)
    }

    // MARK: - Saved Queries

    func loadSavedQueries() -> [SavedQuery] {
        return decode([SavedQuery].self, forKey: Keys.savedQueries)
    }

    func saveQuery(_ query: SavedQuery) {
        var list = loadSavedQueries()
        // Replace if existing, otherwise append
        if let index = list.firstIndex(where: { $0.id == query.id }) {
            list[index] = query
        } else {
            list.insert(query, at: 0)
        }
        encode(list, forKey: Keys.savedQueries)
    }

    func removeQuery(id: UUID) {
        var list = loadSavedQueries()
        list.removeAll { $0.id == id }
        encode(list, forKey: Keys.savedQueries)
    }

    // MARK: - Saved Pipelines

    func loadSavedPipelines() -> [SavedPipeline] {
        return decode([SavedPipeline].self, forKey: Keys.savedPipelines)
    }

    func savePipeline(_ pipeline: SavedPipeline) {
        var list = loadSavedPipelines()
        if let index = list.firstIndex(where: { $0.id == pipeline.id }) {
            list[index] = pipeline
        } else {
            list.insert(pipeline, at: 0)
        }
        encode(list, forKey: Keys.savedPipelines)
    }

    func removePipeline(id: UUID) {
        var list = loadSavedPipelines()
        list.removeAll { $0.id == id }
        encode(list, forKey: Keys.savedPipelines)
    }

    // MARK: - Import / Export Connections

    func exportConnections(to url: URL) throws {
        let connections = loadConnections()
        let data = try JSONEncoder().encode(connections)
        try data.write(to: url, options: .atomic)
    }

    func importConnections(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let imported = try JSONDecoder().decode([ConnectionModel].self, from: data)
        var current = loadConnections()
        let existingIds = Set(current.map(\.id))
        for conn in imported where !existingIds.contains(conn.id) {
            current.append(conn)
        }
        if current.count > Self.maxConnections {
            current = Array(current.prefix(Self.maxConnections))
        }
        saveConnections(current)
    }

    // MARK: - Private Encode/Decode Helpers

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T where T: RangeReplaceableCollection {
        guard let data = defaults.data(forKey: key) else {
            return T()
        }
        return (try? JSONDecoder().decode(T.self, from: data)) ?? T()
    }
}
