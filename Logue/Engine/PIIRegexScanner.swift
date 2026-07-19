import Foundation

/// Fast, deterministic PII scanner using regex patterns.
/// Runs instantly as a first pass before optional LLM enhancement.
enum PIIRegexScanner {
    // MARK: - Compiled Regex Cache

    /// Pre-compiled regex cache keyed by pattern+options — avoids recompilation on every scan call.
    private static let regexCache: [String: NSRegularExpression] = {
        var cache: [String: NSRegularExpression] = [:]
        for category in PIICategory.allCases {
            for rule in rules(for: category) {
                let key = "\(rule.pattern)|\(rule.options.rawValue)"
                if cache[key] == nil {
                    cache[key] = try? NSRegularExpression(pattern: rule.pattern, options: rule.options)
                }
            }
        }
        return cache
    }()

    // MARK: - Public API

    /// Scans text for PII matching the enabled categories. Returns deduplicated findings.
    static func scan(text: String, categories: Set<PIICategory>) -> [PIIFinding] {
        var findings: [PIIFinding] = []
        // Strip markdown formatting so **Label:** patterns still match
        let cleaned = stripMarkdown(text)
        let nsText = cleaned as NSString

        for category in categories {
            for rule in rules(for: category) {
                let cacheKey = "\(rule.pattern)|\(rule.options.rawValue)"
                guard let regex = regexCache[cacheKey] else { continue }
                let matches = regex.matches(in: cleaned, range: NSRange(location: 0, length: nsText.length))
                for match in matches {
                    // Use capture group when defined (strips label prefix), otherwise full match
                    let range = rule.captureGroup > 0 && match.numberOfRanges > rule.captureGroup
                        ? match.range(at: rule.captureGroup)
                        : match.range
                    guard range.location != NSNotFound else { continue }
                    let matchedText = nsText.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !matchedText.isEmpty else { continue }
                    findings.append(PIIFinding(category: category, text: matchedText, detail: rule.detail))
                }
            }
        }

        // Deduplicate by (category + text)
        var seen = Set<String>()
        return findings.filter { finding in
            let key = "\(finding.category.rawValue)|\(finding.text)"
            return seen.insert(key).inserted
        }
    }

    // MARK: - Rule Definition

    private struct Rule {
        let pattern: String
        let detail: String
        var options: NSRegularExpression.Options = [.caseInsensitive]
        /// Which capture group holds the actual PII value (0 = full match, 1 = first group).
        var captureGroup: Int = 0
    }

    // MARK: - Category Rules

    private static func rules(for category: PIICategory) -> [Rule] {
        switch category {
        case .identity:
            identityRules
        case .contact:
            contactRules
        case .governmentIDs:
            governmentIDRules
        case .financial:
            financialRules
        case .credentials:
            credentialRules
        case .health:
            healthRules
        case .employmentEducation:
            employmentRules
        case .biometric:
            biometricRules
        case .locationDevice:
            locationDeviceRules
        case .metadata:
            metadataRules
        }
    }

    // MARK: - Identity

    private static let identityRules: [Rule] = [
        // Date of birth – numeric (capture value only)
        Rule(
            pattern: #"(?:DOB|Date of Birth|Born|Birthday|D\.O\.B\.?)\s*[:：]?\s*(\d{1,2}[/\-\.]\d{1,2}[/\-\.]\d{2,4})"#,
            detail: "Date of birth",
            captureGroup: 1
        ),
        // Date of birth – month name (capture value only)
        Rule(
            // swiftlint:disable:next line_length
            pattern: #"(?:DOB|Date of Birth|Born|Birthday|D\.O\.B\.?)\s*[:：]?\s*((?:January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2},?\s+\d{4})"#,
            detail: "Date of birth",
            captureGroup: 1
        ),
        // Age (capture value only)
        Rule(
            pattern: #"(?:Age|Aged)\s*[:：]?\s*(\d{1,3}\s*(?:years?|yrs?|y/?o)?)"#,
            detail: "Age",
            captureGroup: 1
        ),
        // Gender (capture value only)
        Rule(
            pattern: #"(?:Gender|Sex)\s*[:：]\s*((?:Male|Female|Non-binary|Other|M|F)\b)"#,
            detail: "Gender",
            captureGroup: 1
        ),
    ]

