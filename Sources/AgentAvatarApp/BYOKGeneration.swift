import AgentAvatarCore
import Foundation
import Security

enum APIKeyStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .keychain(status): "Keychain operation failed (\(status))"
        }
    }
}

enum APIKeyStore {
    private static let service = "app.joyride.byok"
    private static let account = "openai"

    static func read() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw APIKeyStoreError.keychain(status)
        }
        return value
    }

    static func save(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if trimmed.isEmpty {
            let status = SecItemDelete(base as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw APIKeyStoreError.keychain(status)
            }
            return
        }

        let attributes: [String: Any] = [kSecValueData as String: Data(trimmed.utf8)]
        let updateStatus = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw APIKeyStoreError.keychain(updateStatus)
        }
        var insertion = base
        insertion[kSecValueData as String] = Data(trimmed.utf8)
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw APIKeyStoreError.keychain(addStatus)
        }
    }
}

enum PromptMatrix {
    static let version = "avatar-scenes-1.0.0"

    static let prompts: [AvatarStateID: String] = [
        .working: "Edit the reference character into a focused working scene at a desk. Preserve the exact character identity, face, proportions, colors, outfit design, and visual style. Square composition, clean background, no text.",
        .checkingFlights: "Edit the reference character into a flight-search scene with a small airplane and itinerary cues. Preserve the exact character identity, face, proportions, colors, outfit design, and visual style. Square composition, no text.",
        .shopping: "Edit the reference character into a playful online-shopping scene with tasteful bags and a cart. Preserve the exact character identity, face, proportions, colors, outfit design, and visual style. Square composition, no text.",
        .staringAtOwner: "Edit the reference character facing forward and warmly watching its owner. Preserve the exact character identity, face, proportions, colors, outfit design, and visual style. Square composition, no text.",
        .thinking: "Edit the reference character into a deep-thinking pose with subtle idea cues. Preserve the exact character identity, face, proportions, colors, outfit design, and visual style. Square composition, no text.",
        .researching: "Edit the reference character researching across documents and web pages. Preserve the exact character identity, face, proportions, colors, outfit design, and visual style. Square composition, no text.",
        .resting: "Edit the reference character comfortably resting in a calm scene. Preserve the exact character identity, face, proportions, colors, outfit design, and visual style. Square composition, no text.",
        .daydreamingHearts: "Edit the reference character daydreaming with small floating hearts. Preserve the exact character identity, face, proportions, colors, outfit design, and visual style. Square composition, no text.",
    ]
}

enum AvatarPackGenerationError: LocalizedError {
    case missingAPIKey
    case portraitRightsRequired
    case uncertifiedModel(String)
    case missingPrompt(String)
    case invalidResponse
    case requestFailed(Int, String, String?)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Save your OpenAI API key first"
        case .portraitRightsRequired: "Confirm that you own the photo or have permission to use it"
        case let .uncertifiedModel(model): "The model is not certified for reference-image generation: \(model)"
        case let .missingPrompt(state): "The scene matrix is missing state: \(state)"
        case .invalidResponse: "The image API returned an invalid response"
        case let .requestFailed(status, detail, requestID):
            "Image API request failed (HTTP \(status), request_id: \(requestID ?? "none")): \(detail)"
        }
    }
}

