import Foundation
import Testing

@testable import Logue

/// Building MCP requests and reading MCP replies.
///
/// All parsing, which means all of it can be wrong in ways a running server would not reveal.
/// These cases are the replies a server can actually send: a good one, an error one, an
/// oversized one, and one that is simply not what it claims to be.
@Suite("MCPWireFormat")
struct MCPWireFormatTests {
    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    // MARK: - Requests

    @Test("A list request is well-formed JSON-RPC")
    func listRequestIsWellFormed() throws {
        let body = try #require(
            try JSONSerialization.jsonObject(with: MCPWireFormat.listToolsBody()) as? [String: Any]
        )
        #expect(body["jsonrpc"] as? String == "2.0")
        #expect(body["method"] as? String == "tools/list")
    }

    @Test("A call request carries the server's own tool name, not the published one")
    func callRequestUsesTheServersName() throws {
        // Namespacing is Logue's, for Logue's registry. Sending `github__create_issue` back
        // to the server would ask it for a tool it has never heard of.
        let body = try #require(
            try JSONSerialization.jsonObject(
                with: MCPWireFormat.callToolBody(name: "create_issue", arguments: ["title": "Bug"])
            ) as? [String: Any]
        )
        let params = try #require(body["params"] as? [String: Any])
        #expect(params["name"] as? String == "create_issue")
        #expect((params["arguments"] as? [String: Any])?["title"] as? String == "Bug")
    }

    // MARK: - Replies

    @Test("A result is read out of the envelope")
    func resultIsUnwrapped() throws {
        let data = try json(["jsonrpc": "2.0", "id": 1, "result": ["tools": []]])
        #expect(try MCPWireFormat.result(from: data)["tools"] != nil)
    }

    @Test("A server-reported error is raised, carrying its message")
    func serverErrorsAreRaised() throws {
        let data = try json([
            "jsonrpc": "2.0", "id": 1,
            "error": ["code": -32601, "message": "Method not found"],
        ])
        #expect(throws: MCPWireFormat.WireError.server("Method not found")) {
            try MCPWireFormat.result(from: data)
        }
    }

    @Test("A server's error message is bounded")
    func serverErrorMessagesAreBounded() throws {
        // Third-party text heading for a log and possibly for the user.
        let data = try json([
            "jsonrpc": "2.0",
            "error": ["message": String(repeating: "x", count: 10_000)],
        ])
        do {
            _ = try MCPWireFormat.result(from: data)
            Issue.record("expected a rejection")
        } catch let MCPWireFormat.WireError.server(message) {
            #expect(message.count <= 200)
        }
    }

    @Test("An oversized reply is refused before it is parsed")
    func oversizedRepliesAreRefused() {
        // MCPToolOutput bounds a String that has already been decoded, so a server could
        // make Logue allocate whatever it sent before anything trimmed it. This is the bound
        // that stops that, and it has to be applied to bytes.
        let huge = Data(repeating: 0x41, count: MCPWireFormat.maxResponseBytes + 1)
        #expect(throws: MCPWireFormat.WireError.tooLarge) {
            try MCPWireFormat.result(from: huge)
        }
    }

    @Test("Something that is not JSON is refused")
    func nonJSONIsRefused() {
        #expect(throws: MCPWireFormat.WireError.notJSON) {
            try MCPWireFormat.result(from: Data("<html>nope</html>".utf8))
        }
    }

    @Test("A reply with neither result nor error is refused")
    func emptyEnvelopeIsRefused() throws {
        let data = try json(["jsonrpc": "2.0", "id": 1])
        #expect(throws: MCPWireFormat.WireError.missingResult) {
            try MCPWireFormat.result(from: data)
        }
    }

    // MARK: - Tool lists

    @Test("Tools are read with their annotations")
    func toolsCarryTheirAnnotations() {
        let tools = MCPWireFormat.tools(from: [
            "tools": [
                ["name": "wipe", "description": "Deletes", "annotations": ["destructiveHint": true]],
                ["name": "list", "description": "Lists", "annotations": ["readOnlyHint": true]],
            ],
        ])
        #expect(tools.map(\.name) == ["wipe", "list"])
        #expect(tools.first?.destructiveHint == true)
        #expect(tools.last?.readOnlyHint == true)
    }

    @Test("A malformed entry costs that tool, not the whole list")
    func malformedEntriesAreSkipped() {
        // One bad entry in a server's list should not make every other tool it offers
        // disappear.
        let tools = MCPWireFormat.tools(from: [
            "tools": [
                ["description": "no name at all"],
                ["name": ""],
                ["name": "good", "description": "fine"],
            ],
        ])
        #expect(tools.map(\.name) == ["good"])
    }

    @Test("A server cannot offer unlimited tools")
    func toolListsAreBounded() {
        // Ten thousand descriptions would fill the model's context before the user's question
        // got anywhere near it.
        let many = (0 ..< 5000).map { ["name": "tool\($0)", "description": "x"] }
        #expect(MCPWireFormat.tools(from: ["tools": many]).count == MCPWireFormat.maxToolsPerServer)
    }

    @Test("A reply with no tools is not an error")
    func emptyToolListIsFine() {
        #expect(MCPWireFormat.tools(from: [:]).isEmpty)
        #expect(MCPWireFormat.tools(from: ["tools": []]).isEmpty)
    }

    // MARK: - Call results

    @Test("Text parts are joined")
    func textPartsAreRead() {
        let text = MCPWireFormat.callText(from: [
            "content": [["type": "text", "text": "first"], ["type": "text", "text": "second"]],
        ])
        #expect(text == "first\nsecond")
    }

    @Test("Non-text content is named, not decoded")
    func binaryContentIsNotInlined() {
        // The agent loop feeds this straight into a prompt, and a base64 blob there is a
        // context window spent on nothing.
        let text = MCPWireFormat.callText(from: [
            "content": [
                ["type": "text", "text": "here it is"],
                ["type": "image", "data": String(repeating: "A", count: 5000)],
            ],
        ])
        #expect(text.contains("here it is"))
        #expect(text.contains("[image content omitted]"))
        #expect(text.count < 100)
    }

    @Test("A call that returned nothing reads as empty, not as broken")
    func emptyContentIsEmpty() {
        #expect(MCPWireFormat.callText(from: [:]).isEmpty)
    }
}
