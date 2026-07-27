import Foundation
@testable import Logue
import Testing

@Suite("MirrorConflict")
struct MirrorConflictTests {
    private func conflict(app: String, file: String) -> MirrorConflict {
        MirrorConflict(
            documentID: UUID(),
            documentTitle: "Doc",
            appVersion: app,
            fileVersion: file,
            fileURL: URL(fileURLWithPath: "/tmp/Doc.md"),
            detectedAt: Date()
        )
    }

    @Test("Frontmatter is stripped from each side, so the comparison shows prose")
    func stripsFrontmatter() {
        let subject = conflict(
            app: "---\ntitle: A\n---\napp body\n",
            file: "---\ntitle: A\n---\nfile body\n"
        )
        #expect(subject.appBody == "app body\n")
        #expect(subject.fileBody == "file body\n")
    }

    @Test("A body difference is reported")
    func detectsBodyDifference() {
        let subject = conflict(
            app: "---\ntitle: A\n---\napp body\n",
            file: "---\ntitle: A\n---\nfile body\n"
        )
        #expect(subject.differsInBody)
    }

    @Test("A metadata-only difference is not reported as a body difference")
    func metadataOnlyDifference() {
        let subject = conflict(
            app: "---\ntitle: A\nstatus: Active\n---\nsame body\n",
            file: "---\ntitle: A\nstatus: Done\n---\nsame body\n"
        )
        #expect(subject.differsInBody == false)
    }

    @Test("Line-ending differences alone are not a body difference")
    func lineEndingsIgnored() {
        let subject = conflict(
            app: "---\ntitle: A\n---\nline one\nline two\n",
            file: "---\ntitle: A\n---\r\nline one\r\nline two\r\n"
        )
        #expect(subject.differsInBody == false)
    }

    @Test("A file with no frontmatter is treated as all body")
    func noFrontmatterIsBody() {
        let subject = conflict(app: "---\ntitle: A\n---\nbody\n", file: "just prose")
        #expect(subject.fileBody == "just prose")
    }

    @Test("An empty side is handled")
    func emptySide() {
        let subject = conflict(app: "---\ntitle: A\n---\n", file: "---\ntitle: A\n---\nsomething\n")
        #expect(subject.appBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(subject.differsInBody)
    }

    @Test("A conflict is identified by its document")
    func identifiedByDocument() {
        let subject = conflict(app: "a", file: "b")
        #expect(subject.id == subject.documentID)
    }

    @Test("Unicode bodies compare correctly")
    func unicodeBodies() {
        let subject = conflict(
            app: "---\ntitle: A\n---\n👩‍💻 記録\n",
            file: "---\ntitle: A\n---\n👩‍💻 記録\n"
        )
        #expect(subject.differsInBody == false)
    }
}
