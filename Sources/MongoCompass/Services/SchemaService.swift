import Foundation
import MongoKitten

struct SchemaService {

    /// Analyze a set of sampled BSON documents and return inferred schema fields.
    /// Fields are sorted with `_id` first, then by frequency descending, then alphabetically.
    func analyzeSchema(documents: [Document]) -> [SchemaField] {
        guard !documents.isEmpty else { return [] }
        return analyzeFields(documents: documents, totalSampled: documents.count)
    }

    // MARK: - Private Implementation

    /// Recursive analyzer. `totalSampled` always refers to the ORIGINAL top-level sample size
    /// so that nested-field frequencies remain absolute ("out of N sampled docs"),
    /// never relative to the parent count.
    private func analyzeFields(documents: [Document], totalSampled: Int) -> [SchemaField] {
        // Per-field accumulators
        var typeCounters: [String: [String: Int]] = [:]
        var presence: [String: Int] = [:]
        var nestedDocsByField: [String: [Document]] = [:]
        var arrayElementsByField: [String: [Primitive]] = [:]
        var valueAccumulators: [String: ValueAccumulator] = [:]

        for doc in documents {
            for (key, value) in doc {
                presence[key, default: 0] += 1
                let typeName = detectType(value)
                typeCounters[key, default: [:]][typeName, default: 0] += 1

                // Collect nested objects (documents that are NOT arrays)
                if let nested = value as? Document, !nested.isArray {
                    nestedDocsByField[key, default: []].append(nested)
                }

                // Collect array elements (flattened)
                if let arr = value as? Document, arr.isArray {
                    arrayElementsByField[key, default: []].append(contentsOf: arr.values)
                }

                // Accumulate value statistics for scalar types
                valueAccumulators[key, default: ValueAccumulator()].record(value)
            }
        }

        var fields: [SchemaField] = []

        for (fieldName, typeCounts) in typeCounters {
            var baseTypes = typeCounts
                .map { SchemaTypeInfo(typeName: $0.key, count: $0.value) }
                .sorted { $0.count > $1.count }

            // Enrich the "array" type entry with its element-type breakdown.
            if let elements = arrayElementsByField[fieldName], !elements.isEmpty {
                var elementCounts: [String: Int] = [:]
                for elem in elements {
                    elementCounts[detectType(elem), default: 0] += 1
                }
                let elementTypes = elementCounts
                    .map { SchemaTypeInfo(typeName: $0.key, count: $0.value) }
                    .sorted { $0.count > $1.count }

                baseTypes = baseTypes.map { type in
                    guard type.typeName == "array" else { return type }
                    var copy = type
                    copy.elementTypes = elementTypes
                    return copy
                }
            }

            // Merge nested documents from BOTH plain-object occurrences AND
            // objects nested inside arrays (fixes polymorphic object/array-of-object schemas).
            var mergedNestedDocs: [Document] = nestedDocsByField[fieldName] ?? []
            if let elements = arrayElementsByField[fieldName] {
                for elem in elements {
                    if let d = elem as? Document, !d.isArray {
                        mergedNestedDocs.append(d)
                    }
                }
            }

            var nestedFields: [SchemaField]?
            if !mergedNestedDocs.isEmpty {
                nestedFields = analyzeFields(documents: mergedNestedDocs, totalSampled: totalSampled)
            }

            let pres = presence[fieldName] ?? 0
            let freq = Double(pres) / Double(totalSampled)
            let stats = valueAccumulators[fieldName]?.finalize()

            fields.append(
                SchemaField(
                    name: fieldName,
                    types: baseTypes,
                    presence: pres,
                    totalDocuments: totalSampled,
                    frequency: freq,
                    nestedFields: nestedFields,
                    stats: stats
                )
            )
        }

        // Sort: `_id` pinned first, then by frequency desc, then alphabetical.
        fields.sort { a, b in
            if a.name == "_id" && b.name != "_id" { return true }
            if b.name == "_id" && a.name != "_id" { return false }
            if a.frequency != b.frequency { return a.frequency > b.frequency }
            return a.name < b.name
        }

        return fields
    }

