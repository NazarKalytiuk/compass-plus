import Foundation

// MARK: - Format Enums

enum ExportFormat: String, CaseIterable {
    case jsonArray = "JSON Array"
    case ndjson = "NDJSON"
    case csv = "CSV"

    var fileExtension: String {
        switch self {
        case .jsonArray: return "json"
        case .ndjson: return "ndjson"
        case .csv: return "csv"
        }
    }
}

enum ImportFormat: String, CaseIterable {
    case jsonArray = "JSON Array"
    case ndjson = "NDJSON"
    case csv = "CSV"

    var fileExtension: String {
        switch self {
        case .jsonArray: return "json"
        case .ndjson: return "ndjson"
        case .csv: return "csv"
        }
    }
}

// MARK: - ImportExportError

enum ImportExportError: LocalizedError {
    case invalidData(String)
    case unsupportedFormat(String)
    case writeError(String)

    var errorDescription: String? {
        switch self {
        case .invalidData(let detail):
            return "Invalid data: \(detail)"
        case .unsupportedFormat(let detail):
            return "Unsupported format: \(detail)"
        case .writeError(let detail):
            return "Write error: \(detail)"
        }
    }
}

// MARK: - ImportExportService

struct ImportExportService {

    // MARK: - Export

    func exportDocuments(_ documents: [[String: Any]], format: ExportFormat, to url: URL) throws {
        guard !documents.isEmpty else {
            throw ImportExportError.invalidData("No documents to export.")
        }

        let data: Data
        switch format {
        case .jsonArray:
            data = try exportAsJSONArray(documents)
        case .ndjson:
            data = try exportAsNDJSON(documents)
        case .csv:
            data = try exportAsCSV(documents)
        }

        try data.write(to: url, options: .atomic)
    }

    private func exportAsJSONArray(_ documents: [[String: Any]]) throws -> Data {
        let cleaned = documents.map { sanitizeForJSON($0) }
        return try JSONSerialization.data(withJSONObject: cleaned, options: [.prettyPrinted, .sortedKeys])
    }

    private func exportAsNDJSON(_ documents: [[String: Any]]) throws -> Data {
        var lines: [String] = []
        for doc in documents {
            let cleaned = sanitizeForJSON(doc)
            let lineData = try JSONSerialization.data(withJSONObject: cleaned, options: [.sortedKeys])
            guard let lineStr = String(data: lineData, encoding: .utf8) else {
                throw ImportExportError.writeError("Failed to encode document as UTF-8.")
            }
            lines.append(lineStr)
        }
        let joined = lines.joined(separator: "\n")
        guard let data = joined.data(using: .utf8) else {
            throw ImportExportError.writeError("Failed to encode NDJSON output as UTF-8.")
        }
        return data
    }

    private func exportAsCSV(_ documents: [[String: Any]]) throws -> Data {
        // Gather all unique top-level keys from all documents for headers.
        var headersSet: [String: Int] = [:]
        var orderIndex = 0
        for doc in documents {
            for key in doc.keys {
                if headersSet[key] == nil {
                    headersSet[key] = orderIndex
                    orderIndex += 1
                }
            }
        }
        let headers = headersSet.sorted { $0.value < $1.value }.map(\.key)

        var csvLines: [String] = []
        // Header row
        csvLines.append(headers.map { escapeCSVField($0) }.joined(separator: ","))

        // Data rows
        for doc in documents {
            let row = headers.map { key -> String in
                guard let value = doc[key] else { return "" }
                return escapeCSVField(csvStringValue(value))
            }
            csvLines.append(row.joined(separator: ","))
        }

        let csvString = csvLines.joined(separator: "\n")
        guard let data = csvString.data(using: .utf8) else {
            throw ImportExportError.writeError("Failed to encode CSV output as UTF-8.")
        }
        return data
    }

    // MARK: - Import

    func importDocuments(from url: URL, format: ImportFormat) throws -> [[String: Any]] {
        let data = try Data(contentsOf: url)

        switch format {
        case .jsonArray:
            return try importFromJSONArray(data)
        case .ndjson:
            return try importFromNDJSON(data)
        case .csv:
            return try importFromCSV(data)
        }
    }

    private func importFromJSONArray(_ data: Data) throws -> [[String: Any]] {
        let obj = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        guard let array = obj as? [[String: Any]] else {
            throw ImportExportError.invalidData("Expected a JSON array of objects at the top level.")
        }
        return array
    }

