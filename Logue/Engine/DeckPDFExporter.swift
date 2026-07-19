import AppKit
import WebKit

/// Phase H: extracted from the now-deleted `SlideStudioView` so the slide
/// deck PDF export pipeline can be invoked from anywhere — chiefly from
/// the Canvas pane's "Export PDF" button when a `slidedeck` snapshot is
/// active. Uses an off-screen `WKWebView` whose `printOperation(with:)`
/// writes a PDF when the print job's `NSPrintInfo` is set to save-to-file.
/// Sandbox-safe — no subprocess, no Marp dependency.
@MainActor
final class DeckPDFExporter {
    /// Strong reference held while the export is in-flight. Without this,
    /// the WKWebView + nav delegate would deallocate before `didFinish`
    /// fires and the print operation would never run.
    nonisolated(unsafe) private static var inFlight: DeckPDFExporter?

    private let webView: WKWebView
    private let destination: URL
    private let completion: (Result<URL, Error>) -> Void
    private var navDelegate: NavDelegate?

    private init(
        html: String,
        destination: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let cfg = WKWebViewConfiguration()
        // Logical 960×540 surface so the PDF page size matches the
        // CSS `@page` rules in the deck scaffold.
        webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 960, height: 540),
            configuration: cfg
        )
        self.destination = destination
        self.completion = completion
        let delegate = NavDelegate { [weak self] in
            self?.runPrint()
        }
        webView.navigationDelegate = delegate
        navDelegate = delegate
        webView.loadHTMLString(html, baseURL: nil)
    }

    static func export(
        html: String,
        to url: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let exporter = DeckPDFExporter(html: html, destination: url, completion: completion)
        Self.inFlight = exporter
    }

    private func runPrint() {
        let printInfo = NSPrintInfo()
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destination
        // 960×540 px = 720×405 points (96 DPI assumption inside WebKit's
        // logical CSS pixel space). Set the paper size so the first
        // slide isn't squashed onto a US Letter page.
        printInfo.paperSize = NSSize(width: 720, height: 405)
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .fit
        guard let op = webView.printOperation(with: printInfo) as NSPrintOperation? else {
            completion(.failure(SlideDeckBuilder.SlideError.generationFailed("Couldn't create print operation")))
            Self.inFlight = nil
            return
        }
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        let succeeded = op.run()
        if succeeded {
            completion(.success(destination))
        } else {
            completion(.failure(SlideDeckBuilder.SlideError.generationFailed("Print returned false")))
        }
        Self.inFlight = nil
    }

    /// Triggers the print pipeline once the WebView has finished loading
    /// and laying out the deck. Without waiting for `didFinish`, the
    /// printout would capture the deck mid-render.
    private final class NavDelegate: NSObject, WKNavigationDelegate {
        let onLoad: () -> Void

        init(onLoad: @escaping () -> Void) {
            self.onLoad = onLoad
        }

        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            // Give layout one runloop pass before we print.
            DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.Delays.chatInputRefocusInterval) {
                self.onLoad()
            }
        }
    }
}
