import Foundation

/// Editor content width for a document.
///
/// `normal` suits focused prose; `wide` suits tables, diagrams, and generated
/// documents. Stored per document so an individual document can override the
/// app-wide default.
enum DocumentWidthMode: String, Codable, CaseIterable, Sendable {
    case normal
    case wide

    /// The measure this mode reads at before the pane is wide enough for the column
    /// to start growing. The column is never narrower than this unless the pane is.
    var baseContentWidth: CGFloat {
        switch self {
        case .normal: AppConstants.Editor.normalBaseContentWidth
        case .wide: AppConstants.Editor.wideBaseContentWidth
        }
    }

    /// Share of the editor pane the column grows to occupy.
    var widthFraction: CGFloat {
        switch self {
        case .normal: AppConstants.Editor.normalWidthFraction
        case .wide: AppConstants.Editor.wideWidthFraction
        }
    }

    /// Ceiling on the grown column, past which a line is too long to read comfortably.
    var maxContentWidth: CGFloat {
        switch self {
        case .normal: AppConstants.Editor.normalMaxContentWidth
        case .wide: AppConstants.Editor.wideMaxContentWidth
        }
    }

    var toggled: DocumentWidthMode {
        self == .normal ? .wide : .normal
    }

    var label: String {
        switch self {
        case .normal: "Normal width"
        case .wide: "Wide width"
        }
    }

    var symbolName: String {
        switch self {
        case .normal: "rectangle.portrait"
        case .wide: "rectangle"
        }
    }

    /// The app-wide default a newly created document starts at, from Settings → General.
    ///
    /// Read straight from `UserDefaults` rather than through `@AppStorage` because the
    /// caller is `DocumentStore`, not a view. An unset or unrecognised value reads as
    /// `normal`, which is also what an unset per-document value means.
    static var appDefault: DocumentWidthMode {
        guard let raw = UserDefaults.standard.string(
            forKey: AppConstants.UserDefaultsKeys.defaultDocumentWidthMode
        )
        else { return .normal }
        return DocumentWidthMode(rawValue: raw) ?? .normal
    }
}
