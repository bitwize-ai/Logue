import Testing
@testable import Logue

/// Two servers publishing under one prefix is resolved by dropping tools. Saying so before
/// it happens is the only way the user finds out.
@Suite("MCP namespace clash")
struct MCPNamespaceClashTests {
    @Test("Names that fold to the same namespace clash")
    func foldedNamesClash() {
        // Every one of these folds to `git_hub`: the derivation lowercases and turns each run
        // of non-alphanumerics into a single underscore. None of them look alike at a glance,
        // which is the whole reason the clash has to be said out loud.
        for name in ["GIT-HUB", "Git.Hub", "git__hub", "git   hub"] {
            #expect(
                MCPNamespaceClash.first(for: name, among: ["git hub"]) == "git hub",
                "\(name) should clash with 'git hub'"
            )
        }
    }

    @Test("Case and spelling alone are a clash")
    func caseOnlyNamesClash() {
        #expect(MCPNamespaceClash.first(for: "GITHUB", among: ["GitHub"]) == "GitHub")
    }

    @Test("A separator is what tells two names apart, and it is easy to misread")
    func separatorMakesTheDifference() {
        // `GitHub` folds to `github`; `git hub` folds to `git_hub`. They look like the same
        // name and are not, and asserting that they clash is a case that passes for the wrong
        // reason — it is the exact pair #76's review found already doing that once.
        #expect(MCPNamespaceClash.first(for: "git hub", among: ["GitHub"]) == nil)
        #expect(MCPToolNaming.namespace(for: "GitHub") != MCPToolNaming.namespace(for: "git hub"))
    }

    @Test("Genuinely different names do not clash")
    func differentNamesDoNotClash() {
        #expect(MCPNamespaceClash.first(for: "Jira", among: ["GitHub", "Linear"]) == nil)
    }

    @Test("An empty or blank name clashes with nothing")
    func blankNameIsNotAClash() {
        #expect(MCPNamespaceClash.first(for: "", among: ["GitHub"]) == nil)
        #expect(MCPNamespaceClash.first(for: "   ", among: ["GitHub"]) == nil)
    }

    @Test("Nothing to clash with is not a clash")
    func noServersIsNotAClash() {
        #expect(MCPNamespaceClash.first(for: "GitHub", among: []) == nil)
    }

    @Test("The clash it reports is the one the registry would resolve first")
    func reportsTheFirstClash() {
        // `MCPRegistryPlan` keeps the first claim over an ordered list, so the name worth
        // showing is the one that would win — not merely any of them.
        #expect(MCPNamespaceClash.first(for: "Git.Hub", among: ["git hub", "GIT-HUB"]) == "git hub")
    }

    @Test("A name of nothing but punctuation clashes with another of the same")
    func punctuationNamesShareTheFallback() {
        // Both fold to the `server` fallback, so they really do collide — reporting them as
        // distinct would be the wrong answer, not a kinder one.
        #expect(MCPNamespaceClash.first(for: "!!!", among: ["???"]) == "???")
    }
}
