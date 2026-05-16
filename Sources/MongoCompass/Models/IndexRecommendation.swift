import Foundation

/// One field of a recommended compound index.
struct IndexFieldSpec: Equatable, Hashable {
    let field: String
    /// `1` for ascending, `-1` for descending.
    let direction: Int
}

/// A suggested index synthesised from observed slow-query patterns.
///
/// Built by `IndexRecommendationService` — pure-function transform of
/// `[SlowQueryEntry] + existingIndexes` into a ranked list of compound
/// index proposals using MongoDB's ESR rule (Equality, Sort, Range).
struct IndexRecommendation: Identifiable, Equatable {
    let id = UUID()

    /// Fully-qualified MongoDB namespace, e.g. `myDb.users`.
    let namespace: String

    /// Ordered fields of the proposed compound index.
    let spec: [IndexFieldSpec]

    /// How many distinct slow-query observations this recommendation
    /// would support (deduplicated by query shape).
    let supportingQueries: Int

    /// Sum of `executionTimeMs` across the supporting queries.
    let totalExecTimeMs: Int

    /// A short, human-readable example of one of the supporting queries.
    /// Truncated to ~100 chars for display.
    let exampleQuery: String

    /// One-sentence explanation of why this index was suggested.
    let rationale: String

    enum Impact: String {
        case high = "HIGH"
        case medium = "MEDIUM"
        case low = "LOW"
    }

    var impact: Impact {
        if supportingQueries >= 5 || totalExecTimeMs >= 1_000 { return .high }
        if supportingQueries >= 2 || totalExecTimeMs >= 200 { return .medium }
        return .low
    }

    /// Average per-query execution time across supporting observations.
    var avgExecTimeMs: Int {
        supportingQueries == 0 ? 0 : totalExecTimeMs / supportingQueries
    }

    /// Render the spec as MongoDB shell-style JSON: `{ status: 1, createdAt: -1 }`.
    var indexJSON: String {
        let parts = spec.map { "\"\($0.field)\": \($0.direction)" }
        return "{ " + parts.joined(separator: ", ") + " }"
    }

    /// Conventional Mongo index name: `field_1_field2_-1`.
    var suggestedName: String {
        spec.map { "\($0.field)_\($0.direction)" }.joined(separator: "_")
    }

    /// Convert to the `[String: Int]` keys dictionary expected by
    /// `AppViewModel.createIndex(fields:)`.
    var keysDictionary: [String: Int] {
        var d: [String: Int] = [:]
        for f in spec { d[f.field] = f.direction }
        return d
    }

    /// True when no fields would be sensible to index. The engine should
    /// never produce one of these, but the guard exists for defence.
    var isEmpty: Bool { spec.isEmpty }
}
