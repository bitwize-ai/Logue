import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXLMTransformers
import os.log

// MARK: - ToneResult

struct ToneResult {
    let label: String
    let confidence: Double

    static let neutral = ToneResult(label: "neutral", confidence: 0.5)
}

// MARK: - LLMEngine

/// Actor that owns the LLM session and serialises all inference operations.
///
/// Used by the streaming `analyze()` overlay path, LangGraph writing-agent nodes,
/// AI chat, meeting title generation, cross-app panels, and more.
actor LLMEngine { // swiftlint:disable:this type_body_length
    static let shared = LLMEngine()
    private init() {}

    // MARK: - MLX Parameters

    /// Default generation parameters for deterministic grammar output.
    /// maxKVSize caps the KV cache at 16K tokens.
    static let defaultGenerateParameters: GenerateParameters = {
        var params = GenerateParameters()
        params.temperature = 0.15
        params.topP = 0.9
        params.repetitionPenalty = 1.1
        params.maxKVSize = 16384
        return params
    }()

    /// KV cache size in tokens — used for context window calculations.
    static let maxKVSize = 16384

    /// Default max tokens for generation.
    static let defaultMaxTokens = 2048

    // MARK: - Internal State (accessible by extensions in separate files)

    // Extension-visible: +WritingAnalysis, +Download
    var modelContainer: ModelContainer?
    var apiClient: (any LLMClient)?
    var currentModelType: ModelType = .mlx
    var analyzeTask: Task<Void, Never>?
    let logger = Logger(subsystem: AppConstants.bundleID, category: "LLMEngine")

    /// Serialization gate for inference calls. Both `complete()` and `completeStream()` chain
    /// onto this task. Assigned synchronously (no suspension between read and write) so actor
    /// reentrancy cannot break the FIFO ordering. Each new caller captures the current gate,
    /// creates a new gate, and the work runs only after the prior gate completes.
    private var inferenceGate: Task<Void, Never>?

    /// Tracks how many inference calls are currently queued/running. Rejects new calls
    /// when the queue exceeds this limit to prevent GPU memory thrashing during bulk operations.
    private var inferenceQueueDepth: Int = 0
    private static let maxInferenceQueueDepth = 4

    // MARK: - Shared Prompts

    /// Base Logue personality prompt, sourced from `PromptRegistry.System.base`.
    static let chatSystemPrompt = PromptRegistry.System.base.content

    // MARK: - Model Lifecycle

    func loadModel(from directory: URL) async throws {
        analyzeTask?.cancel()
        analyzeTask = nil

        // Explicitly release old container/client to free GPU memory before loading new model.
        modelContainer = nil
        apiClient = nil

        // Brief yield to allow Metal resource deallocation from the previous model.
        try? await Task.sleep(for: AppConstants.Delays.metalDeallocationYield)

        guard !Task.isCancelled else { throw CancellationError() }

        // Check available memory before loading to prevent OS kill on low-memory devices.
        // Uses vm_statistics64 for system-wide free + purgeable memory (accounts for all processes),
        // unlike mach_task_basic_info.resident_size which only measures this process's footprint.
        var vmStats = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let vmResult = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { intPtr in
                host_statistics64(host, HOST_VM_INFO64, intPtr, &vmCount)
            }
        }
        if vmResult == KERN_SUCCESS {
            let pageSize = UInt64(vm_kernel_page_size)
            // Include inactive_count: macOS aggressively caches, so free_count alone is often very low
            // on healthy systems. Inactive pages are reclaimable by the OS under memory pressure.
            let freeMB = (UInt64(vmStats.free_count) + UInt64(vmStats.purgeable_count) + UInt64(vmStats.inactive_count)) * pageSize / (1024 * 1024)
            if freeMB < 512 {
                logger.error("Insufficient memory to load model: ~\(freeMB)MB available (need 512MB+)")
                throw LLMError.notLoaded
            }
            logger.info("Loading model into LLMEngine… (~\(freeMB)MB available)")
        } else {
            logger.info("Loading model into LLMEngine…")
        }
        guard !Task.isCancelled else { throw CancellationError() }

        // Load and prewarm with a timeout to avoid hanging indefinitely.
        let container: ModelContainer = try await withThrowingTaskGroup(of: ModelContainer.self) { group in
            group.addTask {
                try await LLMModelFactory.shared.loadContainer(
                    from: directory,
                    using: TransformersLoader()
                )
            }
            group.addTask {
                try await Task.sleep(for: AppConstants.Delays.llmPrewarmTimeout)
                throw LLMError.prewarmTimeout
            }
            // First task to complete (or throw) wins.
            let result = try await group.next()
            group.cancelAll()
            guard let result else { throw LLMError.notLoaded }
            return result
        }

        guard !Task.isCancelled else { throw CancellationError() }

        modelContainer = container
        currentModelType = .mlx
        logger.info("Model ready.")
    }

    /// Accepts a pre-loaded `ModelContainer` (e.g. from download) without re-loading from disk.
    /// Performs the same memory availability check as `loadModel(from:)` to prevent OOM kills
    /// during model swap — the old model's Metal resources need headroom during deallocation.
    func loadContainer(_ container: ModelContainer) async throws {
        analyzeTask?.cancel()
        analyzeTask = nil
        modelContainer = nil
        apiClient = nil
        try? await Task.sleep(for: AppConstants.Delays.metalDeallocationYield)
        guard !Task.isCancelled else { throw CancellationError() }

        // Check available memory before assigning — old model's Metal resources may still
        // be deallocating and the system needs headroom during the swap window.
        var vmStats = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let vmResult = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { intPtr in
                host_statistics64(host, HOST_VM_INFO64, intPtr, &vmCount)
            }
        }
        if vmResult == KERN_SUCCESS {
            let pageSize = UInt64(vm_kernel_page_size)
            let freeMB = (UInt64(vmStats.free_count) + UInt64(vmStats.purgeable_count) + UInt64(vmStats.inactive_count)) * pageSize / (1024 * 1024)
            if freeMB < 512 {
                logger.error("Insufficient memory to activate model: ~\(freeMB)MB available (need 512MB+)")
                throw LLMError.notLoaded
            }
            logger.info("Activating pre-loaded model… (~\(freeMB)MB available)")
        } else {
            logger.info("Activating pre-loaded model…")
        }
        guard !Task.isCancelled else { throw CancellationError() }

        modelContainer = container
        currentModelType = .mlx
        logger.info("Model ready (pre-loaded container).")
    }

    func loadAPISession(config: Logue.ModelConfiguration) async throws {
        analyzeTask?.cancel()
        analyzeTask = nil

        // Release old container/client before connecting to API.
        modelContainer = nil
        apiClient = nil

        logger.info("Connecting to \(config.providerType.displayName) API…")
        let client = try LLMClientFactory.makeClient(for: config)
        try await client.testConnection()
        apiClient = client
        currentModelType = .api
        logger.info("API client ready (\(config.providerType.displayName)).")
    }

    /// Legacy convenience — builds a config and delegates to `loadAPISession(config:)`.
    func loadAPISession(endpoint: String, apiKey: String?, modelName: String) async throws {
        let config = Logue.ModelConfiguration(
            id: "legacy-api",
            type: .api,
            displayName: "API",
            description: "",
            endpoint: endpoint,
            apiKey: apiKey,
            modelName: modelName,
            requiresAuth: apiKey != nil
        )
        try await loadAPISession(config: config)
    }

    func releaseSession() {
        analyzeTask?.cancel()
        analyzeTask = nil
        modelContainer = nil
        apiClient = nil
        logger.info("Session released.")
    }

    var isModelLoaded: Bool {
        modelContainer != nil || apiClient != nil
    }

    // MARK: - Core Inference

    /// Core inference method. All generation methods route through this.
    /// Serializes access via `inferenceGate`: each call chains onto the prior gate so only
    /// one inference runs at a time. The gate is assigned synchronously (before any suspension)
    /// to prevent actor reentrancy from breaking the FIFO chain.
    func complete(system: String, prompt: String, temperature: Double = 0.7, maxTokens: Int = 512) async throws -> String {
        // Reject if too many calls are already queued (prevents GPU thrashing during bulk ops)
        let currentDepth = inferenceQueueDepth
        guard currentDepth < Self.maxInferenceQueueDepth else {
            logger.warning("Inference queue full (\(currentDepth) pending) — rejecting call")
            throw LLMError.queueFull
        }
        inferenceQueueDepth += 1
        notifyBusyState()

        // Capture all state synchronously — no suspension between reading gate and assigning new gate.
        // This prevents actor reentrancy from letting two callers both read the same prior gate.
        let pendingAnalyze = analyzeTask
        analyzeTask = nil
        let priorGate = inferenceGate
        let capturedAPIClient = apiClient
        let capturedContainer = modelContainer

        guard capturedAPIClient != nil || capturedContainer != nil else {
            inferenceQueueDepth -= 1
            notifyBusyState()
            throw LLMError.notLoaded
        }

        // Gate signal: the inner task finishes this continuation when inference is done.
        // Uses the same pattern as completeStream() for unified depth management.
        let (gateSignal, gateCont) = AsyncStream<Void>.makeStream()
        let engine = self
        inferenceGate = Task {
            for await _ in gateSignal {}
            await engine.decrementInferenceQueueDepth()
        }

        // Chain onto prior gate — work runs only after prior completes.
        let task = Task<String, Error> {
            pendingAnalyze?.cancel()
            await pendingAnalyze?.value
            await priorGate?.value
            defer { gateCont.finish() }

            if let client = capturedAPIClient {
                return try await client.chat(
                    messages: [
                        LLMMessage(role: .system, content: system),
                        LLMMessage(role: .user, content: prompt),
                    ],
                    temperature: temperature,
                    maxTokens: maxTokens
                )
            } else if let container = capturedContainer {
                return try await Self.generateText(
                    container: container, system: system, prompt: prompt,
                    maxTokens: maxTokens, temperature: Float(temperature)
                )
            } else {
                throw LLMError.notLoaded
            }
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: - Streaming Completion

    /// Streaming variant of `complete()`. Yields tokens as they arrive.
    /// Participates in the same `inferenceGate` chain as `complete()`, so streaming and
    /// non-streaming calls are properly serialized against each other.
    func completeStream(
        system: String,
        prompt: String,
        temperature: Double = 0.7,
        maxTokens: Int = 512
    ) -> AsyncThrowingStream<String, Error> {
        // Reject if too many calls are already queued (prevents GPU thrashing during bulk ops)
        let currentDepth = inferenceQueueDepth
        guard currentDepth < Self.maxInferenceQueueDepth else {
            logger.warning("Inference queue full (\(currentDepth) pending) — rejecting stream call")
            return AsyncThrowingStream { $0.finish(throwing: LLMError.queueFull) }
        }
        inferenceQueueDepth += 1
        notifyBusyState()

        // Capture state synchronously — no suspension between reading gate and assigning new gate
        let pendingAnalyze = analyzeTask
        pendingAnalyze?.cancel()
        analyzeTask = nil
        let priorGate = inferenceGate
        let engine = self

        // Gate signal: the stream task finishes this continuation when inference is done.
        // The gate task awaits the signal, then decrements the queue depth on the actor.
        // Captures `engine` strongly — LLMEngine is a singleton, so no retain cycle risk,
        // and this ensures the depth decrement always fires.
        let (gateSignal, gateCont) = AsyncStream<Void>.makeStream()
        inferenceGate = Task {
            for await _ in gateSignal {}
            await engine.decrementInferenceQueueDepth()
        }

        if let apiClient {
            return buildAPIStream(
                client: apiClient, system: system, prompt: prompt,
                temperature: temperature, maxTokens: maxTokens,
                priorGate: priorGate, pendingAnalyze: pendingAnalyze, gateCont: gateCont
            )
        } else if let modelContainer {
            return buildMLXStream(
                container: modelContainer, system: system, prompt: prompt,
                maxTokens: maxTokens, temperature: Float(temperature),
                priorGate: priorGate, pendingAnalyze: pendingAnalyze, gateCont: gateCont
            )
        } else {
            // No model loaded — signal gate immediately
            gateCont.finish()
            return AsyncThrowingStream { $0.finish(throwing: LLMError.notLoaded) }
        }
    }

    // Serialization context (gate + pending tasks) requires passing 8 params
    // swiftlint:disable:next function_parameter_count
    private func buildAPIStream(
        client: any LLMClient,
        system: String, prompt: String,
        temperature: Double, maxTokens: Int,
        priorGate: Task<Void, Never>?,
        pendingAnalyze: Task<Void, Never>?,
        gateCont: AsyncStream<Void>.Continuation
    ) -> AsyncThrowingStream<String, Error> {
        let messages = [LLMMessage(role: .system, content: system), LLMMessage(role: .user, content: prompt)]
        return AsyncThrowingStream { continuation in
            let task = Task {
                await pendingAnalyze?.value
                await priorGate?.value
                defer { gateCont.finish() }
                do {
                    for try await token in await client.streamChat(messages: messages, temperature: temperature, maxTokens: maxTokens) {
                        if Task.isCancelled {
                            continuation.finish(throwing: CancellationError()); return
                        }
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            // Also finish the gate if the stream is never consumed or terminated early,
            // preventing a permanent deadlock of the inference FIFO chain.
            continuation.onTermination = { _ in
                task.cancel()
                gateCont.finish()
            }
        }
    }

    /// Runs a single system+user prompt through the MLX model and collects the full response.
    private static func generateText(
        container: ModelContainer, system: String, prompt: String,
        maxTokens: Int, temperature: Float
    ) async throws -> String {
        let messages: [[String: String]] = [
            ["role": "system", "content": system],
            ["role": "user", "content": prompt],
        ]
        let tokenizer = await container.tokenizer
        let inputTokens = try tokenizer.applyChatTemplate(messages: messages)
        let input = LMInput(tokens: MLXArray(inputTokens))
        var params = defaultGenerateParameters
        params.maxTokens = maxTokens
        params.temperature = temperature
        let stream = try await container.generate(input: input, parameters: params)
        var output = ""
        for await generation in stream {
            if Task.isCancelled {
                break
            }
            if let chunk = generation.chunk {
                output += chunk
            }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Serialization context (gate + pending tasks) requires passing 8 params
    // swiftlint:disable:next function_parameter_count
    private func buildMLXStream(
        container: ModelContainer,
        system: String, prompt: String,
        maxTokens: Int, temperature: Float,
        priorGate: Task<Void, Never>?,
        pendingAnalyze: Task<Void, Never>?,
        gateCont: AsyncStream<Void>.Continuation
    ) -> AsyncThrowingStream<String, Error> {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let task = Task {
            await pendingAnalyze?.value
            await priorGate?.value
            defer { gateCont.finish() }
            do {
                let messages: [[String: String]] = [
                    ["role": "system", "content": system],
                    ["role": "user", "content": prompt],
                ]
                let tokenizer = await container.tokenizer
                let inputTokens = try tokenizer.applyChatTemplate(messages: messages)
                let input = LMInput(tokens: MLXArray(inputTokens))
                var params = Self.defaultGenerateParameters
                params.maxTokens = maxTokens
                params.temperature = temperature
                let genStream = try await container.generate(input: input, parameters: params)
                for await generation in genStream {
                    if Task.isCancelled {
                        continuation.finish(throwing: CancellationError()); return
                    }
                    if let chunk = generation.chunk {
                        continuation.yield(chunk)
                    }
                }
                continuation.finish()
            } catch { continuation.finish(throwing: error) }
        }
        // Also finish the gate if the stream is never consumed or terminated early,
        // preventing a permanent deadlock of the inference FIFO chain.
        continuation.onTermination = { _ in
            task.cancel()
            gateCont.finish()
        }
        return stream
    }

    // MARK: - Tool-Calling Generation

    // Streams generation with native tool calling support.
    // Returns `Generation` values: `.chunk(String)` for text, `.toolCall(ToolCall)` for tool calls.
    // Participates in the same `inferenceGate` chain as `complete()` and `completeStream()`.
    // swiftlint:disable:next function_body_length
    func completeWithTools(
        messages: [[String: any Sendable]],
        tools: [ToolSpec],
        temperature: Double = 0.3,
        maxTokens: Int = 2048
    ) -> AsyncThrowingStream<Generation, Error> {
        let currentDepth = inferenceQueueDepth
        guard currentDepth < Self.maxInferenceQueueDepth else {
            logger.warning("Inference queue full — rejecting tool call")
            return AsyncThrowingStream { $0.finish(throwing: LLMError.queueFull) }
        }
        inferenceQueueDepth += 1
        notifyBusyState()

        let pendingAnalyze = analyzeTask
        pendingAnalyze?.cancel()
        analyzeTask = nil
        let priorGate = inferenceGate
        let engine = self

        let (gateSignal, gateCont) = AsyncStream<Void>.makeStream()
        inferenceGate = Task {
            for await _ in gateSignal {}
            await engine.decrementInferenceQueueDepth()
        }

        guard let container = modelContainer else {
            gateCont.finish()
            return AsyncThrowingStream { $0.finish(throwing: LLMError.notLoaded) }
        }

        let (stream, continuation) = AsyncThrowingStream<Generation, Error>.makeStream()

        let task = Task {
            await pendingAnalyze?.value
            await priorGate?.value
            defer { gateCont.finish() }

            do {
                let tokenizer = await container.tokenizer
                let inputTokens = try tokenizer.applyChatTemplate(
                    messages: messages,
                    tools: tools,
                    additionalContext: nil
                )
                let input = LMInput(tokens: MLXArray(inputTokens))
                var params = Self.defaultGenerateParameters
                params.maxTokens = maxTokens
                params.temperature = Float(temperature)
                let genStream = try await container.generate(input: input, parameters: params)

                // Use ToolCallProcessor to detect tool calls during streaming
                let processor = ToolCallProcessor(tools: tools)

                for await generation in genStream {
                    if Task.isCancelled {
                        continuation.finish(throwing: CancellationError()); return
                    }
                    switch generation {
                    case let .chunk(text):
                        // Feed through processor — it buffers tool call content
                        if let passthrough = processor.processChunk(text) {
                            continuation.yield(.chunk(passthrough))
                        }
                    case .info:
                        // Forward performance info
                        continuation.yield(generation)
                    case .toolCall:
                        // Direct tool call from model (some formats emit directly)
                        continuation.yield(generation)
                    }
                }

                // Process end-of-sequence to flush any buffered tool calls
                processor.processEOS()
                for toolCall in processor.toolCalls {
                    continuation.yield(.toolCall(toolCall))
                }

                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { _ in
            task.cancel()
            gateCont.finish()
        }

        return stream
    }

    /// Decrements the inference queue depth on the actor. Called by gate tasks when inference completes.
    func decrementInferenceQueueDepth() {
        inferenceQueueDepth -= 1
        notifyBusyState()
    }

    /// Sends the current busy state to MainActor. Cancels any prior in-flight update so
    /// out-of-order task delivery cannot leave `isBusy` stuck in the wrong state.
    private var busyStateTask: Task<Void, Never>?
    private func notifyBusyState() {
        busyStateTask?.cancel()
        let busy = inferenceQueueDepth > 0
        busyStateTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            LLMEngineStatus.shared.setBusy(busy)
        }
    }

    /// Calculates the maximum number of input characters that fit within the model's context window.
    /// Uses ~4 chars/token heuristic. `reservedTokens` covers output + system prompt overhead.
    static func maxInputChars(reservedTokens: Int) -> Int {
        (maxKVSize - reservedTokens) * 4
    }

    /// Streaming variant of `chat()` for the AI chat panel.
    func chatStream(prompt: String) -> AsyncThrowingStream<String, Error> {
        completeStream(
            system: Self.chatSystemPrompt
                + "\n\nAnswer any question the user has. "
                + "If document context is provided, use it to give informed answers. "
                + "For simple questions or greetings, respond naturally and conversationally. "
                + "Use markdown formatting only when it genuinely aids readability.",
            prompt: prompt,
            maxTokens: 2048
        )
    }

    // MARK: - Streaming Analysis (overlay use)

    /// C2: Analyses `request.text` and streams `Suggestion` values as the LLM responds.
    /// analyzeTask mutation happens on the actor (before returning), not inside the stream closure.
    func analyze(_ request: TextAnalysisRequest) async -> AsyncStream<Suggestion> {
        analyzeTask?.cancel()
        await analyzeTask?.value
        analyzeTask = nil

        guard let capturedContainer = modelContainer else {
            logger.warning("analyze() called but no model is loaded.")
            return AsyncStream { $0.finish() }
        }

        let system = PromptBuilder.systemPrompt(for: request.goalMode)
        let userMessage = PromptBuilder.userMessage(for: request)

        let (stream, continuation) = AsyncStream<Suggestion>.makeStream()
        analyzeTask = Task {
            do {
                let messages: [[String: String]] = [
                    ["role": "system", "content": system],
                    ["role": "user", "content": userMessage],
                ]
                let tokenizer = await capturedContainer.tokenizer
                let inputTokens = try tokenizer.applyChatTemplate(messages: messages)
                let input = LMInput(tokens: MLXArray(inputTokens))
                var params = Self.defaultGenerateParameters
                params.maxTokens = Self.defaultMaxTokens
                params.temperature = 0.7
                let genStream = try await capturedContainer.generate(input: input, parameters: params)

                var parser = SuggestionParser()
                for await generation in genStream {
                    if Task.isCancelled {
                        break
                    }
                    if let chunk = generation.chunk {
                        for suggestion in parser.consume(token: chunk) {
                            continuation.yield(suggestion)
                        }
                    }
                }
                if !Task.isCancelled {
                    for suggestion in parser.flush() {
                        continuation.yield(suggestion)
                    }
                }
            } catch {
                logger.error("Analysis error: \(error.localizedDescription, privacy: .public)")
            }
            continuation.finish()
        }
        return stream
    }

    func cancelAnalysis() {
        analyzeTask?.cancel()
        analyzeTask = nil
    }
}

// MARK: - Errors

enum LLMError: Error, LocalizedError {
    case notLoaded
    case modelNotDownloaded
    case prewarmTimeout
    case emptyResponse
    case queueFull

    var errorDescription: String? {
        switch self {
        case .notLoaded:
            "No model is loaded. Please download and activate a model in Settings."
        case .modelNotDownloaded:
            "Model has not been downloaded yet."
        case .prewarmTimeout:
            "Model took too long to load. Please try again or choose a smaller model."
        case .emptyResponse:
            "The model returned an empty response."
        case .queueFull:
            "The inference engine is busy. Please wait a moment and try again."
        }
    }
}
