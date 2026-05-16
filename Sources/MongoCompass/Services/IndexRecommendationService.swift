import Foundation

/// Pure-function index recommendation engine.
///
/// Takes a list of slow-query observations and produces a ranked set of
/// suggested compound indexes built using MongoDB's ESR rule (Equality →
/// Sort → Range). Out of scope: anything that touches the network or the
/// view layer; the caller fetches inputs and presents outputs.
struct IndexRecommendationService {

    // MARK: - Field-level operators

    /// Operators inside a field's predicate document that imply a range
    /// scan rather than a point lookup.
    private static let rangeOperators: Set<String> = [
        "$gt", "$gte", "$lt", "$lte", "$ne", "$in", "$nin", "$regex"
    ]

    /// Logical operators we descend into to collect inner predicates.
    private static let logicalOperators: Set<String> = ["$and", "$or", "$nor"]

    /// Field-level operators that don't on their own justify an index.
    private static let ignoredFieldOperators: Set<String> = [
        "$exists", "$type", "$mod", "$elemMatch", "$all", "$size", "$not"
    ]

    /// Top-level filter operators that can never benefit from a regular
    /// b-tree index — we drop these queries entirely.
    private static let nonIndexableTopLevelMarkers: [String] = ["$where", "$expr", "$text"]

    // MARK: - Public API

    /// Compute recommendations from observed slow queries.
    ///
    /// - parameter slowQueries: profiled entries from `system.profile`.
    /// - parameter existingIndexesByNamespace: map of `db.coll` →
    ///   array of index documents (as returned by `MongoService.getIndexes`).
    ///   Used to suppress recommendations that are already covered.
    static func recommend(
        slowQueries: [SlowQueryEntry],
        existingIndexesByNamespace: [String: [[String: Any]]] = [:]
    ) -> [IndexRecommendation] {

        struct GroupKey: Hashable {
            let namespace: String
            let spec: [IndexFieldSpec]
        }
        struct GroupValue {
            var count: Int = 0
            var totalMs: Int = 0
            var exampleEntry: SlowQueryEntry?
        }

        var groups: [GroupKey: GroupValue] = [:]

        for entry in slowQueries {
            guard !entry.namespace.isEmpty else { continue }
            // Skip Mongo internal namespaces (system.*, config.*, etc.)
            if entry.namespace.contains(".system.") { continue }
            if entry.namespace.hasPrefix("config.") { continue }
            if entry.namespace.hasPrefix("local.") { continue }
            // Skip queries that already use a selective IXSCAN.
            if isWellIndexed(entry) { continue }
            // Skip queries that contain non-indexable operators.
            if hasNonIndexable(entry.command) { continue }

            guard let parsed = parseCommand(entry.command) else { continue }
            let classification = classifyFilter(parsed.filter)
            let spec = buildSpec(
                equality: classification.equality,
                sort: parsed.sort,
                range: classification.range
            )
            guard !spec.isEmpty else { continue }

            // Don't recommend an index that is already covered by an
            // existing index on the same namespace.
            let existing = existingIndexesByNamespace[entry.namespace] ?? []
            if isCoveredByExisting(spec, in: existing) { continue }

            let key = GroupKey(namespace: entry.namespace, spec: spec)
            var v = groups[key] ?? GroupValue()
            v.count += 1
            v.totalMs += entry.executionTimeMs
            if v.exampleEntry == nil
                || entry.executionTimeMs > (v.exampleEntry?.executionTimeMs ?? 0) {
                v.exampleEntry = entry
            }
            groups[key] = v
        }

        let recs: [IndexRecommendation] = groups.compactMap { (key, value) in
            guard let example = value.exampleEntry else { return nil }
            return IndexRecommendation(
                namespace: key.namespace,
                spec: key.spec,
                supportingQueries: value.count,
                totalExecTimeMs: value.totalMs,
                exampleQuery: shortenCommand(example.command),
                rationale: rationale(spec: key.spec, example: example)
            )
        }

        return recs.sorted {
            if $0.totalExecTimeMs != $1.totalExecTimeMs {
                return $0.totalExecTimeMs > $1.totalExecTimeMs
            }
            return $0.supportingQueries > $1.supportingQueries
        }
    }

