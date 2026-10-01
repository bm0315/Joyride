import CryptoKit
import Foundation

public enum AvatarPackFormat {
    public static let identifier = "agent-avatar-pack"
    public static let currentVersion = 1
    public static let requiredStates = Set(AvatarStateID.allCases)
}

public struct AvatarPackManifest: Codable, Equatable, Sendable {
    public let format: String
    public let formatVersion: Int
    public let id: String
    public let name: String
    public let version: String
    public let character: Character
    public let generator: Generator
    public let states: [State]

    public init(
        format: String,
        formatVersion: Int,
        id: String,
        name: String,
        version: String,
        character: Character,
        generator: Generator,
        states: [State]
    ) {
        self.format = format
        self.formatVersion = formatVersion
        self.id = id
        self.name = name
        self.version = version
        self.character = character
        self.generator = generator
        self.states = states
    }

    enum CodingKeys: String, CodingKey {
        case format
        case formatVersion = "format_version"
        case id
        case name
        case version
        case character
        case generator
        case states
    }

    public struct Character: Codable, Equatable, Sendable {
        public let anchorImage: String
        public let anchorImageHash: String

        enum CodingKeys: String, CodingKey {
            case anchorImage = "anchor_image"
            case anchorImageHash = "anchor_image_hash"
        }

        public init(anchorImage: String, anchorImageHash: String) {
            self.anchorImage = anchorImage
            self.anchorImageHash = anchorImageHash
        }
    }

    public struct Generator: Codable, Equatable, Sendable {
        public let provider: String
        public let model: String
        public let promptVersion: String

        enum CodingKeys: String, CodingKey {
            case provider
            case model
            case promptVersion = "prompt_version"
        }

        public init(provider: String, model: String, promptVersion: String) {
            self.provider = provider
            self.model = model
            self.promptVersion = promptVersion
        }
    }

    public struct State: Codable, Equatable, Sendable {
        public let id: AvatarStateID
        public let triggers: [String]
        public let priority: Int
        public let media: Media
        public let referenceAnchorHash: String
        public let animation: Animation?

        enum CodingKeys: String, CodingKey {
            case id
            case triggers
            case priority
            case media
            case referenceAnchorHash = "reference_anchor_hash"
            case animation
        }

        public init(
            id: AvatarStateID,
            triggers: [String],
            priority: Int,
            media: Media,
            referenceAnchorHash: String,
            animation: Animation?
        ) {
            self.id = id
            self.triggers = triggers
            self.priority = priority
            self.media = media
            self.referenceAnchorHash = referenceAnchorHash
            self.animation = animation
        }
    }

    public struct Media: Codable, Equatable, Sendable {
        public let path: String
        public let type: MediaType

        public init(path: String, type: MediaType) {
            self.path = path
            self.type = type
        }
    }

    public enum MediaType: String, Codable, Sendable {
        case image
        case animatedImage = "animated_image"
        case video
    }

    public struct Animation: Codable, Equatable, Sendable {
        public let kind: String
        public let fallback: String?
        public let durationMilliseconds: Int?

        enum CodingKeys: String, CodingKey {
            case kind
            case fallback
            case durationMilliseconds = "duration_ms"
        }

        public init(kind: String, fallback: String?, durationMilliseconds: Int?) {
            self.kind = kind
            self.fallback = fallback
            self.durationMilliseconds = durationMilliseconds
        }
    }
}

public struct AvatarPackValidation: Equatable, Sendable {
    public let manifest: AvatarPackManifest
    public let isCertified: Bool
    public let certificationReason: String

    public init(manifest: AvatarPackManifest, isCertified: Bool, certificationReason: String) {
        self.manifest = manifest
        self.isCertified = isCertified
        self.certificationReason = certificationReason
    }
}

public enum CertifiedModelRegistry {
    public static let version = "2026-10-01"

    private static let openAIModels: Set<String> = [
        "gpt-image-2.5-sunburst",
        "gpt-image-2.5-flare",
        "gpt-image-2",
        "gpt-image-2-2026-04-21",
    ]

    public static func isCertified(provider: String, model: String) -> Bool {
        provider.lowercased() == "openai" && openAIModels.contains(model)
    }

    public static var recommendedOpenAIModels: [String] {
        ["gpt-image-2.5-sunburst", "gpt-image-2.5-flare"]
    }
}

public enum AvatarPackValidationError: LocalizedError, Equatable {
    case missingManifest
    case malformedManifest(String)
    case unsupportedFormat(String)
    case unsupportedVersion(Int)
    case invalidIdentifier
    case incompleteStates
    case duplicateState(String)
    case invalidPriority(String)
    case unsafePath(String)
    case missingFile(String)
    case anchorHashMismatch
    case inconsistentAnchor(String)

