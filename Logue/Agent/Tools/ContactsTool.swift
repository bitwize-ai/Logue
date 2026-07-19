import Contacts
import Foundation
import MLXLMCommon
import os.log

// MARK: - FetchContactsTool

/// Reads contacts from the user's macOS Contacts app via the `Contacts`
/// framework. Read-only; sandbox-safe given the
/// `com.apple.security.personal-information.contacts` entitlement.
///
/// Clearance is `.sensitive` so the user gets an Approve / Reject card the
/// first time per conversation — this is privacy data and the user should
/// confirm before each access surface.
struct FetchContactsTool: AgentTool {
    let name = "fetch_contacts"
    let description = """
    Look up contacts from the user's macOS Contacts. Returns matching contacts \
    with name, email addresses, and phone numbers. Filter by name, email, or \
    phone number. Returns up to 25 matches. Use this to find a contact's \
    email when drafting messages.
    """
    let clearance: ToolClearance = .sensitive

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "name": AgentToolSpec.stringParam("Filter by name (case-insensitive substring; optional)"),
                "email": AgentToolSpec.stringParam("Filter by email substring (optional)"),
                "phone": AgentToolSpec.stringParam("Filter by phone substring (optional)"),
                "limit": AgentToolSpec.intParam("Maximum results (default 10, max 25)"),
            ]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        let nameFilter = (arguments["name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let emailFilter = (arguments["email"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let phoneFilter = (arguments["phone"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let limit = min((arguments["limit"] as? Int) ?? 10, 25)

        // 1. Permission. Request access — no-op if already granted.
        let store = CNContactStore()
        let granted = await Self.requestAccess(store: store)
        guard granted else {
            throw AgentToolError.executionFailed("Contacts access not granted. Approve it in System Settings → Privacy → Contacts.")
        }

        // 2. Enumerate. CN's predicate API is restrictive (only matches given
        //    name + family name with `CNContact.predicateForContacts(matchingName:)`)
        //    so we do a full enumeration and filter in-process. Caller-supplied
        //    filters are AND-ed.
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)

        var matched: [CNContact] = []
        do {
            try store.enumerateContacts(with: request) { contact, stop in
                if Self.matches(
                    contact,
                    nameFilter: nameFilter, emailFilter: emailFilter, phoneFilter: phoneFilter
                ) {
                    matched.append(contact)
                    if matched.count >= limit {
                        stop.pointee = true
                    }
                }
            }
        } catch {
            throw AgentToolError.executionFailed("Failed to read contacts: \(error.localizedDescription)")
        }

        guard !matched.isEmpty else {
            return "No contacts matched. Try a different name / email / phone fragment."
        }

        // 3. Format. One contact per line block, trimmed to fit a tool result.
        var output = "Found \(matched.count) contact(s):\n"
        for (idx, contact) in matched.enumerated() {
            output += "\n\(idx + 1). \(Self.fullName(contact))"
            if !contact.organizationName.isEmpty {
                output += " (\(contact.organizationName))"
            }
            let emails = contact.emailAddresses.map { String($0.value) }
            if !emails.isEmpty {
                output += "\n   Emails: \(emails.joined(separator: ", "))"
            }
            let phones = contact.phoneNumbers.map(\.value.stringValue)
            if !phones.isEmpty {
                output += "\n   Phones: \(phones.joined(separator: ", "))"
            }
        }
        return output
    }

    // MARK: - Helpers

    private static func fullName(_ contact: CNContact) -> String {
        let parts = [contact.givenName, contact.familyName].filter { !$0.isEmpty }
        if parts.isEmpty {
            return contact.organizationName.isEmpty ? "(unnamed)" : contact.organizationName
        }
        return parts.joined(separator: " ")
    }

    private static func matches(
        _ contact: CNContact,
        nameFilter: String, emailFilter: String, phoneFilter: String
    ) -> Bool {
        if nameFilter.isEmpty, emailFilter.isEmpty, phoneFilter.isEmpty {
            return true
        }
        if !nameFilter.isEmpty {
            let combined = "\(contact.givenName) \(contact.familyName) \(contact.organizationName)".lowercased()
            guard combined.contains(nameFilter) else { return false }
        }
        if !emailFilter.isEmpty {
            let hasMatch = contact.emailAddresses.contains { String($0.value).lowercased().contains(emailFilter) }
            guard hasMatch else { return false }
        }
        if !phoneFilter.isEmpty {
            let hasMatch = contact.phoneNumbers.contains { $0.value.stringValue.lowercased().contains(phoneFilter) }
            guard hasMatch else { return false }
        }
        return true
    }

    private static func requestAccess(store: CNContactStore) async -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .authorized {
            return true
        }
        return await withCheckedContinuation { cont in
            store.requestAccess(for: .contacts) { granted, _ in
                cont.resume(returning: granted)
            }
        }
    }
}
