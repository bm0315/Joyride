import Foundation
import JoyrideCore
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

    static func read(provider: ModelProvider) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
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

    static func save(_ value: String, provider: ModelProvider) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
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
    static let version = "joyride-scenes-3.0.0"

    static let prompts: [AvatarStateID: String] = [
        .working: scene("focused at a desk, wearing headphones and typing on a computer"),
        .thinking: scene("thinking deeply, chin resting on one hand, with subtle question-mark and lightbulb cues"),
        .researching: scene("researching documents with a magnifying glass and several reference pages"),
        .coding: scene("programming with a terminal and code editor visible"),
        .findingFiles: scene("sorting through clearly visible folders and changing from one file to another"),
        .waiting: scene("waiting patiently while checking a watch beside a subtle progress indicator"),
        .greeting: scene("cheerfully waving hello at the viewer"),
        .idle: scene("quietly spacing out in a neutral, relaxed pose"),
        .checkingFlights: scene("checking a flight information panel with a small airplane and itinerary cues"),
        .bookingHotel: scene("comparing hotel cards and choosing a room"),
        .travel: scene("planning a journey with a map and itinerary sheet"),
        .calendar: scene("updating a clean calendar with a new event"),
        .shopping: scene("playfully shopping online while holding tasteful shopping bags"),
        .unboxing: scene("happily opening a delivered parcel"),
        .meeting: scene("participating in a friendly video meeting"),
        .foodOrdering: scene("choosing a meal beside appealing food and a delivery bag"),
        .staringAtOwner: scene("leaning slightly toward the camera and warmly watching its owner"),
        .daydreamingHearts: scene("daydreaming while small heart bubbles float outward"),
        .resting: scene("resting comfortably with a pillow, small blanket, and subtle sleep cues"),
        .dreaming: scene("sleeping while a whimsical dream bubble floats overhead"),
        .grooming: scene("tidying its appearance in a small mirror"),
        .celebrating: scene("celebrating a completed milestone with tasteful confetti"),
        .missingYou: scene("looking out a window and quietly missing its owner"),
        .goodnight: scene("saying goodnight as the light dims beneath a calm moon"),
    ]

    private static func scene(_ action: String) -> String {
        "Edit the reference character so it is \(action). Preserve the exact identity, face, proportions, colors, outfit design, and visual style. Square composition, clean background, no text."
    }
}

enum AvatarPackGenerationError: LocalizedError {
    case missingAPIKey(ModelProvider)
    case portraitRightsRequired
    case unsupportedProvider(ModelProvider)
    case uncertifiedModel(String)
    case missingPrompt(String)
    case invalidResponse
    case requestFailed(Int, String, String?)

    var errorDescription: String? {
        switch self {
        case let .missingAPIKey(provider): "Save your \(provider.displayName) API key first"
        case .portraitRightsRequired: "Confirm that you own the photo or have permission to use it"
        case let .unsupportedProvider(provider): "\(provider.displayName) does not currently provide reference-image output for avatar pack rendering"
        case let .uncertifiedModel(model): "The model is not certified for reference-image generation: \(model)"
        case let .missingPrompt(state): "The scene matrix is missing state: \(state)"
        case .invalidResponse: "The image API returned an invalid response"
        case let .requestFailed(status, detail, requestID):
            "Image API request failed (HTTP \(status), request_id: \(requestID ?? "none")): \(detail)"
        }
    }
}