    // MARK: - Contact

    private static let contactRules: [Rule] = [
        // Email addresses
        Rule(
            pattern: #"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}"#,
            detail: "Email address",
            options: []
        ),
        // US phone numbers (various formats)
        Rule(
            pattern: #"(?:\+?1[\s\-.]?)?\(?\d{3}\)?[\s\-.]?\d{3}[\s\-.]?\d{4}"#,
            detail: "Phone number"
        ),
        // International phone numbers
        Rule(
            pattern: #"\+\d{1,3}[\s\-.]?\d{1,4}[\s\-.]?\d{3,4}[\s\-.]?\d{3,4}"#,
            detail: "International phone number"
        ),
        // Street addresses (number + street name + type)
        Rule(
            // swiftlint:disable:next line_length
            pattern: #"\d{1,5}\s+(?:[A-Z][a-zA-Z]*\s+){1,3}(?:Street|St|Avenue|Ave|Boulevard|Blvd|Drive|Dr|Lane|Ln|Road|Rd|Way|Court|Ct|Circle|Cir|Place|Pl|Terrace|Ter)\.?\s*(?:#\s*\d+|Suite\s+\d+|Apt\.?\s*\d+|Unit\s+\d+)?"#,
            detail: "Street address"
        ),
        // ZIP codes – capture code only
        Rule(
            pattern: #"(?:zip|postal)\s*(?:code)?\s*[:：]?\s*(\d{5}(?:-\d{4})?)"#,
            detail: "ZIP/postal code",
            captureGroup: 1
        ),
    ]

    // MARK: - Government IDs

    private static let governmentIDRules: [Rule] = [
        // SSN bare – entire match is the PII
        Rule(
            pattern: #"\b\d{3}-\d{2}-\d{4}\b"#,
            detail: "Social Security Number (SSN)"
        ),
        // SSN with label – capture value only
        Rule(
            pattern: #"(?:SSN|Social Security)\s*(?:Number|No\.?|#)?\s*[:：]?\s*(\d{3}[\s\-]?\d{2}[\s\-]?\d{4})"#,
            detail: "Social Security Number (SSN)",
            captureGroup: 1
        ),
        // Passport – capture value only
        Rule(
            pattern: #"(?:Passport)\s*(?:Number|No\.?|#)?\s*[:：]?\s*([A-Z]?\d{6,9})"#,
            detail: "Passport number",
            captureGroup: 1
        ),
        // Driver's license – capture value only
        Rule(
            pattern: #"(?:Driver'?s?\s*License|DL)\s*(?:Number|No\.?|#)?\s*[:：]?\s*([A-Z0-9]{5,15})"#,
            detail: "Driver's license number",
            captureGroup: 1
        ),
        // Tax ID / EIN – capture value only
        Rule(
            pattern: #"(?:Tax\s*ID|TIN|EIN)\s*(?:Number|No\.?|#)?\s*[:：]?\s*(\d{2}-?\d{7})"#,
            detail: "Tax ID / EIN",
            captureGroup: 1
        ),
        // Visa number – capture value only
        Rule(
            pattern: #"(?:Visa)\s*(?:Number|No\.?|#)?\s*[:：]?\s*([A-Z0-9]{8,12})"#,
            detail: "Visa number",
            captureGroup: 1
        ),
        // Generic government ID – capture value only
        Rule(
            pattern: #"(?:National\s*ID|Government\s*ID|State\s*ID|ID\s*Number)\s*(?:No\.?|#)?\s*[:：]?\s*([A-Z0-9\-]{5,15})"#,
            detail: "Government ID number",
            captureGroup: 1
        ),
    ]

    // MARK: - Financial

