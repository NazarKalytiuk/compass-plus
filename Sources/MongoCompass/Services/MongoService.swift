import Foundation
import MongoKitten
import MongoCore

// MARK: - MongoService Errors

enum MongoServiceError: LocalizedError {
    case notConnected
    case invalidJSON(String)
    case commandFailed(String)
    case databaseNotFound(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to MongoDB server."
        case .invalidJSON(let detail):
            return "Invalid JSON: \(detail)"
        case .commandFailed(let detail):
            return "Command failed: \(detail)"
        case .databaseNotFound(let name):
            return "Database not found: \(name)"
        }
    }
}

// MARK: - MongoService

@Observable
final class MongoService: @unchecked Sendable {

    // MARK: Connection State

    private(set) var connectedDatabase: MongoDatabase?
    private(set) var connectionURI: String?

    var isConnected: Bool {
        connectedDatabase != nil
    }

    // MARK: - Connection Management

    func connect(uri: String) async throws {
        // MongoKitten requires a database name in the URI.
        // If the user provides a bare URI like "mongodb://localhost:27017",
        // append "/admin" as the default initial database.
        var effectiveURI = uri
        let settings = try ConnectionSettings(effectiveURI)
        if settings.targetDatabase == nil || settings.targetDatabase?.isEmpty == true {
            // Strip trailing slash if present, then append /admin
            if effectiveURI.hasSuffix("/") {
                effectiveURI += "admin"
            } else {
                effectiveURI += "/admin"
            }
        }
        let db = try await MongoDatabase.connect(to: effectiveURI)
        self.connectedDatabase = db
        self.connectionURI = uri  // store the original URI
    }

    func disconnect() {
        connectedDatabase = nil
        connectionURI = nil
    }

    // MARK: - Database Helpers

    /// Returns a MongoDatabase for the given database name, using the same connection pool.
    private func database(named name: String) throws -> MongoDatabase {
        guard let pool = connectedDatabase?.pool else {
            throw MongoServiceError.notConnected
        }
        return pool[name]
    }

    /// Returns the admin database for running admin commands.
    private func adminDatabase() throws -> MongoDatabase {
        return try database(named: "admin")
    }

    /// Returns a MongoCollection for the given database and collection names.
    private func collection(database: String, collection: String) throws -> MongoCollection {
        let db = try self.database(named: database)
        return db[collection]
    }

    // MARK: - BSON / JSON Helpers