struct OpenAIAvatarPackGenerator: Sendable {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    func generate(
        name: String,
        anchorImage: URL,
        model: String,
        apiKey: String,
        portraitRightsConfirmed: Bool,
        progress: @escaping @Sendable (Int, Int, AvatarStateID) -> Void
    ) async throws -> URL {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AvatarPackGenerationError.missingAPIKey
        }
        guard portraitRightsConfirmed else {
            throw AvatarPackGenerationError.portraitRightsRequired
        }
        guard CertifiedModelRegistry.isCertified(provider: "openai", model: model) else {
            throw AvatarPackGenerationError.uncertifiedModel(model)
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("avatar-pack-\(UUID().uuidString)", isDirectory: true)
        let images = root.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let anchorExtension = normalizedImageExtension(anchorImage.pathExtension)
        let storedAnchor = images.appendingPathComponent("anchor.\(anchorExtension)")
        try FileManager.default.copyItem(at: anchorImage, to: storedAnchor)
        let anchorHash = try AvatarPackValidator.sha256Hex(of: storedAnchor)

        var states: [AvatarPackManifest.State] = []
        for (index, state) in AvatarStateID.allCases.enumerated() {
            guard let prompt = PromptMatrix.prompts[state] else {
                throw AvatarPackGenerationError.missingPrompt(state.rawValue)
            }
            progress(index, AvatarStateID.allCases.count, state)
            let data = try await editImage(
                anchorImage: storedAnchor,
                prompt: prompt,
                model: model,
                apiKey: apiKey
            )
            let path = "images/\(state.rawValue).webp"
            try data.write(to: root.appendingPathComponent(path), options: [.atomic])
            states.append(AvatarPackManifest.State(
                id: state,
                triggers: defaultTriggers(for: state),
                priority: state.priority,
                media: AvatarPackManifest.Media(path: path, type: .image),
                referenceAnchorHash: anchorHash,
                animation: AvatarPackManifest.Animation(
                    kind: "static",
                    fallback: "programmatic_micro_motion",
                    durationMilliseconds: nil
                )
            ))
        }
        progress(AvatarStateID.allCases.count, AvatarStateID.allCases.count, .working)

        let slug = UUID().uuidString.lowercased()
        let manifest = AvatarPackManifest(
            format: AvatarPackFormat.identifier,
            formatVersion: AvatarPackFormat.currentVersion,
            id: "local.generated.\(slug)",
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "My Avatar" : name,
            version: "1.0.0",
            character: AvatarPackManifest.Character(
                anchorImage: "images/anchor.\(anchorExtension)",
                anchorImageHash: anchorHash
            ),
            generator: AvatarPackManifest.Generator(
                provider: "openai",
                model: model,
                promptVersion: PromptMatrix.version
            ),
            states: states
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: root.appendingPathComponent("manifest.json"), options: [.atomic])
        _ = try AvatarPackValidator.validate(directory: root)
        return root
    }

    private func editImage(anchorImage: URL, prompt: String, model: String, apiKey: String) async throws -> Data {
        let boundary = "AgentAvatar-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/edits")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try multipartBody(
            boundary: boundary,
            model: model,
            prompt: prompt,
            imageURL: anchorImage
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AvatarPackGenerationError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data.prefix(1_024), encoding: .utf8) ?? "unknown error"
            throw AvatarPackGenerationError.requestFailed(
                http.statusCode,
                detail,
                http.value(forHTTPHeaderField: "x-request-id")
            )
        }
        let decoded = try JSONDecoder().decode(ImageResponse.self, from: data)
        guard let encoded = decoded.data.first?.b64JSON,
              let image = Data(base64Encoded: encoded) else {
            throw AvatarPackGenerationError.invalidResponse
        }
        return image
    }

    private func multipartBody(boundary: String, model: String, prompt: String, imageURL: URL) throws -> Data {
        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        appendField("model", model)
        appendField("prompt", prompt)
        appendField("size", "1024x1024")
        appendField("quality", "medium")
        appendField("output_format", "webp")
        appendField("input_fidelity", "high")
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"image[]\"; filename=\"anchor.\(normalizedImageExtension(imageURL.pathExtension))\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType(imageURL.pathExtension))\r\n\r\n".utf8))
        body.append(try Data(contentsOf: imageURL, options: [.mappedIfSafe]))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    private func defaultTriggers(for state: AvatarStateID) -> [String] {
        switch state {
        case .working: ["run_started", "model_finished", "tool:default"]
        case .checkingFlights: ["state_hint:checking_flights", "tool:flight"]
        case .shopping: ["state_hint:shopping", "tool:shopping"]
        case .thinking: ["model_started", "tool_finished"]
        case .researching: ["state_hint:researching", "tool:web", "tool:search"]
        case .staringAtOwner, .resting, .daydreamingHearts: ["idle:random"]
        }
    }

    private func normalizedImageExtension(_ value: String) -> String {
        switch value.lowercased() {
        case "jpg", "jpeg": "jpg"
        case "webp": "webp"
        default: "png"
        }
    }

    private func mimeType(_ extensionValue: String) -> String {
        switch extensionValue.lowercased() {
        case "jpg", "jpeg": "image/jpeg"
        case "webp": "image/webp"
        default: "image/png"
        }
    }
}

private struct ImageResponse: Decodable {
    let data: [Image]

    struct Image: Decodable {
        let b64JSON: String?

        enum CodingKeys: String, CodingKey {
            case b64JSON = "b64_json"
        }
    }
}
