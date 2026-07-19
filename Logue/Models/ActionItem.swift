import Foundation

/// A single action item extracted from a meeting transcript by the LLM.
struct ActionItem: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String
    var assignee: String?
    var dueDescription: String?
    var isCompleted: Bool
    let createdAt: Date
    var dueDate: Date?
    var reminderDate: Date?
    var notificationID: String?

    init(
        id: UUID = .init(),
        title: String,
        assignee: String? = nil,
        dueDescription: String? = nil,
        isCompleted: Bool = false,
        createdAt: Date = .now,
        dueDate: Date? = nil,
        reminderDate: Date? = nil,
        notificationID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.assignee = assignee
        self.dueDescription = dueDescription
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.dueDate = dueDate
        self.reminderDate = reminderDate
        self.notificationID = notificationID
    }

    // MARK: - Codable (backwards-compatible)

    enum CodingKeys: String, CodingKey {
        case id, title, assignee, dueDescription, isCompleted, createdAt
        case dueDate, reminderDate, notificationID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        assignee = try container.decodeIfPresent(String.self, forKey: .assignee)
        dueDescription = try container.decodeIfPresent(String.self, forKey: .dueDescription)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        reminderDate = try container.decodeIfPresent(Date.self, forKey: .reminderDate)
        notificationID = try container.decodeIfPresent(String.self, forKey: .notificationID)
    }
}
