import Foundation

struct SchemaField: Identifiable {
    let id = UUID()
    let name: String
    /// The BSON types observed for this field, highest-count first.
    var types: [SchemaTypeInfo]
    /// Number of sampled documents that contained this field.
    var presence: Int
    /// Total number of sampled documents (denominator for `frequency`).
    var totalDocuments: Int
    /// Fraction of sampled documents that had this field (0.0 – 1.0).
    /// Always absolute — for nested fields, this is still out of the total sample.
    var frequency: Double
    var nestedFields: [SchemaField]?
    var stats: SchemaFieldStats?

    /// True when a field has more than one non-null type observed at the root level.
    /// (Array element heterogeneity is considered normal and not counted here.)
    var hasMixedTypes: Bool {
        types.filter { $0.typeName != "null" }.count > 1
    }
}

struct SchemaTypeInfo: Identifiable {
    let id = UUID()
    let typeName: String
    let count: Int
    /// For `typeName == "array"`, the breakdown of element types across all observed arrays.
    var elementTypes: [SchemaTypeInfo]?
}

struct SchemaFieldStats {
    // Numeric
    var numericMin: Double?
    var numericMax: Double?
    var numericAvg: Double?
    // String
    var stringMinLength: Int?
    var stringMaxLength: Int?
    // Cardinality / top-values (scalar types only)
    var distinctCount: Int?
    var topValues: [TopValue] = []

    /// True if at least one populated stat is worth showing.
    var hasAnyStat: Bool {
        numericMin != nil
            || stringMinLength != nil
            || distinctCount != nil
            || !topValues.isEmpty
    }
}

struct TopValue: Identifiable {
    let id = UUID()
    let value: String
    let count: Int
}
