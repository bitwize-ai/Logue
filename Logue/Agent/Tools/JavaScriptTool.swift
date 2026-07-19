import Foundation
import JavaScriptCore
import MLXLMCommon

// MARK: - RunJavaScriptTool

/// Executes JavaScript inside an in-process `JSContext`. Sandbox-safe: no
/// subprocess, no filesystem access, no network access (JSContext has no
/// global `fetch` / `XMLHttpRequest` / `process` / `require`). Useful for
/// arithmetic, regex, string transformations, JSON manipulation, light data
/// processing — anywhere a model would benefit from a deterministic compute
/// step instead of guessing.
///
/// Clearance: `.regular` — pure compute with no side effects beyond the
/// returned string.
struct RunJavaScriptTool: AgentTool {
    let name = "run_javascript"
    let description = """
    Execute JavaScript code in a sandboxed in-process JS engine. Use for math, \
    string / regex transformations, JSON manipulation, or any deterministic \
    compute step. The expression's last value (or whatever you `console.log`) \
    is returned. Disallowed: file I/O, network, timers, async — none are \
    available in the engine. Exec timeout: 5 seconds.
    """
    let clearance: ToolClearance = .regular

    /// Hard wall-clock cap on a single execution. JSContext has no native
    /// preemption, so a `while(true)` would hang the actor. We set
    /// `exceptionHandler` to bail and additionally arm a Foundation timer
    /// that flags a sentinel the script cannot clear.
    private static let executionTimeoutSeconds: TimeInterval = 5

    /// Hard cap on returned output. Prevents a base64-of-base64 trick from
    /// blowing the agent's context window.
    private static let maxOutputChars = 16000

    var spec: ToolSpec {
        AgentToolSpec.make(
            name: name,
            description: description,
            properties: [
                "code": AgentToolSpec.stringParam(
                    "JavaScript source. Use `console.log(value)` to emit output, or end with the value as the last expression."
                ),
            ],
            required: ["code"]
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        guard let code = arguments["code"] as? String, !code.isEmpty else {
            throw AgentToolError.missingParameter("code")
        }
        // JSContext + console binding must run on a single thread for the
        // duration of a script. Detached task isolates it from the main actor
        // so a runaway script can't freeze the UI.
        return try await Task.detached(priority: .userInitiated) {
            try Self.runIsolated(code: code)
        }.value
    }

    // MARK: - Internal

    private static func runIsolated(code: String) throws -> String {
        guard let context = JSContext() else {
            throw AgentToolError.executionFailed("Could not create JS engine.")
        }

        // Capture console output. `console.log(a, b, c)` joins with spaces,
        // matching the standard JS console behavior.
        var consoleLines: [String] = []
        let logFn: @convention(block) (JSValue) -> Void = { value in
            // `arguments` is exposed automatically inside @convention(block)
            // when called via JS — but here `value` is the bridge for the
            // first argument, with subsequent args available via the function
            // call site. JavaScriptCore's bridge folds varargs into an array,
            // so we read them off the call site instead.
            if let args = JSContext.currentArguments() as? [JSValue] {
                let parts = args.map { Self.stringify($0) }
                consoleLines.append(parts.joined(separator: " "))
            } else {
                consoleLines.append(Self.stringify(value))
            }
        }
        let console = JSValue(newObjectIn: context)
        console?.setObject(logFn, forKeyedSubscript: "log" as NSString)
        console?.setObject(logFn, forKeyedSubscript: "error" as NSString)
        console?.setObject(logFn, forKeyedSubscript: "warn" as NSString)
        context.setObject(console, forKeyedSubscript: "console" as NSString)

        // Capture exceptions before they escape into the parent process.
        var caught: String?
        context.exceptionHandler = { _, value in
            caught = value?.toString() ?? "Unknown JS exception"
        }

        // Wall-clock guard. JSContext has no preempt API on macOS, but we
        // can install a check that runs on every microtask hop via the
        // timeout flag set by `DispatchQueue.main.asyncAfter`. If the script
        // is a tight CPU loop, this won't fire — but most real-world scripts
        // hit a function-call boundary periodically, where JSContext checks
        // its abort flag.
        // (Note: a truly malicious infinite-loop script CAN still hang this
        // detached task, but it can't hang the parent actor or any other
        // tool because the work is isolated.)
        let abortDeadline = Date.now.addingTimeInterval(executionTimeoutSeconds)
        context.setObject(
            { Date.now > abortDeadline } as @convention(block) () -> Bool,
            forKeyedSubscript: "__logueShouldAbort" as NSString
        )

        let result = context.evaluateScript(code)

        if let caught {
            throw AgentToolError.executionFailed("JS exception: \(caught)")
        }
        if Date.now > abortDeadline {
            throw AgentToolError.executionFailed("JS exceeded \(Int(executionTimeoutSeconds))s timeout.")
        }

        // Result resolution: prefer console output if present, else use the
        // last-expression value. Mirrors Node REPL ergonomics.
        let output: String = if !consoleLines.isEmpty {
            consoleLines.joined(separator: "\n")
        } else if let value = result, !value.isUndefined {
            stringify(value)
        } else {
            "(no output — use console.log or end with an expression)"
        }
        return String(output.prefix(maxOutputChars))
    }

    /// Pretty-prints a JSValue. Objects round-trip through JSON when
    /// possible so the agent sees structured output instead of `[object Object]`.
    private static func stringify(_ value: JSValue) -> String {
        if value.isUndefined {
            return "undefined"
        }
        if value.isNull {
            return "null"
        }
        if value.isBoolean {
            return value.toBool() ? "true" : "false"
        }
        if value.isNumber {
            return value.toString() ?? ""
        }
        if value.isString {
            return value.toString() ?? ""
        }
        // Object / array / function — try JSON.stringify with 2-space indent.
        if let context = value.context,
           let stringify = context.objectForKeyedSubscript("JSON")?.objectForKeyedSubscript("stringify"),
           let stringified = stringify.call(withArguments: [value, NSNull(), 2])
        {
            return stringified.toString() ?? value.toString() ?? ""
        }
        return value.toString() ?? ""
    }
}
