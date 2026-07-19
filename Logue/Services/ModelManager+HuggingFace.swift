import Foundation

// MARK: - Custom MLX from HuggingFace

extension ModelManager {
    /// Validates a HuggingFace URL, fetches model size, and adds it as a custom MLX model.
    func fetchAndAddCustomMLXModel(from urlString: String) async -> Bool {
        setFetchModelError(nil)

        guard let repoID = ModelConfiguration.parseMLXRepoID(from: urlString) else {
            setFetchModelError("Please enter a valid mlx-community HuggingFace URL.")
            return false
        }

        if allModels.contains(where: { $0.hfRepoID == repoID }) {
            setFetchModelError("This model is already added.")
            return false
        }

        setIsFetchingModelInfo(true)
        defer { setIsFetchingModelInfo(false) }

        do {
            let sizeGB = try await fetchHuggingFaceModelSize(repoID: repoID)
            let config = ModelConfiguration.customMLX(repoID: repoID, sizeGB: (sizeGB * 100).rounded() / 100)
            addCustomModel(config)
            logger.info("Added custom MLX model: \(repoID, privacy: .public) (\(String(format: "%.2f", sizeGB)) GB)")
            return true
        } catch {
            setFetchModelError(error.localizedDescription)
        }
        return false
    }

    /// Fetches model file info from the HuggingFace API and returns total size in GB.
    nonisolated func fetchHuggingFaceModelSize(repoID: String) async throws -> Double {
        guard let encodedRepo = repoID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://huggingface.co/api/models/\(encodedRepo)/revision/main?blobs=true")
        else {
            throw CustomMLXError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw CustomMLXError.networkError }

        switch http.statusCode {
        case 200: break
        case 401, 403: throw CustomMLXError.privateRepo
        case 404: throw CustomMLXError.notFound
        default: throw CustomMLXError.networkError
        }

        let parsed = try JSONDecoder().decode(HFRepoResponse.self, from: data)
        let mlxFiles = parsed.siblings.filter {
            $0.rfilename.hasSuffix(".safetensors")
                || $0.rfilename.hasSuffix(".json")
                || $0.rfilename.hasSuffix(".jinja")
        }

        guard mlxFiles.contains(where: { $0.rfilename.hasSuffix(".safetensors") }) else {
            throw CustomMLXError.notMLXModel
        }

        // Verify the model has a chat template (jinja file or tokenizer_config.json)
        let allFiles = parsed.siblings
        let hasJinja = allFiles.contains { $0.rfilename == "chat_template.jinja" }
        let hasTokenizerConfig = allFiles.contains { $0.rfilename == "tokenizer_config.json" }
        guard hasJinja || hasTokenizerConfig else {
            throw CustomMLXError.noChatTemplate
        }

        let totalBytes = mlxFiles.reduce(0) { $0 + $1.size }
        return Double(totalBytes) / (1024 * 1024 * 1024)
    }

    // MARK: - Chat Template Helper

    /// Ensures `chat_template.jinja` exists in the model directory.
    /// Models downloaded before the `.jinja` glob was added will be missing it.
    /// Downloads the file from HuggingFace if absent.
    nonisolated func ensureChatTemplate(at modelDir: URL, repoID: String) async {
        let jinjaURL = modelDir.appending(component: "chat_template.jinja")
        guard !FileManager.default.fileExists(atPath: jinjaURL.path) else { return }

        guard let encodedRepo = repoID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return }
        let remoteURL = "https://huggingface.co/\(encodedRepo)/resolve/main/chat_template.jinja"
        guard let url = URL(string: remoteURL) else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            // S5: Validate downloaded template before writing
            let maxJinjaBytes = 512 * 1024 // 512 KB
            guard data.count <= maxJinjaBytes else {
                await MainActor.run { logger.warning("chat_template.jinja too large (\(data.count) bytes) — refusing to write") }
                return
            }
            guard String(data: data, encoding: .utf8) != nil else {
                await MainActor.run { logger.warning("chat_template.jinja is not valid UTF-8 — refusing to write") }
                return
            }
            try data.write(to: jinjaURL, options: .atomic)
        } catch {
            // Not critical — tokenizer may still work if template is inline
            await MainActor.run { logger.warning("Failed to download chat_template.jinja: \(error.localizedDescription, privacy: .public)") }
        }
    }
}

// MARK: - HuggingFace API Types (implementation detail — do not depend on from outside)

private struct HFRepoResponse: Decodable {
    let siblings: [HFSibling]
}

private struct HFSibling: Decodable {
    let rfilename: String
    let size: Int
}

enum CustomMLXError: LocalizedError {
    case invalidURL
    case notFound
    case privateRepo
    case notMLXModel
    case noChatTemplate
    case networkError

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid HuggingFace URL."
        case .notFound: "Repository not found. Check the URL and try again."
        case .privateRepo: "This repository is private and cannot be accessed."
        case .notMLXModel: "This repository doesn't appear to contain an MLX model."
        case .noChatTemplate: "This model has no chat template — it may be a base model, not an instruct model."
        case .networkError: "Network error. Please check your internet connection."
        }
    }
}
