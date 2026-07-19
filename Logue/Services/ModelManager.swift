import Foundation
import Observation
import os.log

@MainActor
@Observable
final class ModelManager {
    static let shared = ModelManager()
    private init() {
        activeModelID = UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.activeModelID)
        loadCustomModels()
        loadActionModelMap()
    }

    // MARK: - State

    let presets: [ModelConfiguration] = ModelConfiguration.allPresets

    private(set) var customModels: [ModelConfiguration] = []

    /// Maps each `ModelAction` to a specific model ID.
    /// When empty (default), every action falls back to the global `activeModel`.
    private(set) var actionModelMap: [ModelAction: String] = [:]

    var allModels: [ModelConfiguration] {
        presets + customModels
    }

    var activeModelID: String? {
        didSet {
            UserDefaults.standard.setValue(activeModelID, forKey: AppConstants.UserDefaultsKeys.activeModelID)
        }
    }

    var activeModel: ModelConfiguration? {
        guard let id = activeModelID else { return nil }
        return allModels.first { $0.id == id }
    }

    // Extension-visible: +Download needs read/write for download lifecycle.
    // Do NOT access setters from outside ModelManager and its extensions.
    private(set) var downloadingID: String?
    private(set) var downloadProgress: Double = 0
    private(set) var isActivating: Bool = false
    private(set) var activatingModelID: String?
    private(set) var activationError: String?
    /// The model ID that `activationError` belongs to.
    private(set) var activationErrorModelID: String?
    private(set) var downloadError: String?
    // Extension-visible: +Download bumps this after download/delete to force SwiftUI re-evaluation.
    private(set) var downloadStateVersion: Int = 0

    // Custom MLX model fetch state
    // Extension-visible: +HuggingFace needs read/write.
    private(set) var isFetchingModelInfo = false
    private(set) var fetchModelError: String?

    // MARK: - Connection & Discovery State

    // Extension-visible: +Discovery needs read/write.
    private(set) var connectionStatuses: [String: ConnectionStatus] = [:]
    private(set) var discoveredModels: [String: [String]] = [:]
    private(set) var scanningEndpoints: Set<String> = []

    // Extension-visible: +Download needs read/write for task lifecycle.
    private(set) var downloadTask: Task<Void, Never>?
    /// Incremented on each new download or cancel. Progress callbacks capture this
    /// value and are ignored if it no longer matches, which prevents zombie
    /// URLSession tasks (that outlive Task.cancel()) from updating the UI.
    private(set) var downloadGeneration: Int = 0
    let logger = Logger(subsystem: AppConstants.bundleID, category: "ModelManager")

    // MARK: - Extension-Visible Setters

    // These setters allow extension files (+Download, +Discovery, +HuggingFace) to mutate
    // state that is private(set) to prevent accidental mutation from outside the class.

    func setDownloadingID(_ id: String?) {
        downloadingID = id
    }

    func setDownloadProgress(_ progress: Double) {
        // Allow resets to 0 (cancel/error) and explicit completion (1.0).
        // Otherwise enforce monotonic increase — HubClient's Progress object
        // can briefly report lower fractionCompleted when multiple files
        // download concurrently and update the shared Progress from different threads.
        if progress > 0, progress < 1.0, progress <= downloadProgress {
            return
        }
        downloadProgress = progress
    }

    func setIsActivating(_ value: Bool) {
        isActivating = value
    }

    func setActivatingModelID(_ id: String?) {
        activatingModelID = id
    }

    func setActivationError(_ error: String?) {
        activationError = error
    }

    func setActivationErrorModelID(_ id: String?) {
        activationErrorModelID = id
    }

    func setDownloadError(_ error: String?) {
        downloadError = error
    }

    func setIsFetchingModelInfo(_ value: Bool) {
        isFetchingModelInfo = value
    }

    func setFetchModelError(_ error: String?) {
        fetchModelError = error
    }

    func setConnectionStatus(_ status: ConnectionStatus, for modelID: String) {
        connectionStatuses[modelID] = status
    }

    func setDiscoveredModels(_ models: [String], for modelID: String) {
        discoveredModels[modelID] = models
    }

    func insertScanningEndpoint(_ id: String) {
        scanningEndpoints.insert(id)
    }

    func removeScanningEndpoint(_ id: String) {
        scanningEndpoints.remove(id)
    }

    func setDownloadTask(_ task: Task<Void, Never>?) {
        downloadTask = task
    }

    func incrementDownloadGeneration() {
        downloadGeneration += 1
    }

    func incrementDownloadStateVersion() {
        downloadStateVersion += 1
    }

    // MARK: - Computed State

    func isDownloaded(_ record: ModelConfiguration) -> Bool {
        _ = downloadStateVersion // Establish @Observable tracking for SwiftUI re-evaluation
        if record.type == .api {
            return true // API endpoints don't need downloading
        }
        guard let repoId = record.hfRepoID else { return false }
        return Self.isModelDownloaded(repoID: repoId)
    }

    func isDownloading(_ record: ModelConfiguration) -> Bool {
        downloadingID == record.id
    }

    // MARK: - Action ↔ Model Mapping

    /// Returns the model assigned to a specific action.
    /// Falls back to the global `activeModel` when no override is set.
    func model(for action: ModelAction) -> ModelConfiguration? {
        if let overrideID = actionModelMap[action],
           let override = allModels.first(where: { $0.id == overrideID })
        {
            return override
        }
        return activeModel
    }

    /// Assign a specific model to an action, or pass `nil` to clear the
    /// override and fall back to the global active model.
    func setModel(_ modelID: String?, for action: ModelAction) {
        if let modelID {
            actionModelMap[action] = modelID
        } else {
            actionModelMap.removeValue(forKey: action)
        }
        saveActionModelMap()
    }

    // MARK: - Custom Models Management

    func addCustomModel(_ model: ModelConfiguration) {
        customModels.append(model)
        saveCustomModels()
    }

    func updateCustomModel(_ model: ModelConfiguration) {
        guard let idx = customModels.firstIndex(where: { $0.id == model.id }) else { return }
        customModels[idx] = model
        saveCustomModels()

        // If this is the active model, re-activate with new config
        if activeModelID == model.id {
            downloadAndActivate(model)
        }
    }

    func removeCustomModel(id: String) {
        customModels.removeAll { $0.id == id }
        KeychainHelper.delete(key: "api_key_\(id)")
        saveCustomModels()
        if activeModelID == id {
            activeModelID = nil
            Task { await LLMEngine.shared.releaseSession() }
        }
    }

    // MARK: - Persistence

    private func saveCustomModels() {
        // Store secrets in Keychain, strip them from the UserDefaults copy
        var sanitized: [ModelConfiguration] = []
        for model in customModels {
            // S4: Use stricter Keychain accessibility for API keys
            if let key = model.apiKey, !key.isEmpty {
                try? KeychainHelper.saveData(
                    key: "api_key_\(model.id)",
                    data: Data(key.utf8),
                    accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                )
            }
            sanitized.append(ModelConfiguration(
                id: model.id,
                type: model.type,
                displayName: model.displayName,
                description: model.description,
                hfRepoID: model.hfRepoID,
                sizeGB: model.sizeGB,
                minRAMGB: model.minRAMGB,
                endpoint: model.endpoint,
                apiKey: nil, // stripped — stored in Keychain
                modelName: model.modelName,
                requiresAuth: model.requiresAuth,
                providerType: model.providerType,
                isRecommended: model.isRecommended
            ))
        }
        do {
            let data = try JSONEncoder().encode(sanitized)
            UserDefaults.standard.set(data, forKey: AppConstants.UserDefaultsKeys.customAPIModels)
        } catch {
            logger.error("Failed to save custom models: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadCustomModels() {
        guard let data = UserDefaults.standard.data(forKey: AppConstants.UserDefaultsKeys.customAPIModels) else { return }
        let models: [ModelConfiguration]
        do {
            models = try JSONDecoder().decode([ModelConfiguration].self, from: data)
        } catch {
            logger.error("Failed to decode custom models: \(error.localizedDescription, privacy: .public)")
            return
        }
        // Hydrate secrets from Keychain
        customModels = models.map { model in
            let storedKey = try? KeychainHelper.read(key: "api_key_\(model.id)")
            return ModelConfiguration(
                id: model.id,
                type: model.type,
                displayName: model.displayName,
                description: model.description,
                hfRepoID: model.hfRepoID,
                sizeGB: model.sizeGB,
                minRAMGB: model.minRAMGB,
                endpoint: model.endpoint,
                apiKey: (storedKey?.isEmpty == false) ? storedKey : model.apiKey,
                modelName: model.modelName,
                requiresAuth: model.requiresAuth,
                providerType: model.providerType,
                isRecommended: model.isRecommended
            )
        }
    }

    private func saveActionModelMap() {
        let raw = Dictionary(uniqueKeysWithValues: actionModelMap.map { ($0.key.rawValue, $0.value) })
        do {
            let data = try JSONEncoder().encode(raw)
            UserDefaults.standard.set(data, forKey: AppConstants.UserDefaultsKeys.actionModelMap)
        } catch {
            logger.error("Failed to save action model map: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadActionModelMap() {
        guard let data = UserDefaults.standard.data(forKey: AppConstants.UserDefaultsKeys.actionModelMap) else { return }
        guard let raw = try? JSONDecoder().decode([String: String].self, from: data) else {
            logger.error("Failed to decode action model map")
            return
        }
        actionModelMap = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            guard let action = ModelAction(rawValue: key) else { return nil }
            return (action, value)
        })
    }
}
