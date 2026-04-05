import SwiftUI
import Foundation

@MainActor
@Observable
class AppViewModel {

    // MARK: - Services

    let mongoService = MongoService()
    let storageService = StorageService()
    let metricsService: MetricsService
    let schemaService = SchemaService()
    let codeGeneratorService = CodeGeneratorService()
    let importExportService = ImportExportService()
    let dumpRestoreService = DumpRestoreService()

    // MARK: - Connection State

    var isConnected = false
    var connectionName = ""
    var connectionURI = ""
    var savedConnections: [ConnectionModel] = []
    var isConnecting = false
    var connectionError: String?

    // MARK: - Navigation & Database Tree

    var databases: [String] = []
    var expandedDatabases: Set<String> = []
    var collections: [String: [String]] = [:]

    // MARK: - Tabs

    var tabs: [TabState] = [TabState()]
    var activeTabIndex: Int = 0
    var activeTab: TabState {
        get { tabs[activeTabIndex] }
        set { tabs[activeTabIndex] = newValue }
    }

    // MARK: - Documents (for current tab's explorer)

    var documents: [[String: Any]] = []
    var documentCount: Int = 0
    var isLoading = false
    var error: String?

    // MARK: - Query Log

    var queryLog: [QueryLogEntry] = []
    var savedQueries: [SavedQuery] = []

    // MARK: - Aggregation (for current tab)

    var pipelineStages: [PipelineStage] = [PipelineStage()]
    var aggregationResults: [[String: Any]] = []
    var aggregationError: String?
    var savedPipelines: [SavedPipeline] = []
    var allowDiskUse: Bool = false
    var aggregationResultLimit: Int = 100
    var aggregationTruncated: Bool = false
    /// Per-stage preview output, keyed by stage UUID. Shows first N docs from running
    /// the pipeline up to and including that stage.
    var stagePreviews: [UUID: [[String: Any]]] = [:]
    /// Stages currently generating a preview (for spinner UI).
    var stagePreviewInProgress: Set<UUID> = []
    /// Per-stage preview error (keyed by stage UUID).
    var stagePreviewErrors: [UUID: String] = [:]
    /// Running aggregation task, for cancellation.
    private var runningAggregationTask: Task<Void, Never>?

    // MARK: - Metrics

    var serverMetrics: ServerMetrics?
    var metricsHistory: [MetricsSnapshot] = []
    var currentOps: [CurrentOp] = []

    // MARK: - Investigate

    var slowQueries: [SlowQueryEntry] = []
    var indexes: [[String: Any]] = []
    var profilingLevel: Int = 0
    var slowMs: Int = 100

    // MARK: - Schema

    var schemaFields: [SchemaField] = []
    var isAnalyzingSchema = false

    // MARK: - Init

    init() {
        metricsService = MetricsService(mongoService: mongoService)
        loadPersistedData()
    }

    // MARK: - Connection

    func connect(uri: String, name: String) async {
        isConnecting = true
        connectionError = nil
        error = nil

        do {
            try await mongoService.connect(uri: uri)
            isConnected = true
            connectionName = name
            connectionURI = uri

            // Save to recent connections
            let connection = ConnectionModel(name: name, uri: uri, lastUsed: Date())
            storageService.addConnection(connection)
            savedConnections = storageService.loadConnections()

            await loadDatabases()
        } catch {
            connectionError = error.localizedDescription
            self.error = error.localizedDescription
            isConnected = false
        }

        isConnecting = false
    }

    func disconnect() {
        stopMetricsPolling()
        mongoService.disconnect()

        isConnected = false
        connectionName = ""
        connectionURI = ""
        databases = []
        expandedDatabases = []
        collections = [:]
        documents = []
        documentCount = 0
        error = nil
        connectionError = nil
        serverMetrics = nil
        metricsHistory = []
        currentOps = []
        slowQueries = []
        indexes = []
        schemaFields = []
        aggregationResults = []
        aggregationError = nil
        pipelineStages = [PipelineStage()]

        // Reset tabs
        tabs = [TabState()]
        activeTabIndex = 0
    }

    func loadPersistedData() {
        savedConnections = storageService.loadConnections()
        queryLog = storageService.loadQueryLog()
        savedQueries = storageService.loadSavedQueries()
        savedPipelines = storageService.loadSavedPipelines()
    }

