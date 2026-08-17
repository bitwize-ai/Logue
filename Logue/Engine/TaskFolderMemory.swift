import Foundation

/// Which tasks folder this app believes is its own.
///
/// Small, and separate from `TaskStorage`, for one reason: the rule it holds has been got wrong
/// in three consecutive rounds of review, every time because it lived in a static that read
/// `UserDefaults.standard` and could not be driven from a test. `TaskFolderStore`'s own header
/// draws this line already — "takes its root as a parameter rather than reading a singleton, so
/// it is testable" — and this is the state that was left on the wrong side of it.
///
/// The rule itself is one sentence: **learn once, forget deliberately.**
///
/// - *Learn once*, because refreshing on every resolve destroyed the sequence the memory exists
///   for. With the real folder in the Trash, a task write mints a replacement; on the next launch
///   that replacement is the only marked folder, so it was returned *and* remembered, and
///   restoring the original then lost the election exactly as it had before the memory existed.
/// - *Forget deliberately*, because the opposite failure is just as real: a folder the user
///   actually told the app to throw away must stop being the one it looks for, or restoring it
///   for some unrelated reason hands them a library they had deleted.
struct TaskFolderMemory {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = AppConstants.UserDefaultsKeys.lastTaskFolderMarker
    ) {
        self.defaults = defaults
        self.key = key
    }

    /// The marker of the folder this app is using, if it has settled on one.
    var remembered: UUID? {
        defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    /// Records a folder as this app's, the first time it learns.
    ///
    /// Returns whether anything was written, so a caller can tell "already knew" from "just
    /// learned" without reading the value back.
    @discardableResult
    func rememberIfUnknown(_ marker: UUID?) -> Bool {
        guard remembered == nil, let marker else { return false }
        defaults.set(marker.uuidString, forKey: key)
        return true
    }

    /// Stops believing in the remembered folder.
    ///
    /// For the moments the user says so: clearing example data, and the two paths that retire
    /// the markdown folder on a switch out of plain-markdown storage. Ordering matters at every
    /// one of them — resolving the folder in order to trash it is itself an act that can
    /// re-learn it, so this belongs *after* the folder is gone, never before.
    func forget() {
        defaults.removeObject(forKey: key)
    }
}
