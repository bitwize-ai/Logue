import Foundation
@testable import Logue
import Testing

/// Finding and rewriting remote image references in pasted markdown.
///
/// URLs here come from arbitrary web pages, so the detection step is a security
/// boundary: it decides what the app is willing to fetch.
@Suite("RemoteImageImport")
struct RemoteImageImportTests {
    // MARK: - Detection

    @Test("An https image reference is detected")
    func detectsHTTPSImage() {
        let found = RemoteImageImporter.remoteImages(in: "![cat](https://example.com/cat.png)")
        #expect(found.count == 1)
        #expect(found.first?.url.host == "example.com")
        #expect(found.first?.altText == "cat")
    }

    @Test("An http image reference is detected")
    func detectsHTTPImage() {
        #expect(RemoteImageImporter.remoteImages(in: "![a](http://example.com/a.jpg)").count == 1)
    }

    @Test("Multiple references are all detected")
    func detectsMultiple() {
        let markdown = "![a](https://example.com/a.png) ![b](https://example.com/b.png)"
        #expect(RemoteImageImporter.remoteImages(in: markdown).count == 2)
    }

    @Test("A plain link is not an image")
    func plainLinkIgnored() {
        #expect(RemoteImageImporter.remoteImages(in: "[text](https://example.com)").isEmpty)
    }

    @Test("An already-local reference is left alone")
    func localReferenceIgnored() {
        #expect(RemoteImageImporter.remoteImages(in: "![a](attachments/a.png)").isEmpty)
    }

    @Test("A file:// reference is refused")
    func fileSchemeRefused() {
        #expect(RemoteImageImporter.remoteImages(in: "![a](file:///etc/passwd)").isEmpty)
    }

    @Test("A data: reference is refused")
    func dataSchemeRefused() {
        #expect(RemoteImageImporter.remoteImages(in: "![a](data:image/png;base64,AAAA)").isEmpty)
    }

    // MARK: - Local-network protection

    @Test("localhost is refused so a paste cannot probe the local machine")
    func localhostRefused() {
        #expect(RemoteImageImporter.remoteImages(in: "![a](http://localhost/a.png)").isEmpty)
        #expect(RemoteImageImporter.remoteImages(in: "![a](http://127.0.0.1/a.png)").isEmpty)
    }

    @Test("Private network addresses are refused")
    func privateAddressesRefused() {
        let hosts = ["10.0.0.5", "192.168.1.10", "172.16.4.2", "169.254.169.254", "[::1]"]
        for host in hosts {
            let markdown = "![a](http://\(host)/a.png)"
            #expect(RemoteImageImporter.remoteImages(in: markdown).isEmpty, "\(host) should be refused")
        }
    }

    @Test("A .local hostname is refused")
    func mdnsHostRefused() {
        #expect(RemoteImageImporter.remoteImages(in: "![a](http://nas.local/a.png)").isEmpty)
    }

    // MARK: - Rewriting

    @Test("A reference is rewritten to its local path")
    func rewritesToLocalPath() {
        let markdown = "![cat](https://example.com/cat.png)"
        let found = RemoteImageImporter.remoteImages(in: markdown)
        let result = RemoteImageImporter.rewriting(
            markdown: markdown,
            replacing: [found[0].url: "attachments/cat.png"]
        )
        #expect(result == "![cat](attachments/cat.png)")
    }

    @Test("Alt text is preserved when rewriting")
    func preservesAltText() {
        let markdown = "![a nice cat](https://example.com/cat.png)"
        let found = RemoteImageImporter.remoteImages(in: markdown)
        let result = RemoteImageImporter.rewriting(
            markdown: markdown,
            replacing: [found[0].url: "attachments/cat.png"]
        )
        #expect(result.contains("![a nice cat]"))
    }

    @Test("An unimported reference is left remote rather than broken")
    func unimportedLeftAlone() {
        let markdown = "![a](https://example.com/a.png) ![b](https://example.com/b.png)"
        let found = RemoteImageImporter.remoteImages(in: markdown)
        let target = found.first { $0.url.absoluteString.hasSuffix("a.png") }
        let result = RemoteImageImporter.rewriting(
            markdown: markdown,
            replacing: [target?.url ?? URL(fileURLWithPath: "/"): "attachments/a.png"]
        )
        #expect(result.contains("attachments/a.png"))
        #expect(result.contains("https://example.com/b.png"))
    }

    @Test("Rewriting with no replacements returns the markdown unchanged")
    func noReplacements() {
        let markdown = "![a](https://example.com/a.png)"
        #expect(RemoteImageImporter.rewriting(markdown: markdown, replacing: [:]) == markdown)
    }

    @Test("Surrounding unicode is preserved exactly")
    func preservesUnicode() {
        let markdown = "👩‍💻 記録 ![a](https://example.com/a.png) 終わり"
        let found = RemoteImageImporter.remoteImages(in: markdown)
        let result = RemoteImageImporter.rewriting(
            markdown: markdown,
            replacing: [found[0].url: "attachments/a.png"]
        )
        #expect(result == "👩‍💻 記録 ![a](attachments/a.png) 終わり")
    }

    // MARK: - Filenames

    @Test("A filename is derived from the URL")
    func filenameFromURL() throws {
        let url = try #require(URL(string: "https://example.com/photos/cat.png"))
        #expect(RemoteImageImporter.suggestedFilename(for: url).hasSuffix(".png"))
    }

    @Test("A URL with no usable extension still gets one")
    func filenameGetsExtension() throws {
        let url = try #require(URL(string: "https://example.com/image"))
        #expect(RemoteImageImporter.suggestedFilename(for: url).contains("."))
    }

    @Test("Path traversal in the URL cannot escape the attachments directory")
    func filenameCannotTraverse() throws {
        let url = try #require(URL(string: "https://example.com/..%2F..%2Fetc%2Fpasswd"))
        let name = RemoteImageImporter.suggestedFilename(for: url)
        #expect(name.contains("/") == false)
        #expect(name.contains("..") == false)
    }

    @Test("Suggested filenames are unique per URL")
    func filenamesAreUnique() throws {
        let first = try #require(URL(string: "https://a.example.com/cat.png"))
        let second = try #require(URL(string: "https://b.example.com/cat.png"))
        #expect(
            RemoteImageImporter.suggestedFilename(for: first)
                != RemoteImageImporter.suggestedFilename(for: second)
        )
    }
}
