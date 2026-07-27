import Foundation
@testable import Logue
import Testing

/// The YAML frontmatter layer for the plain-markdown mirror.
///
/// Output must be byte-stable for identical input: these files are git-tracked, and
/// unstable key order or quoting would produce diff noise on every save.
@Suite("MarkdownFrontmatter")
struct MarkdownFrontmatterTests {
    // MARK: - Rendering

    @Test("A scalar renders as key: value")
    func rendersScalar() {
        let text = MarkdownFrontmatter.render([("title", .scalar("Project Alpha"))])
        #expect(text == "---\ntitle: Project Alpha\n---\n")
    }

    @Test("Fields render in the order given, for stable diffs")
    func rendersInGivenOrder() {
        let text = MarkdownFrontmatter.render([
            ("title", .scalar("A")),
            ("type", .scalar("Project")),
            ("status", .scalar("Active")),
        ])
        #expect(text == "---\ntitle: A\ntype: Project\nstatus: Active\n---\n")
    }

    @Test("A list renders as indented dashes")
    func rendersList() {
        let text = MarkdownFrontmatter.render([("tags", .list(["urgent", "later"]))])
        #expect(text == "---\ntags:\n  - urgent\n  - later\n---\n")
    }

    @Test("An empty list is omitted rather than written as an empty key")
    func omitsEmptyList() {
        #expect(MarkdownFrontmatter.render([("tags", .list([]))]) == "---\n---\n")
    }

    @Test("An empty scalar is omitted")
    func omitsEmptyScalar() {
        #expect(MarkdownFrontmatter.render([("title", .scalar(""))]) == "---\n---\n")
    }

    @Test("No fields renders no frontmatter at all")
    func rendersNothingForNoFields() {
        #expect(MarkdownFrontmatter.render([]).isEmpty)
    }

    // MARK: - Quoting

    @Test("A value containing a colon is quoted")
    func quotesColon() {
        let text = MarkdownFrontmatter.render([("title", .scalar("Plan: Q3"))])
        #expect(text.contains("title: \"Plan: Q3\""))
    }

    @Test("A value that would read as a comment is quoted")
    func quotesHash() {
        #expect(MarkdownFrontmatter.render([("k", .scalar("#1"))]).contains("\"#1\""))
    }

    @Test("A value with leading or trailing space is quoted")
    func quotesEdgeWhitespace() {
        #expect(MarkdownFrontmatter.render([("k", .scalar(" pad "))]).contains("\" pad \""))
    }

    @Test("A quote inside a value is escaped")
    func escapesQuotes() {
        let text = MarkdownFrontmatter.render([("k", .scalar("say \"hi\""))])
        #expect(text.contains("\\\""))
    }

    @Test("A wikilink value is quoted so the brackets survive")
    func quotesWikilink() {
        let text = MarkdownFrontmatter.render([("belongs_to", .list(["[[Alpha]]"]))])
        #expect(text.contains("\"[[Alpha]]\""))
    }

    @Test("A plain value is not needlessly quoted")
    func doesNotOverQuote() {
        #expect(MarkdownFrontmatter.render([("k", .scalar("Active"))]).contains("k: Active"))
    }

    // MARK: - Parsing

    @Test("Frontmatter and body are separated")
    func parsesFrontmatterAndBody() {
        let parsed = MarkdownFrontmatter.parse("---\ntitle: A\n---\nBody text")
        #expect(parsed.fields["title"] == .scalar("A"))
        #expect(parsed.body == "Body text")
    }

    @Test("A document with no frontmatter is all body")
    func parsesBodyOnly() {
        let parsed = MarkdownFrontmatter.parse("Just prose")
        #expect(parsed.fields.isEmpty)
        #expect(parsed.body == "Just prose")
    }

    @Test("A list parses back into a list")
    func parsesList() {
        let parsed = MarkdownFrontmatter.parse("---\ntags:\n  - a\n  - b\n---\n")
        #expect(parsed.fields["tags"] == .list(["a", "b"]))
    }

    @Test("Quoted values are unquoted and unescaped on parse")
    func parsesQuotedValue() {
        let parsed = MarkdownFrontmatter.parse("---\nk: \"Plan: Q3\"\n---\n")
        #expect(parsed.fields["k"] == .scalar("Plan: Q3"))
    }

    @Test("An unterminated frontmatter block is treated as body")
    func unterminatedIsBody() {
        let source = "---\ntitle: A\nno closing marker"
        let parsed = MarkdownFrontmatter.parse(source)
        #expect(parsed.fields.isEmpty)
        #expect(parsed.body == source)
    }

    @Test("Comment lines are ignored")
    func ignoresComments() {
        let parsed = MarkdownFrontmatter.parse("---\n# a note\ntitle: A\n---\n")
        #expect(parsed.fields.count == 1)
        #expect(parsed.fields["title"] == .scalar("A"))
    }

    @Test("A duplicate key keeps the last value")
    func duplicateKeyLastWins() {
        let parsed = MarkdownFrontmatter.parse("---\nk: one\nk: two\n---\n")
        #expect(parsed.fields["k"] == .scalar("two"))
    }

    @Test("Body content is preserved exactly, including blank lines")
    func preservesBodyExactly() {
        let body = "# Heading\n\nPara one\n\n\nPara two\n"
        let parsed = MarkdownFrontmatter.parse("---\nk: v\n---\n" + body)
        #expect(parsed.body == body)
    }

    @Test("Windows line endings are handled")
    func handlesCRLF() {
        let parsed = MarkdownFrontmatter.parse("---\r\ntitle: A\r\n---\r\nBody")
        #expect(parsed.fields["title"] == .scalar("A"))
        #expect(parsed.body == "Body")
    }

    @Test("Unicode keys and values survive")
    func handlesUnicode() {
        let parsed = MarkdownFrontmatter.parse("---\ntitle: 会議メモ 👩‍💻\n---\n")
        #expect(parsed.fields["title"] == .scalar("会議メモ 👩‍💻"))
    }

    @Test("A value containing a colon after the first one is kept whole")
    func keepsLaterColons() {
        let parsed = MarkdownFrontmatter.parse("---\nurl: https://example.com/a\n---\n")
        #expect(parsed.fields["url"] == .scalar("https://example.com/a"))
    }

    // MARK: - Round trip

    @Test("Rendering then parsing returns the same fields")
    func roundTrips() {
        let fields: [(String, FrontmatterValue)] = [
            ("title", .scalar("Plan: Q3")),
            ("status", .scalar("Active")),
            ("tags", .list(["urgent", "a b"])),
            ("belongs_to", .list(["[[Alpha]]"])),
        ]
        let parsed = MarkdownFrontmatter.parse(MarkdownFrontmatter.render(fields) + "body")

        #expect(parsed.fields["title"] == .scalar("Plan: Q3"))
        #expect(parsed.fields["status"] == .scalar("Active"))
        #expect(parsed.fields["tags"] == .list(["urgent", "a b"]))
        #expect(parsed.fields["belongs_to"] == .list(["[[Alpha]]"]))
        #expect(parsed.body == "body")
    }

    @Test("Rendering the same fields twice produces identical bytes")
    func renderIsDeterministic() {
        let fields: [(String, FrontmatterValue)] = [
            ("title", .scalar("A")),
            ("tags", .list(["x", "y"])),
        ]
        #expect(MarkdownFrontmatter.render(fields) == MarkdownFrontmatter.render(fields))
    }
}