    /// Parse a JSON string into a BSON Document. Returns an empty Document for empty/nil strings.
    static func parseJSON(_ jsonString: String?) throws -> Document {
        guard let jsonString = jsonString, !jsonString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [:]
        }
        guard let data = jsonString.data(using: .utf8) else {
            throw MongoServiceError.invalidJSON("Unable to encode string as UTF-8.")
        }
        let obj = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        guard let dict = obj as? [String: Any] else {
            throw MongoServiceError.invalidJSON("Top-level value is not a JSON object.")
        }
        return Self.dictToDocument(dict)
    }

    /// Convert a Swift dictionary [String: Any] to a BSON Document.
    static func dictToDocument(_ dict: [String: Any]) -> Document {
        var doc = Document()
        for (key, value) in dict {
            doc[key] = Self.anyToPrimitive(value)
        }
        return doc
    }

    /// Convert a Swift Any value to a BSON Primitive.
    static func anyToPrimitive(_ value: Any) -> Primitive? {
        // Check Bool before NSNumber because Bool bridges to NSNumber
        if let bool = value as? Bool {
            return bool
        }
        switch value {
        case let str as String:
            return str
        case let int as Int:
            return int
        case let int32 as Int32:
            return int32
        case let double as Double:
            return double
        case let date as Date:
            return date
        case let data as Data:
            let allocator = ByteBufferAllocator()
            var buffer = allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            return Binary(buffer: buffer)
        case let dict as [String: Any]:
            return dictToDocument(dict)
        case let arr as [Any]:
            var bsonArray = Document(isArray: true)
            for (index, element) in arr.enumerated() {
                bsonArray["\(index)"] = anyToPrimitive(element)
            }
            return bsonArray
        case is NSNull:
            return Null()
        default:
            // Attempt numeric conversion through NSNumber for JSON parsed numbers
            if let nsNumber = value as? NSNumber {
                let objCType = String(cString: nsNumber.objCType)
                if objCType == "c" || objCType == "B" {
                    return nsNumber.boolValue
                }
                if nsNumber.doubleValue == nsNumber.doubleValue.rounded() && abs(nsNumber.doubleValue) < Double(Int32.max) {
                    return nsNumber.int32Value
                }
                return nsNumber.doubleValue
            }
            return nil
        }
    }

    /// Convert a BSON Document to [String: Any].
    static func documentToDict(_ doc: Document) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in doc {
            result[key] = primitiveToAny(value)
        }
        return result
    }

    /// Convert a BSON Primitive to a Swift Any.
    static func primitiveToAny(_ value: Primitive) -> Any {
        switch value {
        case let bool as Bool:
            return bool
        case let str as String:
            return str
        case let int as Int:
            return int
        case let int32 as Int32:
            return Int(int32)
        case let double as Double:
            return double
        case let objectId as ObjectId:
            return objectId.hexString
        case let date as Date:
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: date)
        case let binary as Binary:
            return binary.data.base64EncodedString()
        case let doc as Document:
            if doc.isArray {
                return doc.values.map { primitiveToAny($0) }
            }
            return documentToDict(doc)
        case is Null:
            return NSNull()
        default:
            return "\(value)"
        }
    }

    // MARK: - Database Management

    /// List all database names, excluding admin/config/local system databases.
    func getDatabases() async throws -> [String] {
        let admin = try adminDatabase()
        let command: Document = ["listDatabases": Int32(1), "nameOnly": true]
        let connection = try await admin.pool.next(for: .basic)
        let reply = try await connection.executeCodable(
            command,
            decodeAs: Document.self,
            namespace: admin.commandNamespace,
            sessionId: connection.implicitSessionId,
            traceLabel: "ListDatabases"
        )

        // Convert to Swift types for reliable parsing
        let dict = Self.documentToDict(reply)

        // Check for command error
        if let ok = dict["ok"] as? Double, ok == 0.0 {
            let errmsg = dict["errmsg"] as? String ?? "Unknown error"
            throw MongoServiceError.commandFailed(errmsg)
        }

        let systemDatabases: Set<String> = ["admin", "config", "local"]
        var names: [String] = []

        if let databasesList = dict["databases"] as? [[String: Any]] {
            // Array of dictionaries
            for db in databasesList {
                if let name = db["name"] as? String, !systemDatabases.contains(name) {
                    names.append(name)
                }
            }
        } else if let databasesList = dict["databases"] as? [Any] {
            // Array of Any
            print("[MongoCompass] databases is [Any] with \(databasesList.count) items")
            for item in databasesList {
                if let dbDict = item as? [String: Any], let name = dbDict["name"] as? String {
                    if !systemDatabases.contains(name) {
                        names.append(name)
                    }
                }
            }
        } else {
            print("[MongoCompass] databases field type: \(type(of: dict["databases"] as Any))")
            print("[MongoCompass] full reply: \(dict)")
        }

        print("[MongoCompass] Found databases: \(names)")
        return names.sorted()
    }

    /// List all collection names in the given database.
    func getCollections(database: String) async throws -> [String] {
        let db = try self.database(named: database)
        let command: Document = ["listCollections": Int32(1), "nameOnly": true]
        let connection = try await db.pool.next(for: .basic)
        let reply = try await connection.executeCodable(
            command,
            decodeAs: Document.self,
            namespace: db.commandNamespace,
            sessionId: connection.implicitSessionId,
            traceLabel: "ListCollections"
        )

        let dict = Self.documentToDict(reply)
        var names: [String] = []

        if let cursor = dict["cursor"] as? [String: Any] {
            let firstBatch: [Any]
            if let fb = cursor["firstBatch"] as? [[String: Any]] {
                firstBatch = fb
            } else if let fb = cursor["firstBatch"] as? [Any] {
                firstBatch = fb
            } else {
                print("[MongoCompass] firstBatch type: \(type(of: cursor["firstBatch"] as Any))")
                firstBatch = []
            }
            for item in firstBatch {
                if let collDict = item as? [String: Any], let name = collDict["name"] as? String {
                    if !name.hasPrefix("system.") {
                        names.append(name)
                    }
                }
            }
        }

        return names.sorted()
    }

    /// Create a new collection, optionally as a capped collection.
    func createCollection(database: String, name: String, capped: Bool = false, size: Int? = nil, max: Int? = nil) async throws {
        let db = try self.database(named: database)
        var command: Document = ["create": name]
        if capped {
            command["capped"] = true
            command["size"] = Int32(size ?? 1048576)
            if let max = max {
                command["max"] = Int32(max)
            }
        }
        let connection = try await db.pool.next(for: .writable)
        let reply = try await connection.executeCodable(
            command,
            decodeAs: Document.self,
            namespace: db.commandNamespace,
            sessionId: connection.implicitSessionId,
            traceLabel: "CreateCollection"
        )
        guard reply["ok"] as? Double == 1.0 || reply["ok"] as? Int32 == 1 || reply["ok"] as? Int == 1 else {
            let errmsg = reply["errmsg"] as? String ?? "Unknown error"
            throw MongoServiceError.commandFailed(errmsg)
        }
    }

    /// Drop a collection from a database.
    func dropCollection(database: String, collection: String) async throws {
        let coll = try self.collection(database: database, collection: collection)
        try await coll.drop()
    }

    /// Drop an entire database.
    func dropDatabase(database: String) async throws {
        let db = try self.database(named: database)
        try await db.drop()
    }

    // MARK: - CRUD Operations

    /// Get documents from a collection with optional filter, sort, projection, skip, limit (all JSON strings).
    func getDocuments(database: String, collection: String, filter: String? = nil, sort: String? = nil, projection: String? = nil, skip: Int = 0, limit: Int = 20) async throws -> [[String: Any]] {
        let coll = try self.collection(database: database, collection: collection)
        let filterDoc = try Self.parseJSON(filter)
        let sortDoc = try Self.parseJSON(sort)
        let projDoc = try Self.parseJSON(projection)

        var query = coll.find(filterDoc)
        if !sortDoc.isEmpty {
            query = query.sort(sortDoc)
        }
        if !projDoc.isEmpty {
            query = query.project(projDoc)
        }
        if skip > 0 {
            query = query.skip(skip)
        }
        query = query.limit(limit)

        var results: [[String: Any]] = []
        for try await doc in query {
            results.append(Self.documentToDict(doc))
        }
        return results
    }

    /// Insert a document (JSON string) into a collection. Returns the inserted document as [String: Any].
    @discardableResult
    func insertDocument(database: String, collection: String, document: String) async throws -> [String: Any] {
        let coll = try self.collection(database: database, collection: collection)
        let doc = try Self.parseJSON(document)
        try await coll.insert(doc)
        return Self.documentToDict(doc)
    }

    /// Update a document matching filter with the given update document (both JSON strings).
    func updateDocument(database: String, collection: String, filter: String, update: String) async throws {
        let coll = try self.collection(database: database, collection: collection)
        let filterDoc = try Self.parseJSON(filter)
        let updateDoc = try Self.parseJSON(update)
        try await coll.updateOne(where: filterDoc, to: updateDoc)
    }

    /// Delete a single document matching the filter (JSON string).
    func deleteDocument(database: String, collection: String, filter: String) async throws {
        let coll = try self.collection(database: database, collection: collection)
        let filterDoc = try Self.parseJSON(filter)
        try await coll.deleteOne(where: filterDoc)
    }

    // MARK: - Aggregation

    /// Run an aggregation pipeline on a collection. Pipeline stages are [[String: Any]].
    /// `allowDiskUse` lifts the 100MB memory limit for sorts/groups.
    /// `resultLimit` caps how many documents are materialized into memory; pass `nil` for no cap.
    func runAggregation(
        database: String,
        collection: String,
        pipeline: [[String: Any]],
        allowDiskUse: Bool = false,
        resultLimit: Int? = nil
    ) async throws -> [[String: Any]] {
        let coll = try self.collection(database: database, collection: collection)

        let pipelineDocs: [Document] = pipeline.map { Self.dictToDocument($0) }
        let stages: [AggregateBuilderStage] = pipelineDocs.map { RawAggregateStage(document: $0) }

        var aggregatePipeline = AggregateBuilderPipeline(stages: stages, collection: coll)
        if allowDiskUse {
            aggregatePipeline = aggregatePipeline.allowDiskUse(true)
        }

        var results: [[String: Any]] = []
        for try await doc in aggregatePipeline {
            results.append(Self.documentToDict(doc))
            if let cap = resultLimit, results.count >= cap {
                break
            }
            try Task.checkCancellation()
        }
        return results
    }

    // MARK: - Indexes

    /// Get all indexes for a collection.
    func getIndexes(database: String, collection: String) async throws -> [[String: Any]] {
        let coll = try self.collection(database: database, collection: collection)
        let indexes = try await coll.listIndexes().drain()
        return indexes.map { index in
            var dict: [String: Any] = [
                "name": index.name,
                "key": Self.documentToDict(index.key),
                "version": index.version
            ]
            if let unique = index.unique {
                dict["unique"] = unique
            }
            if let sparse = index.sparse {
                dict["sparse"] = sparse
            }
            if let ttl = index.expireAfterSeconds {
                dict["expireAfterSeconds"] = Int(ttl)
            }
            return dict
        }
    }

    /// Create an index on a collection.
    func createIndex(database: String, collection: String, name: String, keys: [String: Any], unique: Bool = false, sparse: Bool = false) async throws {
        let coll = try self.collection(database: database, collection: collection)
        let keysDoc = Self.dictToDocument(keys)
        var index = CreateIndexes.Index(named: name, keys: keysDoc)
        if unique { index.unique = true }
        if sparse { index.sparse = true }
        try await coll.createIndexes([index])
    }

    /// Drop an index from a collection by name.
    func dropIndex(database: String, collection: String, indexName: String) async throws {
        let db = try self.database(named: database)
        let command: Document = [
            "dropIndexes": collection,
            "index": indexName
        ]
        let connection = try await db.pool.next(for: .writable)
        let reply = try await connection.executeEncodable(
            command,
            namespace: db.commandNamespace,
            in: nil,
            sessionId: connection.implicitSessionId,
            logMetadata: nil
        )
        try reply.assertOK()
    }

    // MARK: - Query Analysis

    /// Explain a find query, returning the explain output.
    func explainFind(database: String, collection: String, filter: String?) async throws -> [String: Any] {
        let coll = try self.collection(database: database, collection: collection)
        let filterDoc = try Self.parseJSON(filter)
        let explainDoc = try await coll.find(filterDoc).explain()
        return Self.documentToDict(explainDoc)
    }

    // MARK: - Sampling

    /// Sample random documents from a collection for schema analysis.
    func sampleDocuments(database: String, collection: String, count: Int) async throws -> [[String: Any]] {
        let docs = try await sampleDocumentsBSON(database: database, collection: collection, count: count)
        return docs.map { Self.documentToDict($0) }
    }

    /// Sample random documents as raw BSON for schema analysis, optionally pre-filtered.
    /// When `count <= 0`, the `$sample` stage is omitted and ALL matching documents are
    /// returned (full-scan mode) — may be slow on large collections.
    /// Returning BSON preserves type information that would otherwise be lost via
    /// `primitiveToAny` (ObjectId -> hex string, Date -> ISO string, Int64 -> Int, etc.).
    func sampleDocumentsBSON(
        database: String,
        collection: String,
        filter: String? = nil,
        count: Int
    ) async throws -> [Document] {
        let coll = try self.collection(database: database, collection: collection)
        let filterDoc = try Self.parseJSON(filter)

        var stages: [AggregateBuilderStage] = []
        if !filterDoc.isEmpty {
            stages.append(RawAggregateStage(document: ["$match": filterDoc]))
        }
        if count > 0 {
            stages.append(RawAggregateStage(document: ["$sample": ["size": Int32(count)]]))
        }

        // An aggregation pipeline must have at least one stage — when unfiltered and
        // unsampled, use a no-op $match to keep the pipeline valid.
        if stages.isEmpty {
            stages.append(RawAggregateStage(document: ["$match": [:] as Document]))
        }

        let pipeline = AggregateBuilderPipeline(stages: stages, collection: coll)
        var results: [Document] = []
        for try await doc in pipeline {
            results.append(doc)
        }
        return results
    }

    // MARK: - Collection Stats

    /// Get collection statistics.
    func getCollStats(database: String, collection: String) async throws -> [String: Any] {
        let result = try await runCommand(database: database, command: ["collStats": collection])
        return result
    }

    // MARK: - Server Status / Metrics

    /// Get server status. Returns a ServerMetrics instance.
    func getServerStatus() async throws -> ServerMetrics {
        let admin = try adminDatabase()
        let command: Document = ["serverStatus": Int32(1)]
        let connection = try await admin.pool.next(for: .basic)
        let reply = try await connection.executeCodable(
            command,
            decodeAs: Document.self,
            namespace: admin.commandNamespace,
            sessionId: connection.implicitSessionId,
            traceLabel: "ServerStatus"
        )

        var metrics = ServerMetrics()

        if let connections = reply["connections"] as? Document {
            metrics.connectionsActive = Self.extractInt(connections["current"]) ?? 0
            metrics.connectionsAvailable = Self.extractInt(connections["available"]) ?? 0
            metrics.connectionsTotalCreated = Self.extractInt(connections["totalCreated"]) ?? 0
        }

        if let mem = reply["mem"] as? Document {
            metrics.memoryResident = Self.extractInt(mem["resident"]) ?? 0
            metrics.memoryVirtual = Self.extractInt(mem["virtual"]) ?? 0
        }

        if let opcounters = reply["opcounters"] as? Document {
            var ops: [String: Int] = [:]
            for (key, value) in opcounters {
                if let v = Self.extractInt(value) {
                    ops[key] = v
                }
            }
            metrics.opcounters = ops
        }

        if let network = reply["network"] as? Document {
            metrics.networkBytesIn = Self.extractInt64(network["bytesIn"]) ?? 0
            metrics.networkBytesOut = Self.extractInt64(network["bytesOut"]) ?? 0
        }

        if let prim = reply["uptime"] {
            if let v = prim as? Int {
                metrics.uptime = v
            } else if let v = prim as? Int32 {
                metrics.uptime = Int(v)
            } else if let v = prim as? Double {
                metrics.uptime = Int(v)
            }
        }

        if let version = reply["version"] as? String {
            metrics.version = version
        }

        if let host = reply["host"] as? String {
            metrics.host = host
        }

        return metrics
    }

    /// Extract an Int from a BSON Primitive (handles Int, Int32, Double).
    private static func extractInt(_ value: Primitive?) -> Int? {
        guard let value = value else { return nil }
        if let v = value as? Int { return v }
        if let v = value as? Int32 { return Int(v) }
        if let v = value as? Double { return Int(v) }
        return nil
    }

    /// Extract an Int64 from a BSON Primitive (handles Int, Int32, Double).
    private static func extractInt64(_ value: Primitive?) -> Int64? {
        guard let value = value else { return nil }
        if let v = value as? Int { return Int64(v) }
        if let v = value as? Int32 { return Int64(v) }
        if let v = value as? Double { return Int64(v) }
        return nil
    }

    /// Ping the server and return latency in milliseconds.
    func pingServer() async throws -> Int {
        let admin = try adminDatabase()
        let command: Document = ["ping": Int32(1)]
        let start = Date()
        let connection = try await admin.pool.next(for: .basic)
        let reply = try await connection.executeCodable(
            command,
            decodeAs: Document.self,
            namespace: admin.commandNamespace,
            sessionId: connection.implicitSessionId,
            traceLabel: "Ping"
        )
        let elapsed = Date().timeIntervalSince(start)
        _ = reply
        return Int(elapsed * 1000)
    }

    // MARK: - Profiling

    /// Get profiler status for a database.
    func getProfilerStatus(database: String) async throws -> [String: Any] {
        return try await runCommand(database: database, command: ["profile": -1])
    }

    /// Set profiling level for a database. Level 0=off, 1=slow queries, 2=all.
    func setProfilingLevel(database: String, level: Int, slowMs: Int? = nil) async throws {
        var cmd: [String: Any] = ["profile": level]
        if let slowMs = slowMs {
            cmd["slowms"] = slowMs
        }
        _ = try await runCommand(database: database, command: cmd)
    }

    /// Get slow queries from the system.profile collection.
    func getSlowQueries(database: String, limit: Int = 50) async throws -> [SlowQueryEntry] {
        let db = try self.database(named: database)
        let profileColl = db["system.profile"]
        var results: [SlowQueryEntry] = []

        let sortDoc: Document = ["ts": Int32(-1)]
        let query = profileColl.find().sort(sortDoc).limit(limit)

        for try await doc in query {
            let dict = Self.documentToDict(doc)
            let commandString: String = {
                if let cmd = dict["command"] {
                    if let data = try? JSONSerialization.data(withJSONObject: cmd, options: [.fragmentsAllowed]),
                       let str = String(data: data, encoding: .utf8) {
                        return str
                    }
                }
                return "{}"
            }()
            let entry = SlowQueryEntry(
                operation: dict["op"] as? String ?? "unknown",
                namespace: dict["ns"] as? String ?? "",
                command: commandString,
                executionTimeMs: dict["millis"] as? Int ?? 0,
                keysExamined: dict["keysExamined"] as? Int ?? 0,
                docsExamined: dict["docsExamined"] as? Int ?? 0,
                planSummary: dict["planSummary"] as? String ?? ""
            )
            results.append(entry)
        }
        return results
    }

    // MARK: - Monitoring

    /// Get currently running operations.
    func getCurrentOps() async throws -> [CurrentOp] {
        let admin = try adminDatabase()
        let command: Document = ["currentOp": Int32(1), "active": true]
        let connection = try await admin.pool.next(for: .basic)
        let reply = try await connection.executeCodable(
            command,
            decodeAs: Document.self,
            namespace: admin.commandNamespace,
            sessionId: connection.implicitSessionId,
            traceLabel: "CurrentOp"
        )

        var ops: [CurrentOp] = []
        if let inprog = reply["inprog"] as? Document {
            for (_, value) in inprog {
                guard let opDoc = value as? Document else { continue }
                let dict = Self.documentToDict(opDoc)
                let op = CurrentOp(
                    id: dict["opid"] as? Int ?? 0,
                    type: dict["type"] as? String ?? "",
                    op: dict["op"] as? String ?? "",
                    namespace: dict["ns"] as? String ?? "",
                    client: dict["client"] as? String ?? dict["client_s"] as? String ?? "",
                    executionTimeMs: dict["microsecs_running"] as? Int ?? ((dict["secs_running"] as? Int ?? 0) * 1000),
                    description: dict["desc"] as? String ?? ""
                )
                ops.append(op)
            }
        }
        return ops
    }

    /// Kill a running operation by opId.
    func killOp(opId: Int) async throws {
        _ = try await runCommand(database: "admin", command: ["killOp": 1, "op": opId])
    }

    // MARK: - Run Arbitrary Command

    /// Run an arbitrary command on a database.
    func runCommand(database: String, command: [String: Any]) async throws -> [String: Any] {
        let db = try self.database(named: database)
        // Convert, ensuring small integers become Int32 for MongoDB compatibility
        var commandDoc = Document()
        for (key, value) in command {
            if let intVal = value as? Int, intVal >= Int(Int32.min) && intVal <= Int(Int32.max) {
                commandDoc[key] = Int32(intVal)
            } else {
                commandDoc[key] = Self.anyToPrimitive(value)
            }
        }
        let connection = try await db.pool.next(for: .basic)
        let reply = try await connection.executeCodable(
            commandDoc,
            decodeAs: Document.self,
            namespace: db.commandNamespace,
            sessionId: connection.implicitSessionId,
            traceLabel: "RunCommand"
        )
        return Self.documentToDict(reply)
    }
}

// MARK: - RawAggregateStage

/// A simple aggregate stage wrapping a raw BSON Document.
struct RawAggregateStage: AggregateBuilderStage {
    let stage: Document
    var minimalVersionRequired: WireVersion? { nil }

    init(document: Document) {
        self.stage = document
    }
}