    // MARK: - Database / Collection Navigation

    func loadDatabases() async {
        do {
            databases = try await mongoService.getDatabases()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadCollections(for database: String) async {
        do {
            let colls = try await mongoService.getCollections(database: database)
            collections[database] = colls
        } catch {
            self.error = error.localizedDescription
        }
    }

    func toggleDatabaseExpanded(_ database: String) async {
        if expandedDatabases.contains(database) {
            expandedDatabases.remove(database)
        } else {
            expandedDatabases.insert(database)
            await loadCollections(for: database)
        }
    }

    func selectDatabase(_ database: String) async {
        activeTab.selectedDatabase = database
        activeTab.selectedCollection = nil
        activeTab.skip = 0
        documents = []
        documentCount = 0
        await loadCollections(for: database)
    }

    func selectCollection(_ collection: String) async {
        activeTab.selectedCollection = collection
        activeTab.skip = 0
        await refreshDocuments()
    }

    func createDatabase(name: String) async {
        do {
            // MongoDB creates databases lazily; insert a doc to materialize the database
            try await mongoService.insertDocument(
                database: name,
                collection: "_mongocompass_init",
                document: "{\"_created\": true}"
            )
            await loadDatabases()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func dropDatabase(name: String) async {
        do {
            try await mongoService.dropDatabase(database: name)
            await loadDatabases()
            expandedDatabases.remove(name)
            collections.removeValue(forKey: name)

            if activeTab.selectedDatabase == name {
                activeTab.selectedDatabase = nil
                activeTab.selectedCollection = nil
                documents = []
                documentCount = 0
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func createCollection(name: String, inDatabase db: String, capped: Bool = false, size: Int? = nil) async {
        do {
            try await mongoService.createCollection(database: db, name: name, capped: capped, size: size)
            await loadCollections(for: db)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func dropCollection(name: String, inDatabase db: String) async {
        do {
            try await mongoService.dropCollection(database: db, collection: name)
            await loadCollections(for: db)

            if activeTab.selectedDatabase == db && activeTab.selectedCollection == name {
                activeTab.selectedCollection = nil
                documents = []
                documentCount = 0
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Documents (Explorer)

    func refreshDocuments() async {
        guard let database = activeTab.selectedDatabase,
              let collection = activeTab.selectedCollection else {
            documents = []
            documentCount = 0
            return
        }

        isLoading = true
        error = nil

        let startTime = Date()

        do {
            let filterStr = activeTab.filter.isEmpty ? nil : activeTab.filter
            let sortStr = activeTab.sort.isEmpty ? nil : activeTab.sort
            let projStr = activeTab.projection.isEmpty ? nil : activeTab.projection

            let results = try await mongoService.getDocuments(
                database: database,
                collection: collection,
                filter: filterStr,
                sort: sortStr,
                projection: projStr,
                skip: activeTab.skip,
                limit: activeTab.limit
            )

            documents = results

            // Get document count using collStats command
            let countResult = try await mongoService.runCommand(
                database: database,
                command: ["count": collection, "query": MongoService.parseJSON(filterStr) as Any]
            )
            if let n = countResult["n"] as? Int {
                documentCount = n
            } else {
                documentCount = results.count
            }

            let executionTimeMs = Int(Date().timeIntervalSince(startTime) * 1000)

            // Log the query
            let logEntry = QueryLogEntry(
                operationType: .find,
                database: database,
                collection: collection,
                query: filterStr ?? "{}",
                executionTimeMs: executionTimeMs,
                docsReturned: results.count
            )
            logQuery(logEntry)
        } catch {
            self.error = error.localizedDescription
            documents = []
            documentCount = 0
        }

        isLoading = false
    }

    func insertDocument(_ json: String) async {
        guard let database = activeTab.selectedDatabase,
              let collection = activeTab.selectedCollection else {
            self.error = "No database or collection selected."
            return
        }

        let startTime = Date()

        do {
            let inserted = try await mongoService.insertDocument(
                database: database,
                collection: collection,
                document: json
            )

            let executionTimeMs = Int(Date().timeIntervalSince(startTime) * 1000)
            let logEntry = QueryLogEntry(
                operationType: .insert,
                database: database,
                collection: collection,
                query: json,
                executionTimeMs: executionTimeMs,
                docsReturned: 1
            )
            logQuery(logEntry)

            _ = inserted
            await refreshDocuments()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateDocument(id: String, json: String) async {
        guard let database = activeTab.selectedDatabase,
              let collection = activeTab.selectedCollection else {
            self.error = "No database or collection selected."
            return
        }

        let startTime = Date()

        do {
            let filterJSON = "{\"_id\": \"\(id)\"}"
            try await mongoService.updateDocument(
                database: database,
                collection: collection,
                filter: filterJSON,
                update: json
            )

            let executionTimeMs = Int(Date().timeIntervalSince(startTime) * 1000)
            let logEntry = QueryLogEntry(
                operationType: .update,
                database: database,
                collection: collection,
                query: "filter: \(filterJSON), update: \(json)",
                executionTimeMs: executionTimeMs,
                docsReturned: 0
            )
            logQuery(logEntry)

            await refreshDocuments()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteDocument(id: String) async {
        guard let database = activeTab.selectedDatabase,
              let collection = activeTab.selectedCollection else {
            self.error = "No database or collection selected."
            return
        }

        let startTime = Date()

        do {
            let filterJSON = "{\"_id\": \"\(id)\"}"
            try await mongoService.deleteDocument(
                database: database,
                collection: collection,
                filter: filterJSON
            )

            let executionTimeMs = Int(Date().timeIntervalSince(startTime) * 1000)
            let logEntry = QueryLogEntry(
                operationType: .delete,
                database: database,
                collection: collection,
                query: filterJSON,
                executionTimeMs: executionTimeMs,
                docsReturned: 0
            )
            logQuery(logEntry)

            await refreshDocuments()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func nextPage() {
        activeTab.skip += activeTab.limit
        Task {
            await refreshDocuments()
        }
    }

    func previousPage() {
        activeTab.skip = max(0, activeTab.skip - activeTab.limit)
        Task {
            await refreshDocuments()
        }
    }

    func getCollectionStats() async -> [String: Any]? {
        guard let database = activeTab.selectedDatabase,
              let collection = activeTab.selectedCollection else {
            return nil
        }

        do {
            return try await mongoService.getCollStats(database: database, collection: collection)
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    // MARK: - Tabs

    func addTab() {
        guard tabs.count < 8 else { return }

        let newTab = TabState(
            selectedDatabase: activeTab.selectedDatabase,
            selectedCollection: activeTab.selectedCollection
        )
        tabs.append(newTab)
        activeTabIndex = tabs.count - 1
    }

    func closeTab(at index: Int) {
        guard tabs.count > 1 else { return }
        guard index >= 0 && index < tabs.count else { return }

        tabs.remove(at: index)

        if activeTabIndex >= tabs.count {
            activeTabIndex = tabs.count - 1
        } else if activeTabIndex > index {
            activeTabIndex -= 1
        } else if activeTabIndex == index {
            activeTabIndex = min(activeTabIndex, tabs.count - 1)
        }
    }

    func closeCurrentTab() {
        closeTab(at: activeTabIndex)
    }

    func switchTab(to index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        activeTabIndex = index

        if activeTab.selectedCollection != nil {
            Task {
                await refreshDocuments()
            }
        }
    }

    // MARK: - Query Log

    func logQuery(_ entry: QueryLogEntry) {
        queryLog.insert(entry, at: 0)
        storageService.addLogEntry(entry)
    }

    func toggleQueryFavorite(_ entry: QueryLogEntry) {
        if let index = queryLog.firstIndex(where: { $0.id == entry.id }) {
            queryLog[index].isFavorite.toggle()
        }
        storageService.toggleFavorite(id: entry.id)
    }

    func clearQueryLog() {
        queryLog.removeAll()
        storageService.clearLog()
    }

    func replayQuery(_ entry: QueryLogEntry) async {
        // Find the tab or set the current tab
        activeTab.selectedDatabase = entry.database
        activeTab.selectedCollection = entry.collection
        activeTab.filter = entry.query
        activeTab.skip = 0

        // Expand the database in the sidebar
        if !expandedDatabases.contains(entry.database) {
            expandedDatabases.insert(entry.database)
            await loadCollections(for: entry.database)
        }

        await refreshDocuments()
    }

    // MARK: - Saved Queries

    func saveCurrentQuery(name: String) {
        guard let database = activeTab.selectedDatabase,
              let collection = activeTab.selectedCollection else { return }

        let query = SavedQuery(
            name: name,
            database: database,
            collection: collection,
            filter: activeTab.filter,
            sort: activeTab.sort,
            projection: activeTab.projection
        )

        savedQueries.insert(query, at: 0)
        storageService.saveQuery(query)
    }

    func deleteQuery(id: UUID) {
        savedQueries.removeAll { $0.id == id }
        storageService.removeQuery(id: id)
    }

    func loadQuery(_ query: SavedQuery) async {
        activeTab.selectedDatabase = query.database
        activeTab.selectedCollection = query.collection
        activeTab.filter = query.filter
        activeTab.sort = query.sort
        activeTab.projection = query.projection
        activeTab.skip = 0

        if !expandedDatabases.contains(query.database) {
            expandedDatabases.insert(query.database)
            await loadCollections(for: query.database)
        }

        await refreshDocuments()
    }

    // MARK: - Aggregation

    func addPipelineStage() {
        pipelineStages.append(PipelineStage())
    }

    func removePipelineStage(at index: Int) {
        guard index >= 0 && index < pipelineStages.count else { return }
        let removedId = pipelineStages[index].id
        pipelineStages.remove(at: index)
        if pipelineStages.isEmpty {
            pipelineStages.append(PipelineStage())
        }
        stagePreviews.removeValue(forKey: removedId)
        stagePreviewErrors.removeValue(forKey: removedId)
        stagePreviewInProgress.remove(removedId)
    }

    func duplicatePipelineStage(at index: Int) {
        guard index >= 0 && index < pipelineStages.count else { return }
        let source = pipelineStages[index]
        let copy = PipelineStage(type: source.type, body: source.body, enabled: source.enabled, collapsed: source.collapsed)
        pipelineStages.insert(copy, at: index + 1)
    }

    func movePipelineStage(from source: IndexSet, to destination: Int) {
        pipelineStages.move(fromOffsets: source, toOffset: destination)
    }

    func movePipelineStageUp(at index: Int) {
        guard index > 0 && index < pipelineStages.count else { return }
        pipelineStages.swapAt(index, index - 1)
    }

    func movePipelineStageDown(at index: Int) {
        guard index >= 0 && index < pipelineStages.count - 1 else { return }
        pipelineStages.swapAt(index, index + 1)
    }

    func runAggregation() async {
        guard let database = activeTab.selectedDatabase,
              let collection = activeTab.selectedCollection else {
            aggregationError = "No database or collection selected."
            return
        }

        aggregationError = nil
        aggregationTruncated = false
        isLoading = true

        do {
            let pipeline = try buildPipeline(from: pipelineStages.filter { $0.enabled })
            let cap = aggregationResultLimit
            let startTime = Date()

            let results = try await mongoService.runAggregation(
                database: database,
                collection: collection,
                pipeline: pipeline,
                allowDiskUse: allowDiskUse,
                resultLimit: cap > 0 ? cap : nil
            )

            aggregationResults = results
            aggregationTruncated = cap > 0 && results.count >= cap

            let executionTimeMs = Int(Date().timeIntervalSince(startTime) * 1000)
            let logEntry = QueryLogEntry(
                operationType: .aggregate,
                database: database,
                collection: collection,
                query: pipelineStagesToJSON(),
                executionTimeMs: executionTimeMs,
                docsReturned: results.count
            )
            logQuery(logEntry)
        } catch is CancellationError {
            aggregationError = "Aggregation cancelled."
            aggregationResults = []
        } catch {
            aggregationError = error.localizedDescription
            aggregationResults = []
        }

        isLoading = false
    }

    /// Preview output of the pipeline up to and including the stage at `index`.
    /// Runs the enabled stages 0...index with a trailing $limit and stores the
    /// result in `stagePreviews` keyed by the stage's UUID.
    func previewStage(at index: Int, limit: Int = 3) async {
        guard index >= 0 && index < pipelineStages.count else { return }
        guard let database = activeTab.selectedDatabase,
              let collection = activeTab.selectedCollection else {
            return
        }

        let stageId = pipelineStages[index].id
        stagePreviewInProgress.insert(stageId)
        stagePreviewErrors.removeValue(forKey: stageId)

        do {
            // Take all stages up to and including this one, honoring enable state.
            let upTo = Array(pipelineStages.prefix(index + 1)).filter { $0.enabled }
            guard !upTo.isEmpty else {
                stagePreviewInProgress.remove(stageId)
                return
            }
            var pipeline = try buildPipeline(from: upTo)
            // Cap preview output at `limit` docs to keep the UI snappy.
            pipeline.append(["$limit": limit])

            let results = try await mongoService.runAggregation(
                database: database,
                collection: collection,
                pipeline: pipeline,
                allowDiskUse: allowDiskUse,
                resultLimit: limit
            )
            stagePreviews[stageId] = results
        } catch {
            stagePreviewErrors[stageId] = error.localizedDescription
            stagePreviews.removeValue(forKey: stageId)
        }

        stagePreviewInProgress.remove(stageId)
    }

    func clearStagePreview(stageId: UUID) {
        stagePreviews.removeValue(forKey: stageId)
        stagePreviewErrors.removeValue(forKey: stageId)
    }

    /// Build a [[String: Any]] pipeline from a list of stages, parsing each body as JSON.
    private func buildPipeline(from stages: [PipelineStage]) throws -> [[String: Any]] {
        var pipeline: [[String: Any]] = []
        for stage in stages {
            let bodyData = stage.body.data(using: .utf8) ?? Data()
            let parsedBody = try JSONSerialization.jsonObject(with: bodyData, options: .fragmentsAllowed)
            pipeline.append([stage.type: parsedBody])
        }
        return pipeline
    }

    func savePipeline(name: String) {
        guard let database = activeTab.selectedDatabase,
              let collection = activeTab.selectedCollection else { return }

        // Overwrite if a saved pipeline with the same name already exists for this db+collection.
        let existing = savedPipelines.first {
            $0.name == name && $0.database == database && $0.collection == collection
        }

        let pipeline = SavedPipeline(
            id: existing?.id ?? UUID(),
            name: name,
            database: database,
            collection: collection,
            stages: pipelineStages
        )

        if let _ = existing {
            savedPipelines.removeAll { $0.id == pipeline.id }
        }
        savedPipelines.insert(pipeline, at: 0)
        storageService.savePipeline(pipeline)
    }

    func deletePipeline(id: UUID) {
        savedPipelines.removeAll { $0.id == id }
        storageService.removePipeline(id: id)
    }

    func loadPipeline(_ pipeline: SavedPipeline) {
        activeTab.selectedDatabase = pipeline.database
        activeTab.selectedCollection = pipeline.collection
        pipelineStages = pipeline.stages
        if pipelineStages.isEmpty {
            pipelineStages = [PipelineStage()]
        }
    }

    /// Serialize the current pipeline stages to a JSON string for logging.
    private func pipelineStagesToJSON() -> String {
        let enabledStages = pipelineStages.filter { $0.enabled }
        let stageStrings = enabledStages.map { "{\"\($0.type)\": \($0.body)}" }
        return "[\(stageStrings.joined(separator: ", "))]"
    }

    // MARK: - Metrics

    func startMetricsPolling() {
        metricsService.start()
    }

    func stopMetricsPolling() {
        metricsService.stop()
    }

    func refreshMetrics() async {
        do {
            serverMetrics = try await mongoService.getServerStatus()
            metricsHistory = metricsService.history
            currentOps = try await mongoService.getCurrentOps()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func killOp(opId: Int) async {
        do {
            try await mongoService.killOp(opId: opId)
            currentOps = try await mongoService.getCurrentOps()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Investigate

    func setProfilingLevel(_ level: Int, slowMs: Int) async {
        guard let database = activeTab.selectedDatabase else {
            self.error = "No database selected."
            return
        }

        do {
            try await mongoService.setProfilingLevel(database: database, level: level, slowMs: slowMs)
            self.profilingLevel = level
            self.slowMs = slowMs
        } catch {
            self.error = error.localizedDescription
        }
    }

    func fetchSlowQueries() async {
        guard let database = activeTab.selectedDatabase else {
            self.error = "No database selected."
            return
        }

        do {
            slowQueries = try await mongoService.getSlowQueries(database: database)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func fetchIndexes() async {
        guard let database = activeTab.selectedDatabase,
              let collection = activeTab.selectedCollection else {
            self.error = "No database or collection selected."
            return
        }

        do {
            indexes = try await mongoService.getIndexes(database: database, collection: collection)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func createIndex(fields: [String: Int], unique: Bool = false, sparse: Bool = false) async {
        guard let database = activeTab.selectedDatabase,
              let collection = activeTab.selectedCollection else {
            self.error = "No database or collection selected."
            return
        }

        do {
            // Generate a name from the fields
            let nameParts = fields.map { "\($0.key)_\($0.value)" }
            let indexName = nameParts.joined(separator: "_")

            // Convert [String: Int] to [String: Any] for the service
            let keysDict: [String: Any] = fields.reduce(into: [:]) { result, pair in
                result[pair.key] = pair.value
            }

            try await mongoService.createIndex(
                database: database,
                collection: collection,
                name: indexName,
                keys: keysDict,
                unique: unique,
                sparse: sparse
            )

            await fetchIndexes()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func dropIndex(name: String) async {
        guard let database = activeTab.selectedDatabase,
              let collection = activeTab.selectedCollection else {
            self.error = "No database or collection selected."
            return
        }

        do {
            try await mongoService.dropIndex(
                database: database,
                collection: collection,
                indexName: name
            )
            await fetchIndexes()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func explainCurrentQuery() async -> [String: Any]? {
        guard let database = activeTab.selectedDatabase,
              let collection = activeTab.selectedCollection else {
            self.error = "No database or collection selected."
            return nil
        }

        do {
            let filterStr = activeTab.filter.isEmpty ? nil : activeTab.filter
            return try await mongoService.explainFind(
                database: database,
                collection: collection,
                filter: filterStr
            )
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    // MARK: - Schema

    func analyzeSchema(sampleSize: Int = 100) async {
        guard let database = activeTab.selectedDatabase,
              let collection = activeTab.selectedCollection else {
            self.error = "No database or collection selected."
            return
        }

        isAnalyzingSchema = true
        error = nil

        do {
            let filterStr = activeTab.filter.isEmpty ? nil : activeTab.filter
            let sampleDocs = try await mongoService.sampleDocumentsBSON(
                database: database,
                collection: collection,
                filter: filterStr,
                count: sampleSize
            )
            schemaFields = schemaService.analyzeSchema(documents: sampleDocs)
        } catch {
            self.error = error.localizedDescription
            schemaFields = []
        }

        isAnalyzingSchema = false
    }

    // MARK: - Code Generation

    func generateFindCode(language: CodeLanguage) -> String {
        let database = activeTab.selectedDatabase ?? ""
        let collection = activeTab.selectedCollection ?? ""

        return codeGeneratorService.generateFindCode(
            database: database,
            collection: collection,
            filter: activeTab.filter,
            sort: activeTab.sort,
            projection: activeTab.projection,
            skip: activeTab.skip,
            limit: activeTab.limit,
            language: language
        )
    }

    func generateAggregationCode(language: CodeLanguage) -> String {
        let database = activeTab.selectedDatabase ?? ""
        let collection = activeTab.selectedCollection ?? ""
        let pipelineJSON = pipelineStagesToJSON()

        return codeGeneratorService.generateAggregationCode(
            database: database,
            collection: collection,
            pipeline: pipelineJSON,
            language: language
        )
    }

    // MARK: - Export / Import

    func exportDocuments(format: ExportFormat, to url: URL) async throws {
        guard !documents.isEmpty else {
            throw ImportExportError.invalidData("No documents to export.")
        }
        try importExportService.exportDocuments(documents, format: format, to: url)
    }

    func importDocuments(format: ImportFormat, from url: URL) async throws {
        guard let database = activeTab.selectedDatabase,
              let collection = activeTab.selectedCollection else {
            throw ImportExportError.invalidData("No database or collection selected.")
        }

        let importedDocs = try importExportService.importDocuments(from: url, format: format)

        for doc in importedDocs {
            let jsonData = try JSONSerialization.data(withJSONObject: doc, options: [])
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw ImportExportError.invalidData("Failed to convert document to JSON string.")
            }
            try await mongoService.insertDocument(
                database: database,
                collection: collection,
                document: jsonString
            )
        }

        await refreshDocuments()
    }
}