struct BYOKAvatarPackGenerator: Sendable {
    private let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    func generate(
        name: String,
        anchorImage: URL,
        provider: ModelProvider,
        model: String,
        tier: StateTier,
        apiKey: String,
        portraitRightsConfirmed: Bool,
        progress: @escaping @Sendable (Int, Int, AvatarStateID) -> Void
    ) async throws -> URL {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AvatarPackGenerationError.missingAPIKey(provider)
        }
        guard portraitRightsConfirmed else {
            throw AvatarPackGenerationError.portraitRightsRequired
        }
        guard provider.supportsReferenceImageGeneration else {
            throw AvatarPackGenerationError.unsupportedProvider(provider)
        }
        guard CertifiedModelRegistry.isCertified(provider: provider.rawValue, model: model) else {
            throw AvatarPackGenerationError.uncertifiedModel(model)
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("joyride-pack-\(UUID().uuidString)", isDirectory: true)
        let images = root.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let anchorExtension = normalizedImageExtension(anchorImage.pathExtension)
        let storedAnchor = images.appendingPathComponent("anchor.\(anchorExtension)")
        try FileManager.default.copyItem(at: anchorImage, to: storedAnchor)
        let anchorHash = try AvatarPackValidator.sha256Hex(of: storedAnchor)
        let selectedStates = AvatarStateID.allCases.filter { $0.tier == tier }

        var states: [AvatarPackManifest.State] = []
        for (index, state) in selectedStates.enumerated() {
            guard let prompt = PromptMatrix.prompts[state] else {
                throw AvatarPackGenerationError.missingPrompt(state.rawValue)
            }
            progress(index, selectedStates.count, state)
            let result = try await generateImage(
                provider: provider,
                anchorImage: storedAnchor,
                prompt: prompt,
                model: model,
                apiKey: apiKey
            )
            let path = "images/\(state.rawValue).\(result.fileExtension)"
            try result.data.write(to: root.appendingPathComponent(path), options: [.atomic])
            states.append(AvatarPackManifest.State(
                id: state,
                tier: state.tier,
                triggers: state.defaultTriggers,
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
        progress(selectedStates.count, selectedStates.count, selectedStates[0])

        let manifest = AvatarPackManifest(
            format: AvatarPackFormat.identifier,
            formatVersion: AvatarPackFormat.currentVersion,
            id: "local.generated.\(UUID().uuidString.lowercased())",
            name: normalizedPackName(name, tier: tier),
            version: "1.0.0",
            character: AvatarPackManifest.Character(
                anchorImage: "images/anchor.\(anchorExtension)",
                anchorImageHash: anchorHash
            ),
            generator: AvatarPackManifest.Generator(
                provider: provider.rawValue,
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

    private func generateImage(
        provider: ModelProvider,
        anchorImage: URL,
        prompt: String,
        model: String,
        apiKey: String
    ) async throws -> GeneratedImage {
        switch provider {
        case .openAI:
            return GeneratedImage(
                data: try await editOpenAIImage(anchorImage: anchorImage, prompt: prompt, model: model, apiKey: apiKey),
                fileExtension: "webp"
            )
        case .google:
            return GeneratedImage(
                data: try await editGoogleImage(anchorImage: anchorImage, prompt: prompt, model: model, apiKey: apiKey),
                fileExtension: "png"
            )
        case .anthropic:
            throw AvatarPackGenerationError.unsupportedProvider(.anthropic)
        }
    }

    private func editOpenAIImage(anchorImage: URL, prompt: String, model: String, apiKey: String) async throws -> Data {
        let boundary = "Joyride-\(UUID().uuidString)"
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
        let http = try validatedHTTPResponse(response, data: data)
        let decoded = try JSONDecoder().decode(OpenAIImageResponse.self, from: data)
        guard let encoded = decoded.data.first?.b64JSON,
              let image = Data(base64Encoded: encoded) else {
            throw AvatarPackGenerationError.invalidResponse
        }
        _ = http
        return image
    }

    private func editGoogleImage(anchorImage: URL, prompt: String, model: String, apiKey: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let input = GoogleInteractionRequest(
            model: model,
            input: [
                .init(role: "user", content: [
                    .init(type: "text", text: prompt, mimeType: nil, data: nil),
                    .init(
                        type: "image",
                        text: nil,
                        mimeType: mimeType(anchorImage.pathExtension),
                        data: try Data(contentsOf: anchorImage, options: [.mappedIfSafe]).base64EncodedString()
                    ),
                ]),
            ],
            responseFormat: .init(type: "image", image: .init(aspectRatio: "1:1", resolution: "1K"))
        )
        request.httpBody = try JSONEncoder().encode(input)

        let (data, response) = try await session.data(for: request)
        _ = try validatedHTTPResponse(response, data: data)
        let decoded = try JSONDecoder().decode(GoogleInteractionResponse.self, from: data)
        guard let encoded = decoded.imageData,
              let image = Data(base64Encoded: encoded) else {
            throw AvatarPackGenerationError.invalidResponse
        }
        return image
    }

    private func validatedHTTPResponse(_ response: URLResponse, data: Data) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw AvatarPackGenerationError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data.prefix(1_024), encoding: .utf8) ?? "unknown error"
            throw AvatarPackGenerationError.requestFailed(
                http.statusCode,
                detail,
                http.value(forHTTPHeaderField: "x-request-id")
                    ?? http.value(forHTTPHeaderField: "x-goog-request-id")
            )
        }
        return http
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
}

private struct GeneratedImage: Sendable {
    let data: Data
    let fileExtension: String
}

private struct OpenAIImageResponse: Decodable {
    let data: [Image]

    struct Image: Decodable {
        let b64JSON: String?

        enum CodingKeys: String, CodingKey {
            case b64JSON = "b64_json"
        }
    }
}

private struct GoogleInteractionRequest: Encodable {
    let model: String
    let input: [Input]
    let responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case responseFormat = "response_format"
    }

    struct Input: Encodable {
        let role: String
        let content: [Content]
    }

    struct Content: Encodable {
        let type: String
        let text: String?
        let mimeType: String?
        let data: String?

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case mimeType = "mime_type"
            case data
        }
    }

    struct ResponseFormat: Encodable {
        let type: String
        let image: Image

        struct Image: Encodable {
            let aspectRatio: String
            let resolution: String

            enum CodingKeys: String, CodingKey {
                case aspectRatio = "aspect_ratio"
                case resolution
            }
        }
    }
}

private struct GoogleInteractionResponse: Decodable {
    let interaction: Interaction

    var imageData: String? {
        interaction.outputImage?.data
            ?? interaction.outputs?.compactMap(\.data).first
            ?? interaction.steps?.flatMap(\.content).compactMap(\.data).first
    }

    struct Interaction: Decodable {
        let outputImage: ImagePayload?
        let outputs: [ImagePayload]?
        let steps: [Step]?

        enum CodingKeys: String, CodingKey {
            case outputImage = "output_image"
            case outputs
            case steps
        }
    }

    struct Step: Decodable {
        let content: [ImagePayload]
    }

    struct ImagePayload: Decodable {
        let data: String?
    }
}

private func normalizedPackName(_ value: String, tier: StateTier) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "My \(tier.displayName) Avatar" : trimmed
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