    // MARK: - Heuristics

    private static func isWellIndexed(_ entry: SlowQueryEntry) -> Bool {
        let summary = entry.planSummary.uppercased()
        if summary.contains("COLLSCAN") { return false }
        if summary.hasPrefix("IXSCAN") {
            // If the index returned almost as many keys as docs examined,
            // it's already selective. ratio ≤ 1.5 means most keys mapped
            // to a single document — a healthy index.
            let keys = Swift.max(entry.keysExamined, 1)
            let ratio = Double(entry.docsExamined) / Double(keys)
            return ratio <= 1.5
        }
        // Unknown plan summary — let the user see the recommendation.
        return false
    }

    private static func hasNonIndexable(_ command: String) -> Bool {
        for marker in nonIndexableTopLevelMarkers where command.contains(marker) {
            return true
        }
        return false
    }

    /// True if some existing index already covers this spec — same field
    /// set with the same directions. We're conservative on field-order
    /// because dictionaries decoded from JSON aren't ordered: any
    /// existing index with the same fields & directions counts as
    /// covering, even if the prefix order may differ.
    private static func isCoveredByExisting(
        _ spec: [IndexFieldSpec],
        in existing: [[String: Any]]
    ) -> Bool {
        for index in existing {
            guard let key = index["key"] as? [String: Any] else { continue }
            var allFieldsMatch = true
            for f in spec {
                let existingDir: Int? = {
                    if let v = key[f.field] as? Int { return v }
                    if let v = key[f.field] as? Int32 { return Int(v) }
                    if let v = key[f.field] as? Double { return Int(v) }
                    return nil
                }()
                if existingDir != f.direction {
                    allFieldsMatch = false
                    break
                }
            }
            // Existing index has at least these fields and at most a few
            // more — it can serve the recommendation as a prefix or
            // identically.
            if allFieldsMatch && key.count >= spec.count {
                return true
            }
        }
        return false
    }

    // MARK: - Parsing

    private static func parseCommand(
        _ command: String
    ) -> (filter: [String: Any], sort: [(String, Int)])? {
        guard let data = command.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let dict = any as? [String: Any]
        else { return nil }

        // find / count
        if dict["find"] != nil || dict["count"] != nil {
            let filter = (dict["filter"] as? [String: Any])
                ?? (dict["query"] as? [String: Any])
                ?? [:]
            let sort = sortFromDocument(dict["sort"] as? [String: Any] ?? [:])
            return (filter, sort)
        }
        // aggregate — take first $match for filter, first $sort for sort
        if dict["aggregate"] != nil,
           let pipeline = dict["pipeline"] as? [[String: Any]] {
            var filter: [String: Any] = [:]
            var sort: [(String, Int)] = []
            for stage in pipeline {
                if filter.isEmpty, let match = stage["$match"] as? [String: Any] {
                    filter = match
                }
                if sort.isEmpty, let s = stage["$sort"] as? [String: Any] {
                    sort = sortFromDocument(s)
                }
                if !filter.isEmpty && !sort.isEmpty { break }
            }
            return (filter, sort)
        }
        // update
        if dict["update"] != nil,
           let updates = dict["updates"] as? [[String: Any]],
           let first = updates.first,
           let q = first["q"] as? [String: Any] {
            return (q, [])
        }
        // delete
        if dict["delete"] != nil,
           let deletes = dict["deletes"] as? [[String: Any]],
           let first = deletes.first,
           let q = first["q"] as? [String: Any] {
            return (q, [])
        }
        // Legacy profiled `query`/`orderby` form
        if let q = dict["query"] as? [String: Any] {
            let sort = sortFromDocument(dict["orderby"] as? [String: Any] ?? [:])
            return (q, sort)
        }
        return nil
    }

    private static func sortFromDocument(_ dict: [String: Any]) -> [(String, Int)] {
        dict.compactMap { key, value -> (String, Int)? in
            if let v = value as? Int { return (key, v) }
            if let v = value as? Int32 { return (key, Int(v)) }
            if let v = value as? Double { return (key, Int(v)) }
            return nil
        }
    }

