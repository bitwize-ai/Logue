import Foundation
import Testing

@testable import Logue

/// The `+` menu both composers mount, and the storage that keeps them apart.
///
/// The menu itself is a SwiftUI `Menu` and cannot be exercised headlessly. What can be —
/// and what actually regressed once already — is which `UserDefaults` key each surface
/// arms, and whether the menu has words to show.
@Suite("ComposerPlusMenu")
struct ComposerPlusMenuTests {
    @Test("The island arms its own keys, never the main window's")
    func islandKeysAreItsOwn() {
        // The regression this guards, fixed once already in review: both surfaces bound the
        // same key, and the island clears its flags after every send — so a quick question
        // asked from the island disarmed a Search or Deep Research chip the user had turned
        // on in the main window and left on an unsent prompt. It then ran without the tools
        // and never said why.
        #expect(
            AppConstants.UserDefaultsKeys.islandOneShotWebSearch
                != AppConstants.UserDefaultsKeys.oneShotWebSearch
        )
        #expect(
            AppConstants.UserDefaultsKeys.islandOneShotDeepResearch
                != AppConstants.UserDefaultsKeys.oneShotDeepResearch
        )
    }

    @Test("No two of the four one-shot keys collide")
    func allFourKeysAreDistinct() {
        let keys = Set([
            AppConstants.UserDefaultsKeys.oneShotWebSearch,
            AppConstants.UserDefaultsKeys.oneShotDeepResearch,
            AppConstants.UserDefaultsKeys.islandOneShotWebSearch,
            AppConstants.UserDefaultsKeys.islandOneShotDeepResearch,
        ])
        #expect(keys.count == 4)
    }

    @Test("Every menu item has something to say")
    func menuCopyIsPresent() {
        for label in [
            UICopy.Input.addFiles,
            UICopy.Input.searchTheWeb,
            UICopy.Input.deepResearchMenu,
            UICopy.Input.toolSettings,
            UICopy.Input.composerMenuHelp,
            UICopy.Input.composerMenuLabel,
        ] {
            #expect(!label.isEmpty)
        }
    }

    @Test("The menu's own label is a name, not its icon")
    func menuLabelIsNotASymbolName() {
        // Same rule the island's other controls follow: a Button whose only content is an
        // Image hands VoiceOver the SF Symbol name unless something else names it.
        #expect(!UICopy.Input.composerMenuLabel.contains("."))
        #expect(UICopy.Input.composerMenuLabel.first?.isUppercase == true)
    }
}