    private func importFromNDJSON(_ data: Data) throws -> [[String: Any]] {
        guard let content = String(data: data, encoding: .utf8) else {
            throw ImportExportError.invalidData("Unable to decode file as UTF-8.")
        }
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var documents: [[String: Any]] = []
        for (lineNumber, line) in lines.enumerated() {
            guard let lineData = line.data(using: .utf8) else {
                throw ImportExportError.invalidData("Failed to encode line \(lineNumber + 1) as UTF-8.")
            }
            let obj = try JSONSerialization.jsonObject(with: lineData, options: .fragmentsAllowed)
            guard let dict = obj as? [String: Any] else {
                throw ImportExportError.invalidData("Line \(lineNumber + 1) is not a JSON object.")
            }
            documents.append(dict)
        }
        return documents
    }

    private func importFromCSV(_ data: Data) throws -> [[String: Any]] {
        guard let content = String(data: data, encoding: .utf8) else {
            throw ImportExportError.invalidData("Unable to decode file as UTF-8.")
        }
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else {
            throw ImportExportError.invalidData("CSV file must have at least a header row and one data row.")
        }

        let headers = parseCSVLine(lines[0])
        var documents: [[String: Any]] = []

        for i in 1..<lines.count {
            let fields = parseCSVLine(lines[i])
            var doc: [String: Any] = [:]
            for (index, header) in headers.enumerated() {
                let value: String = index < fields.count ? fields[index] : ""
                doc[header] = inferType(value)
            }
            documents.append(doc)
        }
        return documents
    }

    // MARK: - CSV Helpers

    /// Parse a single CSV line respecting quoted fields.
    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()

        while let char = iterator.next() {
            if inQuotes {
                if char == "\"" {
                    // Check for escaped quote ""
                    // We need to peek ahead. Since we cannot with the iterator,
                    // we'll handle it by checking the next character.
                    current.append(char)
                    // We'll fix double-quote handling after the loop.
                    inQuotes = false
                } else {
                    current.append(char)
                }
            } else {
                if char == "\"" {
                    inQuotes = true
                    // If current ends with a quote, it's an escaped quote.
                    if current.hasSuffix("\"") {
                        current.removeLast()
                        current.append("\"")
                    }
                } else if char == "," {
                    fields.append(current)
                    current = ""
                } else {
                    current.append(char)
                }
            }
        }
        fields.append(current)

        // Clean up: remove surrounding quotes from fields
        return fields.map { field in
            var f = field
            if f.hasPrefix("\"") && f.hasSuffix("\"") && f.count >= 2 {
                f = String(f.dropFirst().dropLast())
            }
            return f.replacingOccurrences(of: "\"\"", with: "\"")
        }
    }

    /// Escape a value for CSV output.
    private func escapeCSVField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    /// Convert a value to its CSV string representation.
    private func csvStringValue(_ value: Any) -> String {
        switch value {
        case let str as String:
            return str
        case let num as NSNumber:
            return num.stringValue
        case let bool as Bool:
            return bool ? "true" : "false"
        case is NSNull:
            return ""
        case let dict as [String: Any]:
            if let data = try? JSONSerialization.data(withJSONObject: sanitizeForJSON(dict), options: []),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            return "{}"
        case let arr as [Any]:
            if let data = try? JSONSerialization.data(withJSONObject: arr, options: []),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            return "[]"
        default:
            return "\(value)"
        }
    }

    /// Infer the Swift type from a CSV string value.
    private func inferType(_ value: String) -> Any {
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty || trimmed.lowercased() == "null" {
            return NSNull()
        }
        if trimmed.lowercased() == "true" {
            return true
        }
        if trimmed.lowercased() == "false" {
            return false
        }
        if let intVal = Int(trimmed) {
            return intVal
        }
        if let doubleVal = Double(trimmed), trimmed.contains(".") {
            return doubleVal
        }
        return trimmed
    }

    /// Recursively sanitize a dictionary so that all values are JSON-serializable.
    private func sanitizeForJSON(_ dict: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dict {
            result[key] = sanitizeValueForJSON(value)
        }
        return result
    }

    /// Sanitize a single value for JSON serialization.
    private func sanitizeValueForJSON(_ value: Any) -> Any {
        switch value {
        case let dict as [String: Any]:
            return sanitizeForJSON(dict)
        case let arr as [Any]:
            return arr.map { sanitizeValueForJSON($0) }
        case is NSNull:
            return NSNull()
        case let bool as Bool:
            return bool
        case let num as NSNumber:
            return num
        case let str as String:
            return str
        case let data as Data:
            return data.base64EncodedString()
        default:
            return "\(value)"
        }
    }
}
