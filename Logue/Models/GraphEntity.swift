import Foundation

/// A named entity extracted from a meeting or document chunk.
struct GraphEntity: Codable, Identifiable, Equatable {
    var id: String {
        name.lowercased()
    }

    /// Canonical lowercased name (deduplicated at write time).
    let name: String
    /// Coarse type tag: "person", "organization", "topic", "technology", "location", or "other".
    let type: String
    /// Namespaces that contributed chunks to this entity ("meeting", "document").
    var sourceNamespaces: Set<String>
    /// Item IDs (meeting / document UUIDs as strings) that mention this entity.
    var sourceItemIDs: Set<String>

    init(name: String, type: String, namespace: String, itemID: String) {
        self.name = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.type = type
        sourceNamespaces = [namespace]
        sourceItemIDs = [itemID]
    }
}

/// A directed relationship between two entities.
struct GraphRelationship: Codable, Equatable {
    let sourceName: String // lowercased
    let targetName: String // lowercased
    let relationship: String // short verb phrase, e.g. "works at", "mentioned in"
    let sourceItemID: String
}

/// Lightweight JSON wrapper used for LLM entity-extraction responses.
struct EntityExtractionResponse: Codable {
    let entities: [EntityRecord]
    let relationships: [RelationshipRecord]

    struct EntityRecord: Codable {
        let name: String
        let type: String
    }

    struct RelationshipRecord: Codable {
        let source: String
        let target: String
        let relationship: String
    }
}
