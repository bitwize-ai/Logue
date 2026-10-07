import Foundation

/// What a remote server is allowed to put into a prompt.
///
/// Tool output from a built-in tool is text Logue produced. Tool output from an MCP server is
/// text **somebody else** produced, arriving over the network, and it is fed straight back
/// into the model's context. That makes it the same category of thing as a web page or a
/// document: content, not instruction, and it has to be delimited and bounded before it goes
/// anywhere near a prompt.
///
/// Three separate jobs, deliberately not collapsed into one:
///
/// - **Bounded.** A server can return a gigabyte. The context window cannot, and a tool that
///   fills it evicts the conversation that asked the question.
/// - **Delimited.** Wrapped in `<tool_output>` per the project rule for injecting user or
///   third-party content, with any closing delimiter in the payload neutralised — otherwise
///   a server can end its own region and have the remainder read as instruction.
/// - **Stripped.** Control characters removed, because a payload can carry them and they do
///   nothing useful in a prompt.
enum MCPToolOutput {
    /// The tag the output is wrapped in.
    static let tag = "tool_output"

    /// Longest payload we will hand to the model, in characters.
    ///
    /// Four characters to a token, roughly, so this is about 2k tokens — enough for a real
    /// answer, small enough that one tool call cannot evict the conversation.
    static let maxCharacters = 8000

    /// Prepares a server's response for a prompt.
    ///
    /// The rules are `DelimitedContent`'s — stripped, unable to close its own region, and
    /// bounded with the cut announced. What is decided *here* is the tag and the budget:
    /// this is a server's reply, and 8000 characters is about 2k tokens, which is enough for
    /// a real answer and small enough that one tool call cannot evict the conversation that
    /// asked the question.
    static func prepare(_ raw: String) -> String {
        DelimitedContent.wrap(raw, in: tag, maxCharacters: maxCharacters)
    }
}

/// How long we will wait on a server before giving up on it.
///
/// A hung server must not hang the turn. The agent loop has its own approval timeout for a
/// user who never answers; this is the equivalent for a server that never answers, and it is
/// deliberately much shorter — a person deserves five minutes to think, a socket does not.
enum MCPTimeout {
    /// One tool call.
    static let call: TimeInterval = 20
    /// Asking a server what it can do, which happens while the user watches Settings.
    static let discovery: TimeInterval = 10
}
