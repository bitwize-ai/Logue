import Foundation
import NaturalLanguage
import os.log

/// On-device sentence embedding service backed by Apple's `NLContextualEmbedding`
/// (macOS 14+). Wraps loading + token-vector mean-pooling + L2 normalization so
/// callers get a single `[Float]` per input string.
///
/// Used by Phase 3 (cross-conversation memory) and Phase 4 (semantic RAG over
/// meetings & documents). Stays Apple-native to avoid pulling in DistilBERT or
/// any extra ML asset, and to keep embedding work off the MLX `inferenceGate`.
///
/// Thread-safety: `actor` — all access serializes through Swift's actor isolation.
/// Embedding work happens on the actor's executor (background), not the main thread.
actor EmbeddingService {
    static let shared = EmbeddingService()

    private var embedder: NLContextualEmbedding?
    /// In-flight load task — coalesces concurrent `embed` calls during cold start.
    private var loadTask: Task<NLContextualEmbedding, Error>?

    private let logger = Logger(subsystem: AppConstants.bundleID, category: "EmbeddingService")

    enum EmbeddingError: Error, LocalizedError {
        case unavailable
        case loadFailed(String)
        case embeddingFailed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable: "Contextual embedding model is not available on this OS."
            case let .loadFailed(reason): "Failed to load embedding model: \(reason)"
            case let .embeddingFailed(reason): "Failed to embed text: \(reason)"
            }
        }
    }

    private init() {}

    // MARK: - Public

    /// Returns an L2-normalized vector for `text`, suitable for cosine similarity
    /// against other vectors produced by the same call. Inputs longer than the
    /// model's token limit are silently truncated by the underlying framework;
    /// callers should chunk upstream for best results.
    func embed(_ text: String) async throws -> [Float] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw EmbeddingError.embeddingFailed("Empty input")
        }

        let model = try await getOrLoad()

        let result: NLContextualEmbeddingResult
        do {
            result = try model.embeddingResult(for: trimmed, language: .english)
        } catch {
            throw EmbeddingError.embeddingFailed(error.localizedDescription)
        }

        // Mean-pool token vectors into a single sentence vector.
        let dim = model.dimension
        var sum = [Double](repeating: 0, count: dim)
        var count = 0
        var dimMismatch = false
        result.enumerateTokenVectors(in: trimmed.startIndex ..< trimmed.endIndex) { vector, _ in
            guard vector.count == dim else {
                // Bail rather than silently dropping the vector — a bad token
                // would bias the mean toward the surviving vectors and
                // produce a misleading embedding for cosine search.
                dimMismatch = true
                return false
            }
            for i in 0 ..< dim {
                sum[i] += vector[i]
            }
            count += 1
            return true
        }
        if dimMismatch {
            throw EmbeddingError.embeddingFailed(
                "Token vector dimension mismatch (expected \(dim))"
            )
        }
        guard count > 0 else {
            throw EmbeddingError.embeddingFailed("No token vectors produced")
        }

        // Normalize to unit length so cosine similarity reduces to a dot product.
        var floats = [Float](repeating: 0, count: dim)
        var sqSum: Double = 0
        for i in 0 ..< dim {
            let mean = sum[i] / Double(count)
            floats[i] = Float(mean)
            sqSum += mean * mean
        }
        let norm = sqSum.squareRoot()
        if norm > 0 {
            let invNorm = Float(1.0 / norm)
            for i in 0 ..< dim {
                floats[i] *= invNorm
            }
        }
        return floats
    }

    /// The dimensionality of the embedding (set after first load). Useful for
    /// VectorStore schema sanity checks.
    func dimension() async throws -> Int {
        try await getOrLoad().dimension
    }

    // MARK: - Loading

    private func getOrLoad() async throws -> NLContextualEmbedding {
        if let embedder {
            return embedder
        }
        if let loadTask {
            // Another caller is loading — await the same task instead of double-loading.
            return try await loadTask.value
        }
        let task = Task<NLContextualEmbedding, Error> { [weak self] in
            try await Self.loadFromFramework(logger: self?.logger)
        }
        loadTask = task
        do {
            let model = try await task.value
            embedder = model
            loadTask = nil
            return model
        } catch {
            loadTask = nil
            throw error
        }
    }

    private static func loadFromFramework(logger: Logger?) async throws -> NLContextualEmbedding {
        guard let model = NLContextualEmbedding(language: .english) else {
            throw EmbeddingError.unavailable
        }
        // `load()` synchronously downloads the embedding asset on first use. On
        // success it's idempotent — subsequent calls are no-ops.
        do {
            try model.load()
        } catch {
            // Surface the real error rather than swallowing it. CLAUDE.md: never silent try?.
            logger?.error("NLContextualEmbedding load failed: \(error.localizedDescription, privacy: .public)")
            throw EmbeddingError.loadFailed(error.localizedDescription)
        }
        return model
    }

    // MARK: - Cosine Similarity

    /// Cosine similarity for L2-normalized inputs (reduces to dot product).
    /// For non-normalized inputs the result is undefined.
    nonisolated static func cosine(_ lhs: [Float], _ rhs: [Float]) -> Float {
        // nonisolated: pure function over its args, no shared state.
        guard lhs.count == rhs.count else { return 0 }
        var sum: Float = 0
        for i in 0 ..< lhs.count {
            sum += lhs[i] * rhs[i]
        }
        return sum
    }
}