    public var errorDescription: String? {
        switch self {
        case .missingManifest: "The avatar pack is missing manifest.json"
        case let .malformedManifest(detail): "Invalid manifest.json: \(detail)"
        case let .unsupportedFormat(value): "Unsupported avatar pack format: \(value)"
        case let .unsupportedVersion(value): "Unsupported avatar pack version v\(value); this client supports v\(AvatarPackFormat.currentVersion)"
        case .invalidIdentifier: "The pack id must contain 1–80 lowercase letters, digits, dots, underscores, or hyphens"
        case .incompleteStates: "A v1 pack must contain exactly all eight standard states"
        case let .duplicateState(value): "Duplicate state: \(value)"
        case let .invalidPriority(value): "Invalid state priority: \(value)"
        case let .unsafePath(value): "Unsafe resource path: \(value)"
        case let .missingFile(value): "Missing resource file: \(value)"
        case .anchorHashMismatch: "The anchor image SHA-256 does not match the manifest"
        case let .inconsistentAnchor(value): "State \(value) is not bound to the shared character anchor"
        }
    }
}

public enum AvatarPackValidator {
    public static func validate(directory: URL) throws -> AvatarPackValidation {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw AvatarPackValidationError.missingManifest
        }

        let manifest: AvatarPackManifest
        do {
            let data = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
            manifest = try JSONDecoder().decode(AvatarPackManifest.self, from: data)
        } catch let error as AvatarPackValidationError {
            throw error
        } catch {
            throw AvatarPackValidationError.malformedManifest(error.localizedDescription)
        }

        guard manifest.format == AvatarPackFormat.identifier else {
            throw AvatarPackValidationError.unsupportedFormat(manifest.format)
        }
        guard manifest.formatVersion == AvatarPackFormat.currentVersion else {
            throw AvatarPackValidationError.unsupportedVersion(manifest.formatVersion)
        }
        guard isValidIdentifier(manifest.id) else {
            throw AvatarPackValidationError.invalidIdentifier
        }

        let stateIDs = manifest.states.map(\.id)
        guard Set(stateIDs) == AvatarPackFormat.requiredStates,
              stateIDs.count == AvatarPackFormat.requiredStates.count else {
            if let duplicate = Dictionary(grouping: stateIDs, by: { $0 }).first(where: { $0.value.count > 1 })?.key {
                throw AvatarPackValidationError.duplicateState(duplicate.rawValue)
            }
            throw AvatarPackValidationError.incompleteStates
        }

        let anchorURL = try resolvedResource(manifest.character.anchorImage, in: directory)
        guard FileManager.default.fileExists(atPath: anchorURL.path) else {
            throw AvatarPackValidationError.missingFile(manifest.character.anchorImage)
        }
        let actualHash = try sha256Hex(of: anchorURL)
        guard actualHash == manifest.character.anchorImageHash.lowercased() else {
            throw AvatarPackValidationError.anchorHashMismatch
        }

        for state in manifest.states {
            guard state.priority >= 0 && state.priority <= 100 else {
                throw AvatarPackValidationError.invalidPriority(state.id.rawValue)
            }
            guard state.referenceAnchorHash.lowercased() == actualHash else {
                throw AvatarPackValidationError.inconsistentAnchor(state.id.rawValue)
            }
            let resourceURL = try resolvedResource(state.media.path, in: directory)
            guard FileManager.default.fileExists(atPath: resourceURL.path) else {
                throw AvatarPackValidationError.missingFile(state.media.path)
            }
        }

        let certified = CertifiedModelRegistry.isCertified(
            provider: manifest.generator.provider,
            model: manifest.generator.model
        )
        return AvatarPackValidation(
            manifest: manifest,
            isCertified: certified,
            certificationReason: certified
                ? "Reference-image model certified by registry \(CertifiedModelRegistry.version)"
                : "The generator model is not in the reference-image whitelist"
        )
    }

    public static func sha256Hex(of fileURL: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: fileURL, options: [.mappedIfSafe]))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func resolvedResource(_ relativePath: String, in directory: URL) throws -> URL {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        guard normalized.hasPrefix("images/"),
              !normalized.hasPrefix("/"),
              !normalized.split(separator: "/").contains("..") else {
            throw AvatarPackValidationError.unsafePath(relativePath)
        }
        let root = directory.standardizedFileURL
        let resolved = directory.appendingPathComponent(normalized).standardizedFileURL
        guard resolved.path.hasPrefix(root.path + "/") else {
            throw AvatarPackValidationError.unsafePath(relativePath)
        }
        return resolved
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 80 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 97 && scalar.value <= 122)
                || (scalar.value >= 48 && scalar.value <= 57)
                || scalar.value == 46 || scalar.value == 95 || scalar.value == 45
        }
    }
}
