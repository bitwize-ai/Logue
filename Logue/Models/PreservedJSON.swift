import Foundation

/// A value of any JSON shape, preserved exactly.
///
/// Named `PreservedJSON` rather than `JSONValue` because the agent tooling already has a `JSONValue`
/// for a different job — describing tool-call schemas.
///
/// Exists so a persisted enum can keep a case it does not understand. Without somewhere to put the
/// original payload, tolerating an unknown tag means discarding its value — which turns "a newer
/// build wrote something I cannot read" into data loss on the way back up.
indirect enum PreservedJSON: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case array([PreservedJSON])
    case object([String: PreservedJSON])
    case null

    /// How the value reads when there is nothing better to show.
    var displayString: String {
        switch self {
        case let .string(value):
            return value
        case let .number(value):
            guard value == value.rounded(), abs(value) < 1e15 else { return String(value) }
            return String(Int(value))
        case let .boolean(value):
            return value ? "Yes" : "No"
        case let .array(values):
            return values.map(\.displayString).joined(separator: ", ")
        case .object, .null:
            return "—"
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            // Before `Double`: JSON `true` decodes as a number on some platforms.
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([PreservedJSON].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: PreservedJSON].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Not a JSON value"
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .boolean(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
