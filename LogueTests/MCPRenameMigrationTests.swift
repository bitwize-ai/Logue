import Foundation
import Testing
@testable import Logue

/// Renaming a server must not undo what the user turned off.
@Suite("MCP rename migration")
struct MCPRenameMigrationTests {
    @Test("A disabled tool stays disabled through a rename")
    func disabledToolSurvivesRename() {
        // The bug this exists for: published names are derived from the server name, and the
        // disable list is keyed on the published name — so without this the tool is offered
        // again under a name the user has never seen.
        let before: Set<String> = ["github__delete_repo"]
        let after = MCPRenameMigration.remapped(disabled: before, from: "GitHub", to: "GitLab")
        #expect(after.contains("gitlab__delete_repo"))
        #expect(after.contains("github__delete_repo") == false)
    }

    @Test("Built-in tools are never touched")
    func builtInsAreUntouched() {
        // A built-in has no namespace separator, so it cannot be mistaken for a server's.
        let before: Set<String> = ["delete_document", "run_javascript", "github__delete_repo"]
        let after = MCPRenameMigration.remapped(disabled: before, from: "GitHub", to: "GitLab")
        #expect(after.contains("delete_document"))
        #expect(after.contains("run_javascript"))
    }

    @Test("Another server's tools are left alone")
    func otherServersAreUntouched() {
        let before: Set<String> = ["github__delete_repo", "jira__delete_issue"]
        let after = MCPRenameMigration.remapped(disabled: before, from: "GitHub", to: "GitLab")
        #expect(after.contains("jira__delete_issue"))
    }

    @Test("A rename that does not change the namespace changes nothing")
    func cosmeticRenameIsANoOp() {
        // "GitHub" and "git-hub" both fold to `github`... they do not, and that is the point:
        // the namespace is what matters, not the spelling. A change that leaves the namespace
        // alone must leave the list byte-identical rather than rebuilding it.
        let before: Set<String> = ["github__delete_repo"]
        #expect(MCPRenameMigration.remapped(disabled: before, from: "GitHub", to: "GITHUB") == before)
        #expect(MCPRenameMigration.remapped(disabled: before, from: "GitHub", to: "GitHub") == before)
    }

    @Test("Every entry survives the remap — nothing is silently dropped")
    func nothingIsLost() {
        let before: Set<String> = [
            "delete_document",
            "github__delete_repo",
            "github__create_issue",
            "jira__delete_issue",
        ]
        let after = MCPRenameMigration.remapped(disabled: before, from: "GitHub", to: "GitLab")
        #expect(after.count == before.count, "an entry was lost or two collapsed into one")
    }

    @Test("The rewritten name is one the registry will actually look for")
    func rewrittenNameMatchesTheRegistry() {
        // Pasting the halves together would let the result exceed the length bound
        // `published` applies, and a name over that bound never matches anything.
        let long = String(repeating: "server", count: 20)
        let before: Set<String> = [MCPToolNaming.published(serverName: "Short", toolName: "do_thing")]
        let after = MCPRenameMigration.remapped(disabled: before, from: "Short", to: long)
        let expected = MCPToolNaming.published(serverName: long, toolName: "do_thing")
        #expect(after.contains(expected))
        #expect(expected.count <= MCPToolNaming.maxNameLength)
    }

    @Test("An empty list stays empty")
    func emptyStaysEmpty() {
        #expect(MCPRenameMigration.remapped(disabled: [], from: "A", to: "B").isEmpty)
    }
}