    private static let financialRules: [Rule] = [
        // Credit card numbers (Visa, MC, Amex, Discover)
        Rule(
            pattern: #"\b(?:4\d{3}|5[1-5]\d{2}|3[47]\d{2}|6(?:011|5\d{2}))[\s\-]?\d{4}[\s\-]?\d{4}[\s\-]?\d{3,4}\b"#,
            detail: "Credit/debit card number"
        ),
        // Bank account – capture value only
        Rule(
            pattern: #"(?:Account|Acct)\s*(?:Number|No\.?|#)?\s*[:：]?\s*(\d{8,17})"#,
            detail: "Bank account number",
            captureGroup: 1
        ),
        // Routing number – capture value only
        Rule(
            pattern: #"(?:Routing|ABA)\s*(?:Number|No\.?|#)?\s*[:：]?\s*(\d{9})"#,
            detail: "Bank routing number",
            captureGroup: 1
        ),
        // IBAN
        Rule(
            pattern: #"\b[A-Z]{2}\d{2}[\s]?[A-Z0-9]{4}[\s]?(?:\d{4}[\s]?){2,7}\d{1,4}\b"#,
            detail: "IBAN",
            options: []
        ),
        // Crypto wallet addresses (Bitcoin)
        Rule(
            pattern: #"\b[13][a-km-zA-HJ-NP-Z1-9]{25,34}\b"#,
            detail: "Bitcoin wallet address",
            options: []
        ),
        // Crypto wallet addresses (Ethereum)
        Rule(
            pattern: #"\b0x[a-fA-F0-9]{40}\b"#,
            detail: "Ethereum wallet address"
        ),
    ]

    // MARK: - Credentials

    private static let credentialRules: [Rule] = [
        // Passwords – capture value only
        Rule(
            pattern: #"(?:Password|Passwd|Pass|PIN)\s*[:：]\s*(\S+)"#,
            detail: "Password or PIN",
            captureGroup: 1
        ),
        // API keys / tokens – capture value only
        Rule(
            pattern: #"(?:API[_\s]?Key|API[_\s]?Token|Secret[_\s]?Key|Access[_\s]?Token|Auth[_\s]?Token)\s*[:：=]\s*(\S+)"#,
            detail: "API key or token",
            captureGroup: 1
        ),
        // Bearer tokens – capture token value only (strips "Bearer " prefix)
        Rule(
            pattern: #"Bearer\s+([A-Za-z0-9\-._~+/]+=*)"#,
            detail: "Bearer token",
            options: [],
            captureGroup: 1
        ),
        // AWS keys
        Rule(
            pattern: #"(?:AKIA|ASIA)[A-Z0-9]{16}"#,
            detail: "AWS access key",
            options: []
        ),
        // Generic secret patterns
        Rule(
            pattern: #"(?:sk|pk)[-_](?:live|test)[-_][A-Za-z0-9]{20,}"#,
            detail: "API secret key",
            options: []
        ),
    ]

    // MARK: - Health

    private static let healthRules: [Rule] = [
        // Insurance/Member ID – capture value only
        Rule(
            pattern: #"(?:Insurance|Member|Policy|Subscriber)\s*(?:ID|Number|No\.?|#)\s*[:：]?\s*([A-Z0-9\-]{5,20})"#,
            detail: "Insurance/member ID",
            captureGroup: 1
        ),
        // Medical Record Number – capture value only
        Rule(
            pattern: #"(?:MRN|Medical\s*Record|Patient\s*ID|Chart)\s*(?:Number|No\.?|#)?\s*[:：]?\s*([A-Z0-9\-]{4,15})"#,
            detail: "Medical record number",
            captureGroup: 1
        ),
        // NPI – capture value only
        Rule(
            pattern: #"(?:NPI)\s*[:：]?\s*(\d{10})"#,
            detail: "National Provider Identifier (NPI)",
            captureGroup: 1
        ),
        // DEA number – capture value only
        Rule(
            pattern: #"(?:DEA)\s*(?:Number|No\.?|#)?\s*[:：]?\s*([A-Z]{2}\d{7})"#,
            detail: "DEA number",
            captureGroup: 1
        ),
        // ICD codes
        Rule(
            pattern: #"\b[A-Z]\d{2}(?:\.\d{1,4})?\b"#,
            detail: "ICD diagnosis code",
            options: []
        ),
        // Prescription/medication – capture drug + dosage only
        Rule(
            pattern: #"(?:prescribed|taking|medication|Rx)\s*[:：]?\s*([A-Z][a-z]+\s+\d+\s*(?:mg|mcg|ml|units?))"#,
            detail: "Prescription/medication",
            captureGroup: 1
        ),
        // NDC – capture value only
        Rule(
            pattern: #"(?:NDC)\s*[:：]?\s*(\d{4,5}-\d{3,4}-\d{1,2})"#,
            detail: "National Drug Code (NDC)",
            captureGroup: 1
        ),
        // Group number – capture value only
        Rule(
            pattern: #"(?:Group)\s*(?:Number|No\.?|#)\s*[:：]?\s*([A-Z0-9\-]{3,15})"#,
            detail: "Insurance group number",
            captureGroup: 1
        ),
    ]