    /// Detect the BSON type name of a Primitive value.
    private func detectType(_ value: Primitive) -> String {
        // Order matters: Bool must be checked before integer-like NSNumber bridging.
        if value is Bool { return "bool" }
        if value is Null { return "null" }
        if value is Int32 { return "int32" }
        if value is Int { return "int64" }      // BSON int64 arrives as Swift Int on 64-bit
        if value is Double { return "double" }
        if value is Decimal128 { return "decimal128" }
        if value is String { return "string" }
        if value is ObjectId { return "objectId" }
        if value is Date { return "date" }
        if value is Binary { return "binary" }
        if value is RegularExpression { return "regex" }
        if value is Timestamp { return "timestamp" }
        if let doc = value as? Document {
            return doc.isArray ? "array" : "object"
        }
        return String(describing: type(of: value))
    }
}

// MARK: - Value Accumulator

/// Collects min/max/avg/distinct/top-values for a single field across a sample.
private struct ValueAccumulator {
    // Numeric
    var numericMin: Double?
    var numericMax: Double?
    var numericSum: Double = 0
    var numericCount: Int = 0

    // String
    var stringMinLength: Int?
    var stringMaxLength: Int?

    // Distinct / top values (scalar keys only)
    var valueCounts: [String: Int] = [:]
    /// Cap cardinality tracking to prevent unbounded memory on high-cardinality fields.
    private static let maxDistinctTracked = 1000
    var hitCardinalityCap = false

    var hasAnyRecord = false

    mutating func record(_ value: Primitive) {
        // Skip null (presence is enough; null has no stats to show).
        if value is Null { return }
        // Skip structural types — stats apply to scalars only.
        if value is Document { return }
        hasAnyRecord = true

        // Numeric stats
        if let d = numericValue(value) {
            numericMin = min(numericMin ?? d, d)
            numericMax = max(numericMax ?? d, d)
            numericSum += d
            numericCount += 1
        }

        // String length
        if let s = value as? String {
            stringMinLength = min(stringMinLength ?? s.count, s.count)
            stringMaxLength = max(stringMaxLength ?? s.count, s.count)
        }

        // Distinct + top values (scalar key only)
        if let key = scalarKey(value) {
            if valueCounts[key] != nil {
                valueCounts[key, default: 0] += 1
            } else if valueCounts.count < Self.maxDistinctTracked {
                valueCounts[key] = 1
            } else {
                hitCardinalityCap = true
            }
        }
    }

    func finalize() -> SchemaFieldStats? {
        guard hasAnyRecord else { return nil }

        let numericAvg: Double? = numericCount > 0 ? numericSum / Double(numericCount) : nil

        // Top values are only useful when there is actual repetition.
        let sortedTop = valueCounts.sorted { $0.value > $1.value }
        let topValues: [TopValue]
        if let first = sortedTop.first, first.value > 1 {
            topValues = sortedTop.prefix(5).map { TopValue(value: $0.key, count: $0.value) }
        } else {
            topValues = []
        }

        let distinctCount: Int? = valueCounts.isEmpty
            ? nil
            : (hitCardinalityCap ? Self.maxDistinctTracked : valueCounts.count)

        return SchemaFieldStats(
            numericMin: numericMin,
            numericMax: numericMax,
            numericAvg: numericAvg,
            stringMinLength: stringMinLength,
            stringMaxLength: stringMaxLength,
            distinctCount: distinctCount,
            topValues: topValues
        )
    }

    private func numericValue(_ value: Primitive) -> Double? {
        if value is Bool { return nil }
        if let i = value as? Int { return Double(i) }
        if let i = value as? Int32 { return Double(i) }
        if let d = value as? Double { return d }
        return nil
    }

    private func scalarKey(_ value: Primitive) -> String? {
        if let b = value as? Bool { return b ? "true" : "false" }
        if let s = value as? String { return s }
        if let i = value as? Int { return String(i) }
        if let i = value as? Int32 { return String(i) }
        if let d = value as? Double { return String(d) }
        if let oid = value as? ObjectId { return oid.hexString }
        if let date = value as? Date {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f.string(from: date)
        }
        return nil  // binary / regex / timestamp / decimal128 — skip for top-values
    }
}
