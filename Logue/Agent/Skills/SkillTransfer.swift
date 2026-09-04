import AppKit
import Foundation
import os.log
import UniformTypeIdentifiers

/// Moving skills between this Mac and a file.
///
/// #64 asks that skills "export and import as plain files", which is a claim about the
/// filesystem rather than about a format — the format is `SkillFile`'s. This is the half that
/// presents a panel, reads bytes, and says what happened.
///
/// The panel is presented rather than a path invented: this is the user's filesystem, and a
/// silent write into Documents is how a feature becomes something people cannot find again.
/// `MessageActions.exportMarkdown` makes the same argument for the same reason.
@MainActor
enum SkillTransfer {
    private static let logger = Logger(subsystem: AppConstants.bundleID, category: "Skills")

    /// Files we will read a skill out of.
    ///
    /// Markdown and plain text: a skill file is frontmatter plus prose, and the extension a
    /// person gives it is not something to be strict about.
    static var acceptedTypes: [UTType] {
        [UTType("net.daringfireball.markdown"), .plainText, .text].compactMap(\.self)
    }

    /// Writes one skill to a file the user picks.
    static func export(_ skill: AgentSkill) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = acceptedTypes
        panel.nameFieldStringValue = "\(skill.invocation).md"
        panel.canCreateDirectories = true
        panel.message = "Save this skill as a file you can share."

        let text = SkillFile.render(skill)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                // Surfaced, not only logged: the user asked for a file and there is now no
                // file, which is not a thing to find out about later.
                Task { @MainActor in
                    ToastCenter.shared.show("Could not export the skill: \(error.localizedDescription)")
                }
                Self.logger.error("Skill export failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Reads skills out of files the user picks, and adds them.
    ///
    /// Returns how many landed. A file that cannot be read costs that file and nothing else —
    /// picking six and losing all of them because one had the wrong encoding would be the
    /// worst possible reading of "import".
    @discardableResult
    static func importSkills(into store: SkillStore) async -> Int {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = acceptedTypes
        panel.prompt = "Import"
        panel.message = "Choose skill files to import."

        let urls: [URL] = await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.urls : [])
            }
        }
        guard !urls.isEmpty else { return 0 }

        var texts: [String] = []
        for url in urls {
            do {
                try texts.append(String(contentsOf: url, encoding: .utf8))
            } catch {
                // The name, never the path — the project rule is that a full path does not go
                // into a log, and a filename is what the user recognises anyway.
                logger.error(
                    "Could not read a skill file named \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        let taken = store.importSkills(from: texts)
        // Said out loud, including when it is zero. An import that quietly does nothing is
        // indistinguishable from one that worked.
        ToastCenter.shared.show(summary(taken: taken, chosen: urls.count))
        return taken
    }

    /// What to say after an import.
    ///
    /// Pure and separate so the wording is testable without a panel — the counts are the part
    /// that is easy to get wrong, and "1 skills" is the kind of thing nobody notices until it
    /// ships.
    static func summary(taken: Int, chosen: Int) -> String {
        switch (taken, chosen) {
        case (0, _):
            "Nothing could be imported from \(count(chosen, "file"))."
        case let (taken, chosen) where taken == chosen:
            "Imported \(count(taken, "skill"))."
        case let (taken, chosen):
            "Imported \(count(taken, "skill")) of \(chosen)."
        }
    }

    private static func count(_ number: Int, _ noun: String) -> String {
        "\(number) \(noun)\(number == 1 ? "" : "s")"
    }
}
