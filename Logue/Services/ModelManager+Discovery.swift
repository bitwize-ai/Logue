import Foundation

// MARK: - Connection & Discovery

extension ModelManager {
    func connectionStatus(for modelID: String) -> ConnectionStatus {
        connectionStatuses[modelID] ?? .idle
    }

    func testConnection(for record: ModelConfiguration) {
        setConnectionStatus(.checking, for: record.id)

        Task { [weak self] in
            guard let self else { return }
            do {
                let client = try LLMClientFactory.makeClient(for: record)
                try await client.testConnection()
                setConnectionStatus(.connected, for: record.id)
                logger.info("Connection test passed: \(record.id, privacy: .public)")
            } catch {
                setConnectionStatus(.error(error.localizedDescription), for: record.id)
                logger.error("Connection test failed for \(record.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func scanModels(for record: ModelConfiguration) {
        insertScanningEndpoint(record.id)
        setConnectionStatus(.checking, for: record.id)

        Task { [weak self] in
            guard let self else { return }
            do {
                let client = try LLMClientFactory.makeClient(for: record)
                let models = try await client.listModels()
                setDiscoveredModels(models, for: record.id)
                setConnectionStatus(.connected, for: record.id)
                logger.info("Scanned \(models.count) models from \(record.id, privacy: .public)")
            } catch {
                setConnectionStatus(.error(error.localizedDescription), for: record.id)
                logger.error("Scan failed for \(record.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            removeScanningEndpoint(record.id)
        }
    }

    /// Scans models from a provider configuration.
    func scanModelsForConfig(_ config: ModelConfiguration) async -> [String] {
        do {
            let client = try LLMClientFactory.makeClient(for: config)
            return try await client.listModels()
        } catch {
            logger.error("Config scan failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Legacy convenience for OpenAI-compatible endpoints.
    func scanModelsFromEndpoint(endpoint: String, apiKey: String?) async -> [String] {
        // SSRF protection: block private/internal network targets
        if let url = URL(string: endpoint), url.isPrivateOrMetadataEndpoint {
            logger.warning("Blocked model scan to private/metadata endpoint: \(URL(string: endpoint)?.host ?? "unknown", privacy: .public)")
            return []
        }
        let config = ModelConfiguration(
            id: "scan-temp", type: .api, displayName: "", description: "",
            endpoint: endpoint, apiKey: apiKey, modelName: nil,
            requiresAuth: apiKey != nil
        )
        return await scanModelsForConfig(config)
    }

    func addDiscoveredModel(from record: ModelConfiguration, modelName: String) {
        let config = ModelConfiguration(
            id: UUID().uuidString,
            type: .api,
            displayName: "\(modelName) (\(record.providerType.displayName))",
            description: "Discovered from \(record.providerType.displayName).",
            endpoint: record.endpoint,
            apiKey: record.apiKey,
            modelName: modelName,
            requiresAuth: record.requiresAuth
        )
        addCustomModel(config)
    }
}