    // MARK: - Employment/Education

    private static let employmentRules: [Rule] = [
        // Employee ID – capture value only
        Rule(
            pattern: #"(?:Employee|Staff|Worker|Personnel)\s*(?:ID|Number|No\.?|#)\s*[:：]?\s*([A-Z0-9\-]{3,15})"#,
            detail: "Employee ID",
            captureGroup: 1
        ),
        // Student ID – capture value only
        Rule(
            pattern: #"(?:Student)\s*(?:ID|Number|No\.?|#)\s*[:：]?\s*([A-Z0-9\-]{4,15})"#,
            detail: "Student ID",
            captureGroup: 1
        ),
        // Salary/compensation – capture value only
        Rule(
            pattern: #"(?:Salary|Compensation|Base\s*Pay|Annual\s*Pay|Wage)\s*[:：]?\s*(\$[\d,]+(?:\.\d{2})?)"#,
            detail: "Salary/compensation",
            captureGroup: 1
        ),
    ]

    // MARK: - Biometric

    private static let biometricRules: [Rule] = [
        // Biometric identifiers – capture value only
        Rule(
            pattern: #"(?:fingerprint|biometric|retina|iris|voiceprint|face\s*ID)\s*(?:ID|hash|data|scan|template)\s*[:：]?\s*(\S+)"#,
            detail: "Biometric identifier",
            captureGroup: 1
        ),
    ]

    // MARK: - Location/Device

    private static let locationDeviceRules: [Rule] = [
        // IPv4
        Rule(
            // swiftlint:disable:next line_length
            pattern: #"\b(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b"#,
            detail: "IPv4 address"
        ),
        // IPv6 (simplified)
        Rule(
            pattern: #"\b(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\b"#,
            detail: "IPv6 address"
        ),
        // MAC address
        Rule(
            pattern: #"\b(?:[0-9A-Fa-f]{2}[:\-]){5}[0-9A-Fa-f]{2}\b"#,
            detail: "MAC address"
        ),
        // GPS coordinates – capture value only
        Rule(
            pattern: #"(?:GPS|Coordinates?|Lat(?:itude)?|Lon(?:gitude)?)\s*[:：]?\s*(-?\d{1,3}\.\d{4,})"#,
            detail: "GPS coordinates",
            captureGroup: 1
        ),
        // Device IDs – capture value only
        Rule(
            pattern: #"(?:IMEI|UDID|Device\s*ID|Serial\s*Number|Serial\s*No)\s*[:：]?\s*([A-Z0-9\-]{10,20})"#,
            detail: "Device identifier",
            captureGroup: 1
        ),
    ]

    // MARK: - Metadata

    private static let metadataRules: [Rule] = [
        // Session IDs – capture value only
        Rule(
            pattern: #"(?:Session|Token)\s*(?:ID)?\s*[:：=]\s*([A-Za-z0-9\-]{16,})"#,
            detail: "Session ID",
            captureGroup: 1
        ),
        // Cookies – capture value only
        Rule(
            pattern: #"(?:Cookie|Set-Cookie)\s*[:：=]\s*(\S+)"#,
            detail: "Cookie value",
            captureGroup: 1
        ),
        // UUIDs (standalone, not in code context)
        Rule(
            pattern: #"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"#,
            detail: "UUID identifier"
        ),
    ]

    // MARK: - Markdown Stripping

    /// Removes markdown bold/italic markers so labeled PII patterns match.
    /// Uses a single pre-compiled regex instead of 11 sequential string replacements.
    /// Pre-compiled regex matching markdown markers: **, __, headings, list dashes, standalone asterisks.
    private static let markdownStripRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: #"\*\*|__|#{1,3}\s|(?<=\s)\*(?=\s)|- "#)

    private static func stripMarkdown(_ text: String) -> String {
        guard let regex = markdownStripRegex else { return text }
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: ""
        )
    }
}
