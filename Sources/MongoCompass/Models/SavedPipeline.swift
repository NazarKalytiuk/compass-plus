import Foundation

struct SavedPipeline: Codable, Identifiable {
    let id: UUID
    var name: String
    var database: String
    var collection: String
    var stages: [PipelineStage]

    init(id: UUID = UUID(), name: String, database: String, collection: String, stages: [PipelineStage] = []) {
        self.id = id
        self.name = name
        self.database = database
        self.collection = collection
        self.stages = stages
    }
}
