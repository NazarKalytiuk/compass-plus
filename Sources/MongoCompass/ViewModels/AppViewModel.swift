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
    /// Captured DNS/TLS/Auth phases from the most recent failed connect.
    /// Cleared on a successful connection.
    var lastDiagnostics: ConnectionDiagnostics?

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
    var savedCommands: [SavedCommand] = []

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
    var indexRecommendations: [IndexRecommendation] = []
    /// Set of `IndexRecommendation.id`s the user has dismissed. Survives
    /// for the lifetime of the connection so dismissed items don't
    /// re-appear after a re-analyse.
    private var dismissedRecommendationKeys: Set<String> = []
    var isComputingRecommendations: Bool = false
    var profilingLevel: Int = 0
    var slowMs: Int = 100

    /// Sidebar Investigate nav-row badge count: slow queries + currently
    /// running ops that have exceeded 1 second.
    var investigateBadgeCount: Int {
        slowQueries.count + currentOps.filter { $0.executionTimeMs > 1000 }.count
    }

    // MARK: - Schema

    var schemaFields: [SchemaField] = []
    var isAnalyzingSchema = false

    // MARK: - Init

    init() {
        metricsService = MetricsService(mongoService: mongoService)
        loadPersistedData()
    }

    // MARK: - Connection

    func connect(uri: String, name: String, save: Bool = true) async {
        isConnecting = true
        connectionError = nil
        error = nil

        do {
            try await mongoService.connect(uri: uri)
            isConnected = true
            connectionName = name
            connectionURI = uri
            lastDiagnostics = nil

            // Recents are gated by the Save-connection toggle so one-off
            // probes don't pollute history.
            if save {
                let connection = ConnectionModel(name: name, uri: uri, lastUsed: Date())
                storageService.addConnection(connection)
                savedConnections = storageService.loadConnections()
            }

            await loadDatabases()
        } catch {
            connectionError = error.localizedDescription
            self.error = error.localizedDescription
            isConnected = false
            // Run a diagnose pass so ConnectView's failure card can show
            // which phase actually broke. Best-effort; never re-throws.
            lastDiagnostics = await mongoService.diagnose(uri: uri)
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
        indexRecommendations = []
        dismissedRecommendationKeys = []
        isComputingRecommendations = false
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
        savedCommands = storageService.loadSavedCommands()
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

            // Best-effort explain so slow queries surface plan + docsExamined
            // in the log. Falls back silently if explain isn't permitted on
            // this connection or the server omits executionStats.
            var plan: String?
            var examined: Int?
            if let explain = try? await mongoService.explainFind(
                database: database, collection: collection, filter: filterStr
            ) {
                plan = Self.extractWinningStage(from: explain)
                examined = Self.extractExamined(from: explain)
            }

            let logEntry = QueryLogEntry(
                operationType: .find,
                database: database,
                collection: collection,
                query: filterStr ?? "{}",
                executionTimeMs: executionTimeMs,
                docsReturned: results.count,
                docsExamined: examined,
                plan: plan,
                client: "compass+"
            )
            logQuery(logEntry)
        } catch {
            self.error = error.localizedDescription
            documents = []
            documentCount = 0
            let executionTimeMs = Int(Date().timeIntervalSince(startTime) * 1000)
            let filterStr = activeTab.filter.isEmpty ? "{}" : activeTab.filter
            let logEntry = QueryLogEntry(
                operationType: .find,
                database: database,
                collection: collection,
                query: filterStr,
                executionTimeMs: executionTimeMs,
                docsReturned: 0,
                client: "compass+",
                errorMessage: error.localizedDescription
            )
            logQuery(logEntry)
        }

        isLoading = false
    }

    /// Walk the `queryPlanner.winningPlan` tree and return the outermost
    /// stage name (e.g. "IXSCAN", "COLLSCAN", "FETCH").
    private static func extractWinningStage(from explain: [String: Any]) -> String? {
        guard let qp = explain["queryPlanner"] as? [String: Any],
              let wp = qp["winningPlan"] as? [String: Any] else { return nil }
        if let stage = wp["stage"] as? String { return stage }
        return nil
    }

    /// Read totalDocsExamined out of `executionStats`. Absent on default
    /// verbosity (queryPlanner-only) — returns nil in that case.
    private static func extractExamined(from explain: [String: Any]) -> Int? {
        guard let es = explain["executionStats"] as? [String: Any] else { return nil }
        if let n = es["totalDocsExamined"] as? Int { return n }
        if let n = es["totalKeysExamined"] as? Int { return n }
        return nil
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
                docsReturned: 1,
                client: "compass+"
            )
            logQuery(logEntry)

            _ = inserted
            await refreshDocuments()
        } catch {
            self.error = error.localizedDescription
            let executionTimeMs = Int(Date().timeIntervalSince(startTime) * 1000)
            logQuery(QueryLogEntry(
                operationType: .insert,
                database: database,
                collection: collection,
                query: json,
                executionTimeMs: executionTimeMs,
                docsReturned: 0,
                client: "compass+",
                errorMessage: error.localizedDescription
            ))
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
                docsReturned: 0,
                client: "compass+"
            )
            logQuery(logEntry)

            await refreshDocuments()
        } catch {
            self.error = error.localizedDescription
            let executionTimeMs = Int(Date().timeIntervalSince(startTime) * 1000)
            let filterJSON = "{\"_id\": \"\(id)\"}"
            logQuery(QueryLogEntry(
                operationType: .update,
                database: database,
                collection: collection,
                query: "filter: \(filterJSON), update: \(json)",
                executionTimeMs: executionTimeMs,
                docsReturned: 0,
                client: "compass+",
                errorMessage: error.localizedDescription
            ))
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
                docsReturned: 0,
                client: "compass+"
            )
            logQuery(logEntry)

            await refreshDocuments()
        } catch {
            self.error = error.localizedDescription
            let executionTimeMs = Int(Date().timeIntervalSince(startTime) * 1000)
            let filterJSON = "{\"_id\": \"\(id)\"}"
            logQuery(QueryLogEntry(
                operationType: .delete,
                database: database,
                collection: collection,
                query: filterJSON,
                executionTimeMs: executionTimeMs,
                docsReturned: 0,
                client: "compass+",
                errorMessage: error.localizedDescription
            ))
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

    // MARK: - Saved Shell Commands

    /// Persist a mongosh expression for quick recall in the Shell view.
    /// Trims whitespace; ignores empty payloads.
    func saveShellCommand(name: String, command: String, category: String = "Custom") {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else { return }
        let resolvedName = trimmedName.isEmpty ? Self.defaultCommandName(for: trimmedCommand) : trimmedName
        let resolvedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Custom"
            : category.trimmingCharacters(in: .whitespacesAndNewlines)

        let entry = SavedCommand(
            name: resolvedName,
            command: trimmedCommand,
            category: resolvedCategory
        )
        savedCommands.insert(entry, at: 0)
        storageService.saveCommand(entry)
    }

    func removeSavedCommand(id: UUID) {
        savedCommands.removeAll { $0.id == id }
        storageService.removeCommand(id: id)
    }

    /// Mark a saved command as used. Updates `lastUsedAt` and re-sorts
    /// it to the top so the drawer feels recency-ordered.
    func markCommandUsed(id: UUID) {
        guard let index = savedCommands.firstIndex(where: { $0.id == id }) else { return }
        savedCommands[index].lastUsedAt = Date()
        let updated = savedCommands.remove(at: index)
        savedCommands.insert(updated, at: 0)
        storageService.updateCommandLastUsed(id: id)
    }

    /// Best-effort short label derived from the command body when the
    /// user doesn't supply a name.
    private static func defaultCommandName(for command: String) -> String {
        // Take the first non-empty line, strip leading prefixes, cap at 32 chars.
        let firstLine = command
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? command
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        if trimmed.count <= 32 { return trimmed }
        return String(trimmed.prefix(31)) + "…"
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

        let startTime = Date()
        do {
            let pipeline = try buildPipeline(from: pipelineStages.filter { $0.enabled })
            let cap = aggregationResultLimit

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
                docsReturned: results.count,
                client: "compass+"
            )
            logQuery(logEntry)

            // Best-effort: populate per-stage timing / outCount / index. Stays
            // silent on permission errors or non-explainable terminal stages
            // ($out, $merge) — those keep their existing nil values.
            await runPipelineIncrementally(database: database, collection: collection)
        } catch is CancellationError {
            aggregationError = "Aggregation cancelled."
            aggregationResults = []
        } catch {
            aggregationError = error.localizedDescription
            aggregationResults = []
            let executionTimeMs = Int(Date().timeIntervalSince(startTime) * 1000)
            logQuery(QueryLogEntry(
                operationType: .aggregate,
                database: database,
                collection: collection,
                query: pipelineStagesToJSON(),
                executionTimeMs: executionTimeMs,
                docsReturned: 0,
                client: "compass+",
                errorMessage: error.localizedDescription
            ))
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

    /// Walk the enabled stages and populate `outCount` / `ms` / `usedIndex`
    /// from a single executionStats-verbosity explain. Failures are swallowed
    /// — meta fields stay nil and the stage row simply shows no extra info.
    func runPipelineIncrementally(database: String, collection: String) async {
        let enabledIndices = pipelineStages.indices.filter { pipelineStages[$0].enabled }
        guard !enabledIndices.isEmpty else { return }

        // Build the pipeline once; explain only succeeds when every stage
        // parses, so a single broken stage skips the whole pass.
        let enabledStages = enabledIndices.map { pipelineStages[$0] }
        let pipeline: [[String: Any]]
        do {
            pipeline = try buildPipeline(from: enabledStages)
        } catch {
            return
        }

        let explain: [String: Any]
        do {
            explain = try await mongoService.explainAggregation(
                database: database, collection: collection, pipeline: pipeline
            )
        } catch {
            return
        }

        let parsed = Self.parseAggregationExplainStages(explain)
        // Walk side-by-side: parsed[i] corresponds to enabled stage at
        // enabledIndices[i]. Disabled stages keep their previous metadata.
        for (i, idx) in enabledIndices.enumerated() {
            guard i < parsed.count else { break }
            pipelineStages[idx].ms = parsed[i].ms
            pipelineStages[idx].outCount = parsed[i].outCount
            pipelineStages[idx].usedIndex = parsed[i].usedIndex
        }
    }

    private struct StageMeta {
        var ms: Double?
        var outCount: Int?
        var usedIndex: String?
    }

    /// Pull per-stage `executionTimeMillisEstimate` / `nReturned` /
    /// `winningPlan.indexName` from an aggregation explain at executionStats
    /// verbosity. Standalone-only path; shard envelopes fall back to all-nil.
    private static func parseAggregationExplainStages(_ explain: [String: Any]) -> [StageMeta] {
        guard let stages = explain["stages"] as? [[String: Any]] else { return [] }
        return stages.map { stage in
            var meta = StageMeta()
            if let cursor = stage["$cursor"] as? [String: Any] {
                if let es = cursor["executionStats"] as? [String: Any] {
                    if let t = es["executionTimeMillis"] as? Int { meta.ms = Double(t) }
                    else if let t = es["executionTimeMillis"] as? Double { meta.ms = t }
                    if let n = es["nReturned"] as? Int { meta.outCount = n }
                }
                if let qp = cursor["queryPlanner"] as? [String: Any],
                   let wp = qp["winningPlan"] as? [String: Any] {
                    meta.usedIndex = Self.indexNameDeep(in: wp)
                }
            } else {
                if let t = stage["executionTimeMillisEstimate"] as? Int { meta.ms = Double(t) }
                else if let t = stage["executionTimeMillisEstimate"] as? Double { meta.ms = t }
                if let n = stage["nReturned"] as? Int { meta.outCount = n }
            }
            return meta
        }
    }

    /// `winningPlan.indexName` lives at the IXSCAN stage which may be wrapped
    /// in FETCH/SHARD_MERGE/etc. — walk inputStage links until we find one.
    private static func indexNameDeep(in plan: [String: Any]) -> String? {
        if let name = plan["indexName"] as? String { return name }
        if let inner = plan["inputStage"] as? [String: Any] {
            return indexNameDeep(in: inner)
        }
        return nil
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

    /// Issue `killOp` for every currentOp running longer than `thresholdMs`.
    /// Errors from individual kills are aggregated into `self.error`; the
    /// list refresh runs once at the end regardless of partial failure.
    func killAllSlowOps(thresholdMs: Int) async {
        let targets = currentOps.filter { $0.executionTimeMs >= thresholdMs }
        var failures: [String] = []
        for op in targets {
            do {
                try await mongoService.killOp(opId: op.id)
            } catch {
                failures.append("opid \(op.id): \(error.localizedDescription)")
            }
        }
        do {
            currentOps = try await mongoService.getCurrentOps()
        } catch {
            failures.append("refresh: \(error.localizedDescription)")
        }
        if !failures.isEmpty {
            self.error = "killAllSlow encountered errors: " + failures.joined(separator: "; ")
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

    /// Compute index recommendations for the active database. Loads
    /// recent slow queries from `system.profile`, gathers existing
    /// indexes for each unique namespace observed, and runs the pure
    /// `IndexRecommendationService.recommend` engine.
    ///
    /// Filters out anything the user has previously dismissed in this
    /// session so the list converges on actionable suggestions.
    func computeIndexRecommendations() async {
        guard let database = activeTab.selectedDatabase else {
            self.error = "No database selected."
            return
        }
        isComputingRecommendations = true
        defer { isComputingRecommendations = false }
        do {
            let queries = try await mongoService.getSlowQueries(database: database, limit: 200)
            slowQueries = queries

            // Look up existing indexes once per distinct namespace so we
            // don't re-fetch on every recommendation candidate.
            var byNamespace: [String: [[String: Any]]] = [:]
            let namespaces = Set(queries.map(\.namespace).filter { !$0.isEmpty })
            for ns in namespaces {
                let parts = ns.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { continue }
                let db = String(parts[0])
                let coll = String(parts[1])
                if coll.contains("system.") || db == "config" || db == "local" { continue }
                do {
                    byNamespace[ns] = try await mongoService.getIndexes(database: db, collection: coll)
                } catch {
                    // A single namespace failing shouldn't abort the run.
                    continue
                }
            }

            let candidates = IndexRecommendationService.recommend(
                slowQueries: queries,
                existingIndexesByNamespace: byNamespace
            )
            indexRecommendations = candidates.filter {
                !dismissedRecommendationKeys.contains(recommendationKey($0))
            }
        } catch {
            self.error = "Index analysis failed: \(error.localizedDescription)"
        }
    }

    /// Issue `createIndex` on the namespace named in the recommendation,
    /// then refresh recommendations so the newly-built index is reflected
    /// in subsequent runs.
    func createRecommendedIndex(_ rec: IndexRecommendation) async {
        let parts = rec.namespace.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            self.error = "Recommendation has malformed namespace: \(rec.namespace)"
            return
        }
        let db = String(parts[0])
        let coll = String(parts[1])
        do {
            try await mongoService.createIndex(
                database: db,
                collection: coll,
                name: rec.suggestedName,
                keys: rec.keysDictionary.reduce(into: [String: Any]()) { $0[$1.key] = $1.value },
                unique: false,
                sparse: false
            )
            // Drop just this one from the list — re-running analysis is
            // user-initiated.
            indexRecommendations.removeAll { $0.id == rec.id }
            // If the user happens to have this collection open, refresh
            // its visible index list.
            if activeTab.selectedDatabase == db && activeTab.selectedCollection == coll {
                await fetchIndexes()
            }
        } catch {
            self.error = "Failed to create index: \(error.localizedDescription)"
        }
    }

    /// Hide a recommendation. Persists for the connection lifetime via
    /// a content-based key so re-running analysis won't surface it again.
    func dismissRecommendation(_ rec: IndexRecommendation) {
        dismissedRecommendationKeys.insert(recommendationKey(rec))
        indexRecommendations.removeAll { $0.id == rec.id }
    }

    private func recommendationKey(_ rec: IndexRecommendation) -> String {
        rec.namespace + "::" + rec.spec.map { "\($0.field)_\($0.direction)" }.joined(separator: ",")
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

    /// Snapshot diff (path-level) for the schema view's stat cards. Populated
    /// alongside `schemaFields` after each analyzeSchema pass.
    var schemaAddedFields: [String] = []
    var schemaRemovedFields: [String] = []

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

            // Compute diff against the previous snapshot for this namespace
            // and persist the new one.
            let namespace = "\(database).\(collection)"
            let currentPaths = Self.flattenSchemaPaths(schemaFields)
            let previousPaths = storageService.loadSchemaSnapshot(for: namespace) ?? []
            if previousPaths.isEmpty {
                schemaAddedFields = []
                schemaRemovedFields = []
            } else {
                let prevSet = Set(previousPaths)
                let currSet = Set(currentPaths)
                schemaAddedFields = currentPaths.filter { !prevSet.contains($0) }
                schemaRemovedFields = previousPaths.filter { !currSet.contains($0) }
            }
            storageService.saveSchemaSnapshot(currentPaths, for: namespace)
        } catch {
            self.error = error.localizedDescription
            schemaFields = []
            schemaAddedFields = []
            schemaRemovedFields = []
        }

        isAnalyzingSchema = false
    }

    private static func flattenSchemaPaths(_ fields: [SchemaField], prefix: [String] = []) -> [String] {
        var out: [String] = []
        for f in fields {
            let path = prefix + [f.name]
            out.append(path.joined(separator: "."))
            if let nested = f.nestedFields {
                out.append(contentsOf: flattenSchemaPaths(nested, prefix: path))
            }
        }
        return out
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
