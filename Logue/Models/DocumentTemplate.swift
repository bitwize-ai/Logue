import Foundation

// MARK: - Template Category

/// Categories for organizing document templates.
enum TemplateCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case meetingNotes = "Meeting Notes"
    case projectManagement = "Project Management"
    case business = "Business"
    case marketing = "Marketing"
    case engineering = "Engineering"
    case hr = "HR & People"
    case finance = "Finance"
    case academic = "Academic"
    case personal = "Personal"
    case communication = "Communication"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .meetingNotes: "note.text"
        case .projectManagement: "list.clipboard"
        case .business: "briefcase"
        case .marketing: "megaphone"
        case .engineering: "wrench.and.screwdriver"
        case .hr: "person.2"
        case .finance: "dollarsign.circle"
        case .academic: "graduationcap"
        case .personal: "person"
        case .communication: "envelope"
        }
    }
}

// MARK: - Document Template

/// A reusable document template with pre-filled markdown content.
struct DocumentTemplate: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var category: TemplateCategory
    var icon: String
    var description: String
    var body: String
    var isBuiltIn: Bool
    var createdAt: Date

    init(
        id: UUID = .init(),
        name: String,
        category: TemplateCategory,
        icon: String,
        description: String,
        body: String,
        isBuiltIn: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.icon = icon
        self.description = description
        self.body = body
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
    }
}
