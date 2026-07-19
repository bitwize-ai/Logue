import SwiftUI

// MARK: - PII Category

enum PIICategory: String, CaseIterable, Identifiable, Codable {
    case identity = "Identity"
    case contact = "Contact"
    case governmentIDs = "Government IDs"
    case financial = "Financial"
    case credentials = "Credentials"
    case health = "Health"
    case employmentEducation = "Employment/Education"
    case biometric = "Biometric"
    case locationDevice = "Location/Device"
    case metadata = "Metadata"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .identity: "person.text.rectangle"
        case .contact: "envelope.fill"
        case .governmentIDs: "creditcard.fill"
        case .financial: "banknote.fill"
        case .credentials: "key.fill"
        case .health: "heart.text.square.fill"
        case .employmentEducation: "graduationcap.fill"
        case .biometric: "faceid"
        case .locationDevice: "location.fill"
        case .metadata: "server.rack"
        }
    }

    var examples: String {
        switch self {
        case .identity: "Name, DOB, Gender"
        case .contact: "Email, Phone, Address, Social handles"
        case .governmentIDs: "SSN, Passport, Driver's license, Tax ID"
        case .financial: "Bank accounts, Cards, Payment accounts, Crypto"
        case .credentials: "Passwords, OTPs, PINs, API keys"
        case .health: "Insurance, Medical records, Prescriptions"
        case .employmentEducation: "Employee ID, Student ID, Transcripts"
        case .biometric: "Fingerprints, Face, Voice, Iris"
        case .locationDevice: "GPS, IP, Device IDs"
        case .metadata: "Cookies, Session IDs, Usernames"
        }
    }

    var risk: PIIRisk {
        switch self {
        case .identity: .medium
        case .contact: .medium
        case .governmentIDs: .high
        case .financial: .high
        case .credentials: .critical
        case .health: .high
        case .employmentEducation: .medium
        case .biometric: .high
        case .locationDevice: .medium
        case .metadata: .medium
        }
    }
}

// MARK: - PII Risk Level

enum PIIRisk: String, Codable, Comparable {
    case medium = "Medium"
    case high = "High"
    case critical = "Critical"

    var color: Color {
        switch self {
        case .medium: AppThemeConstants.warning
        case .high: AppThemeConstants.error
        case .critical: AppThemeConstants.error
        }
    }

    var badgeColor: Color {
        switch self {
        case .medium: AppThemeConstants.warning
        case .high: AppThemeConstants.error
        case .critical: AppThemeConstants.error
        }
    }

    private var sortOrder: Int {
        switch self {
        case .critical: 3
        case .high: 2
        case .medium: 1
        }
    }

    static func < (lhs: PIIRisk, rhs: PIIRisk) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - PII Finding

struct PIIFinding: Identifiable, Codable {
    var id: String {
        "\(category.rawValue)-\(text)"
    }

    let category: PIICategory
    let text: String
    let detail: String

    enum CodingKeys: String, CodingKey {
        case category, text, detail
    }
}