    // MARK: - Classification

    private static func classifyFilter(
        _ filter: [String: Any]
    ) -> (equality: [String], range: [String]) {
        var equality: [String] = []
        var range: [String] = []
        classifyRecursive(filter, equality: &equality, range: &range)

        // Preserve first-seen order while deduplicating across both buckets.
        // Range overrides equality when a field appears in both — ESR
        // demands that range fields go last regardless of any earlier
        // equality usage.
        let rangeSet = Set(range)
        var seen: Set<String> = []
        let dedupedEq = equality.filter { f in
            !rangeSet.contains(f) && seen.insert(f).inserted
        }
        var seenR: Set<String> = []
        let dedupedRange = range.filter { seenR.insert($0).inserted }
        return (dedupedEq, dedupedRange)
    }

    private static func classifyRecursive(
        _ filter: [String: Any],
        equality: inout [String],
        range: inout [String]
    ) {
        for (key, value) in filter {
            // Logical operator — recurse into each clause.
            if logicalOperators.contains(key), let clauses = value as? [[String: Any]] {
                for clause in clauses {
                    classifyRecursive(clause, equality: &equality, range: &range)
                }
                continue
            }
            // Other top-level operators — skip.
            if key.hasPrefix("$") { continue }

            // Scalar value → equality predicate.
            if !(value is [String: Any]) {
                equality.append(key)
                continue
            }

            // Operator document — inspect inner operators.
            if let opDict = value as? [String: Any] {
                var hasRange = false
                var hasEquality = false
                var meaningful = false
                for (op, _) in opDict {
                    if rangeOperators.contains(op) {
                        hasRange = true
                        meaningful = true
                    } else if op == "$eq" {
                        hasEquality = true
                        meaningful = true
                    } else if !ignoredFieldOperators.contains(op) {
                        // Unknown operator — be conservative; classify as equality.
                        hasEquality = true
                        meaningful = true
                    }
                }
                guard meaningful else { continue }
                if hasRange { range.append(key) }
                else if hasEquality { equality.append(key) }
            }
        }
    }

    // MARK: - Spec assembly (ESR)

    private static func buildSpec(
        equality: [String],
        sort: [(String, Int)],
        range: [String]
    ) -> [IndexFieldSpec] {
        var spec: [IndexFieldSpec] = []
        var used: Set<String> = []

        // E — equality predicates ascending.
        for field in equality where !used.contains(field) {
            spec.append(IndexFieldSpec(field: field, direction: 1))
            used.insert(field)
        }

        // S — sort fields preserving direction. If a sort field already
        // appears as equality, rewrite the existing entry's direction to
        // the sort direction so the index can serve both.
        for (field, dir) in sort {
            if used.contains(field) {
                if let idx = spec.firstIndex(where: { $0.field == field }) {
                    spec[idx] = IndexFieldSpec(field: field, direction: dir)
                }
            } else {
                spec.append(IndexFieldSpec(field: field, direction: dir))
                used.insert(field)
            }
        }

        // R — range predicates ascending.
        for field in range where !used.contains(field) {
            spec.append(IndexFieldSpec(field: field, direction: 1))
            used.insert(field)
        }

        return spec
    }

    // MARK: - Display helpers

    private static func shortenCommand(_ command: String, maxChars: Int = 100) -> String {
        let trimmed = command
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        if trimmed.count <= maxChars { return trimmed }
        return String(trimmed.prefix(maxChars - 1)) + "…"
    }

    private static func rationale(
        spec: [IndexFieldSpec],
        example: SlowQueryEntry
    ) -> String {
        let fields = spec.map { $0.field }.joined(separator: ", ")
        let plan = example.planSummary.uppercased()
        if plan.contains("COLLSCAN") {
            return "COLLSCAN observed on \(example.namespace). A compound index on \(fields) would let the operation use IXSCAN."
        }
        let ratio = Double(example.docsExamined) / Double(Swift.max(example.keysExamined, 1))
        return String(
            format: "Existing access plan examined %d docs against %d keys (ratio %.1f). A more selective index on %@ should reduce scanning.",
            example.docsExamined, example.keysExamined, ratio, fields
        )
    }
}
