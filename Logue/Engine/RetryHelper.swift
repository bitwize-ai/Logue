import Foundation

/// A1: Centralized retry utility to eliminate 15+ duplicated retry blocks.
/// Retries an async throwing operation with configurable attempts and delay.
func withRetry<T>(
    maxAttempts: Int = AppConstants.LLMDefaults.maxRetryAttempts,
    delay: Duration = AppConstants.LLMDefaults.retryDelay,
    operation: () async throws -> T
) async throws -> T {
    var lastError: Error = LLMError.notLoaded
    for attempt in 1 ... maxAttempts {
        do {
            return try await operation()
        } catch {
            if error is CancellationError {
                throw error
            }
            lastError = error
        }
        if attempt < maxAttempts {
            try? await Task.sleep(for: delay)
        }
    }
    throw lastError
}

/// Bug-1: Variant that returns an optional instead of throwing on final failure.
/// Checks Task.isCancelled before attempting, so cancellation propagates immediately.
func withRetryOptional<T>(
    maxAttempts: Int = AppConstants.LLMDefaults.maxRetryAttempts,
    delay: Duration = AppConstants.LLMDefaults.retryDelay,
    operation: () async throws -> T
) async -> T? {
    guard !Task.isCancelled else { return nil }
    return try? await withRetry(maxAttempts: maxAttempts, delay: delay, operation: operation)
}
