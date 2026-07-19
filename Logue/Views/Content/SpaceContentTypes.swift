import SwiftUI

// MARK: - Space Item

/// A unified item type for mixed display in a space.
enum SpaceItem: Identifiable {
    case document(WritingDocument)
    case meeting(MeetingNote)
    case space(Space)

    var id: UUID {
        switch self {
        case let .document(doc): doc.id
        case let .meeting(meeting): meeting.id
        case let .space(space): space.id
        }
    }

    var title: String {
        switch self {
        case let .document(doc): doc.title
        case let .meeting(meeting): meeting.title
        case let .space(space): space.name
        }
    }

    var modifiedAt: Date {
        switch self {
        case let .document(doc): doc.modifiedAt
        case let .meeting(meeting): meeting.modifiedAt
        case let .space(space): space.createdAt
        }
    }

    var createdAt: Date {
        switch self {
        case let .document(doc): doc.createdAt
        case let .meeting(meeting): meeting.createdAt
        case let .space(space): space.createdAt
        }
    }
}

// MARK: - Filter & Sort

enum SpaceFilterType: CaseIterable {
    case all, documents, meetings

    var label: String {
        switch self {
        case .all: "All"
        case .documents: "Documents"
        case .meetings: "Meetings"
        }
    }

    var icon: String {
        switch self {
        case .all: "square.grid.2x2"
        case .documents: "doc.text"
        case .meetings: "waveform"
        }
    }
}

enum SpaceSortOrder: CaseIterable {
    case modifiedNewest, modifiedOldest, titleAZ, titleZA, createdNewest, createdOldest

    var label: String {
        switch self {
        case .modifiedNewest: "Modified (Newest)"
        case .modifiedOldest: "Modified (Oldest)"
        case .titleAZ: "Title (A-Z)"
        case .titleZA: "Title (Z-A)"
        case .createdNewest: "Created (Newest)"
        case .createdOldest: "Created (Oldest)"
        }
    }
}

// MARK: - Sidebar Space Sort

enum SidebarSpaceSortOrder: String, CaseIterable {
    case custom
    case nameAZ
    case nameZA
    case createdNewest
    case createdOldest

    var label: String {
        switch self {
        case .custom: "Custom"
        case .nameAZ: "Name (A–Z)"
        case .nameZA: "Name (Z–A)"
        case .createdNewest: "Date Created (Newest)"
        case .createdOldest: "Date Created (Oldest)"
        }
    }
}
