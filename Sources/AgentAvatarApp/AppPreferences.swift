import AgentAvatarCore
import Foundation

struct PrivacyConfiguration: Codable, Equatable, Sendable {
    let privacyMode: Bool
    let keywordBlacklist: [String]

    enum CodingKeys: String, CodingKey {
        case privacyMode = "privacy_mode"
        case keywordBlacklist = "keyword_blacklist"
    }
}

@MainActor
final class AppPreferences {
    private let defaults: UserDefaults

    convenience init() {
        self.init(defaults: .standard)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var privacyMode: Bool {
        get { defaults.bool(forKey: "privacyMode") }
        set { defaults.set(newValue, forKey: "privacyMode") }
    }

    var keywordBlacklist: [String] {
        get {
            defaults.stringArray(forKey: "keywordBlacklist") ?? []
        }
        set {
            let normalized = Array(Set(newValue.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }.filter { !$0.isEmpty })).sorted()
            defaults.set(normalized, forKey: "keywordBlacklist")
        }
    }

    var generationModel: String {
        get { defaults.string(forKey: "generationModel") ?? CertifiedModelRegistry.recommendedOpenAIModels[0] }
        set { defaults.set(newValue, forKey: "generationModel") }
    }

    var privacyConfiguration: PrivacyConfiguration {
        PrivacyConfiguration(privacyMode: privacyMode, keywordBlacklist: keywordBlacklist)
    }
}
