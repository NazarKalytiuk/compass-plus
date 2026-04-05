import Foundation

struct PipelineStage: Codable, Identifiable {
    let id: UUID
    var type: String  // e.g. "$match", "$group"
    var body: String  // JSON string
    var enabled: Bool
    var collapsed: Bool

    init(id: UUID = UUID(), type: String = "$match", body: String = "{}", enabled: Bool = true, collapsed: Bool = false) {
        self.id = id
        self.type = type
        self.body = body
        self.enabled = enabled
        self.collapsed = collapsed
    }

    static let availableTypes = [
        // Core filtering / reshaping
        "$match", "$project", "$addFields", "$set", "$unset", "$replaceRoot", "$replaceWith",
        // Aggregation
        "$group", "$bucket", "$bucketAuto", "$count", "$sortByCount", "$facet",
        // Ordering / paging
        "$sort", "$limit", "$skip", "$sample",
        // Joining
        "$lookup", "$graphLookup", "$unionWith",
        // Arrays / expansion
        "$unwind", "$fill", "$densify", "$setWindowFields",
        // Output
        "$out", "$merge",
        // Search / geo / security
        "$search", "$vectorSearch", "$geoNear", "$redact"
    ]

    static func template(for type: String) -> String {
        switch type {
        case "$match":
            return "{\n  \"field\": \"value\"\n}"
        case "$project":
            return "{\n  \"field\": 1,\n  \"_id\": 0\n}"
        case "$addFields", "$set":
            return "{\n  \"newField\": \"$expression\"\n}"
        case "$unset":
            return "\"field\""
        case "$replaceRoot":
            return "{\n  \"newRoot\": \"$subdocField\"\n}"
        case "$replaceWith":
            return "\"$subdocField\""
        case "$group":
            return "{\n  \"_id\": \"$field\",\n  \"count\": { \"$sum\": 1 }\n}"
        case "$bucket":
            return "{\n  \"groupBy\": \"$field\",\n  \"boundaries\": [0, 100, 200],\n  \"default\": \"Other\",\n  \"output\": { \"count\": { \"$sum\": 1 } }\n}"
        case "$bucketAuto":
            return "{\n  \"groupBy\": \"$field\",\n  \"buckets\": 5,\n  \"output\": { \"count\": { \"$sum\": 1 } }\n}"
        case "$count":
            return "\"total\""
        case "$sortByCount":
            return "\"$field\""
        case "$facet":
            return "{\n  \"facetA\": [ { \"$match\": {} } ],\n  \"facetB\": [ { \"$count\": \"total\" } ]\n}"
        case "$sort":
            return "{\n  \"field\": 1\n}"
        case "$limit":
            return "10"
        case "$skip":
            return "0"
        case "$sample":
            return "{\n  \"size\": 100\n}"
        case "$lookup":
            return "{\n  \"from\": \"collection\",\n  \"localField\": \"field\",\n  \"foreignField\": \"_id\",\n  \"as\": \"result\"\n}"
        case "$graphLookup":
            return "{\n  \"from\": \"collection\",\n  \"startWith\": \"$field\",\n  \"connectFromField\": \"field\",\n  \"connectToField\": \"field\",\n  \"as\": \"chain\"\n}"
        case "$unionWith":
            return "{\n  \"coll\": \"otherCollection\",\n  \"pipeline\": []\n}"
        case "$unwind":
            return "\"$arrayField\""
        case "$fill":
            return "{\n  \"output\": { \"field\": { \"method\": \"linear\" } }\n}"
        case "$densify":
            return "{\n  \"field\": \"date\",\n  \"range\": { \"step\": 1, \"unit\": \"day\", \"bounds\": \"full\" }\n}"
        case "$setWindowFields":
            return "{\n  \"partitionBy\": \"$field\",\n  \"sortBy\": { \"date\": 1 },\n  \"output\": {\n    \"runningTotal\": { \"$sum\": \"$amount\", \"window\": { \"documents\": [\"unbounded\", \"current\"] } }\n  }\n}"
        case "$out":
            return "\"outputCollection\""
        case "$merge":
            return "{\n  \"into\": \"targetCollection\",\n  \"on\": \"_id\",\n  \"whenMatched\": \"merge\",\n  \"whenNotMatched\": \"insert\"\n}"
        case "$search":
            return "{\n  \"index\": \"default\",\n  \"text\": { \"query\": \"searchTerm\", \"path\": \"field\" }\n}"
        case "$vectorSearch":
            return "{\n  \"index\": \"vector_index\",\n  \"path\": \"embedding\",\n  \"queryVector\": [],\n  \"numCandidates\": 100,\n  \"limit\": 10\n}"
        case "$geoNear":
            return "{\n  \"near\": { \"type\": \"Point\", \"coordinates\": [0, 0] },\n  \"distanceField\": \"distance\",\n  \"spherical\": true\n}"
        case "$redact":
            return "{\n  \"$cond\": { \"if\": {}, \"then\": \"$$DESCEND\", \"else\": \"$$PRUNE\" }\n}"
        default:
            return "{}"
        }
    }
}
