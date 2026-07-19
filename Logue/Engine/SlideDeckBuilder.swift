import Foundation
import os.log

/// Phase G: drives the LLM to draft an HTML slide deck from a prompt.
/// Sandbox-safe (no Marp subprocess) — the deck is composed of CSS-only
/// `<section class="slide">` blocks the WebKit renderer can paginate
/// directly to PDF via `WKWebView.printOperation`.
///
/// We pass the model a strict cheatsheet describing the layout so its
/// output is deterministic enough to render reliably. If the model
/// hallucinates extra HTML, we strip everything outside the deck root.
enum SlideDeckBuilder {
    private static let logger = Logger(subsystem: AppConstants.bundleID, category: "SlideDeckBuilder")

    /// Number of slides cap. Prevents an unbounded prompt from generating
    /// a 200-slide deck the WebView can't paginate cleanly.
    static let maxSlides = 24

    /// One-shot generation. Throws when the LLM call fails or returns
    /// unparseable output. The returned string is a complete HTML deck
    /// the caller can hand straight to `WKWebView.loadHTMLString`.
    static func generate(prompt: String, slideCount: Int = 8) async throws -> String {
        let count = max(3, min(maxSlides, slideCount))
        let system = """
        You are a presentation designer. Generate a polished slide deck on the user's topic. \
        Output ONLY a JSON array of slide objects — no preamble, no markdown fences, no commentary.

        Each slide object has the shape:
          {"title": "Short slide title (max 80 chars)",
           "bullets": ["bullet 1", "bullet 2", ...]}

        Rules:
        - Generate exactly \(count) slides.
        - First slide is the title slide: bullets contains a single one-line subtitle.
        - Last slide is a takeaway / call to action.
        - Bullets are concise — under 18 words each.
        - 3-5 bullets per content slide; 1 for the title slide.
        - No markdown formatting inside bullets — plain prose.
        """
        let user = "<topic>\n\(prompt)\n</topic>"
        let raw = try await LLMEngine.shared.complete(
            system: system, prompt: user, maxTokens: 2048
        )
        let cleaned = stripFences(raw)
        let slides = try parse(json: cleaned)
        return renderHTML(slides: slides, title: prompt)
    }

    // MARK: - Parsing

    private static func stripFences(_ raw: String) -> String {
        var stripped = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstBracket = stripped.firstIndex(of: "["),
           let lastBracket = stripped.lastIndex(of: "]"), lastBracket > firstBracket
        {
            stripped = String(stripped[firstBracket ... lastBracket])
        }
        return stripped
    }

    private static func parse(json: String) throws -> [Slide] {
        guard let data = json.data(using: .utf8) else {
            throw SlideError.parseFailed("Couldn't encode JSON to UTF-8")
        }
        do {
            return try JSONDecoder().decode([Slide].self, from: data)
        } catch {
            throw SlideError.parseFailed(error.localizedDescription)
        }
    }

    // MARK: - Rendering

    private static func renderHTML(slides: [Slide], title: String) -> String {
        let slideHTML = slides.enumerated().map { idx, slide in
            renderSlide(slide, isTitle: idx == 0)
        }.joined(separator: "\n")
        return scaffold(title: title, body: slideHTML)
    }

    private static func renderSlide(_ slide: Slide, isTitle: Bool) -> String {
        let safeTitle = escape(slide.title)
        let bulletList = slide.bullets.map { "<li>\(escape($0))</li>" }.joined(separator: "\n        ")
        if isTitle {
            let subtitle = slide.bullets.first.map(escape) ?? ""
            return """
            <section class="slide title-slide">
              <h1>\(safeTitle)</h1>
              <p class="subtitle">\(subtitle)</p>
            </section>
            """
        }
        return """
        <section class="slide content-slide">
          <h2>\(safeTitle)</h2>
          <ul>
            \(bulletList)
          </ul>
        </section>
        """
    }

    private static func scaffold(title: String, body: String) -> String {
        // 16:9 slides at 960×540 logical px — same as Marp's default.
        // `@page` rules let WKWebView's printOperation paginate slide-by-slide.
        """
        <!DOCTYPE html>
        <html lang="en"><head>
        <meta charset="utf-8"/>
        <title>\(escape(title))</title>
        <style>
          @page { size: 960px 540px; margin: 0; }
          html, body { margin: 0; padding: 0; background: #f4f4f7;
                       font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif;
                       color: #1c1c1e; }
          .slide {
            width: 960px; height: 540px; box-sizing: border-box;
            padding: 56px 64px;
            display: flex; flex-direction: column; justify-content: center;
            background: #ffffff; color: #1c1c1e;
            page-break-after: always; break-after: page;
            border-bottom: 1px solid #d0d0d6;
          }
          .slide:last-child { page-break-after: auto; break-after: auto; border-bottom: none; }
          .title-slide {
            background: linear-gradient(135deg, #4f46e5 0%, #7c3aed 60%, #db2777 100%);
            color: #ffffff;
            justify-content: center; align-items: flex-start;
          }
          .title-slide h1 { font-size: 56px; font-weight: 700; letter-spacing: -0.02em;
                            margin: 0 0 18px 0; line-height: 1.05; }
          .title-slide .subtitle { font-size: 24px; opacity: 0.85; margin: 0; }
          .content-slide h2 { font-size: 36px; font-weight: 600; letter-spacing: -0.01em;
                              margin: 0 0 28px 0; }
          .content-slide ul { list-style: none; padding: 0; margin: 0;
                              font-size: 22px; line-height: 1.45; }
          .content-slide li { padding: 8px 0 8px 28px; position: relative; }
          .content-slide li::before {
            content: ''; position: absolute; left: 0; top: 18px;
            width: 8px; height: 8px; background: #4f46e5; border-radius: 50%;
          }
        </style>
        </head><body>
          \(body)
        </body></html>
        """
    }

    private static func escape(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Types

    private struct Slide: Codable {
        let title: String
        let bullets: [String]
    }

    enum SlideError: Error, LocalizedError {
        case parseFailed(String)
        case generationFailed(String)

        var errorDescription: String? {
            switch self {
            case let .parseFailed(detail): "Couldn't parse slide JSON: \(detail)"
            case let .generationFailed(detail): "Couldn't generate slides: \(detail)"
            }
        }
    }
}
