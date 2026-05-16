import Foundation

/// A reusable mongosh command the user has saved for quick recall in
/// the Shell view. Mirrors `SavedQuery` for the find/aggregate explorer
/// — same persistence pattern, different payload.
struct SavedCommand: Codable, Identifiable {
    let id: UUID
    var name: String
    var command: String
    var category: String
    var createdAt: Date
    var lastUsedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        command: String,
        category: String = "Custom",
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.category = category
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}
