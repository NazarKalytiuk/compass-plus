import Foundation
import SwiftUI

struct ConnectionModel: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var uri: String
    var environment: ConnectionEnvironment
    var lastUsed: Date
    var pingMs: Int?

    init(id: UUID = UUID(), name: String, uri: String, environment: ConnectionEnvironment = .local, lastUsed: Date = Date(), pingMs: Int? = nil) {
        self.id = id
        self.name = name
        self.uri = uri
        self.environment = environment
        self.lastUsed = lastUsed
        self.pingMs = pingMs
    }

    enum ConnectionEnvironment: String, Codable, CaseIterable {
        case local, staging, production

        var displayName: String {
            rawValue.capitalized
        }

        var color: Color {
            switch self {
            case .local: return Theme.green
            case .staging: return Theme.amber
            case .production: return Theme.crimson
            }
        }
    }

    var hostDisplay: String {
        // Extract host:port from MongoDB URI
        let cleaned = uri.replacingOccurrences(of: "mongodb://", with: "")
            .replacingOccurrences(of: "mongodb+srv://", with: "")
        // Remove credentials
        if let atIndex = cleaned.firstIndex(of: "@") {
            let afterAt = cleaned[cleaned.index(after: atIndex)...]
            if let slashIndex = afterAt.firstIndex(of: "/") {
                return String(afterAt[afterAt.startIndex..<slashIndex])
            }
            return String(afterAt)
        }
        if let slashIndex = cleaned.firstIndex(of: "/") {
            return String(cleaned[cleaned.startIndex..<slashIndex])
        }
        return cleaned
    }
}
