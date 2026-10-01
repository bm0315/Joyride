import Foundation
import JoyrideCore

struct FeedbackConfiguration: Sendable {
    let supportEmail: String?
    let waitlistURL: URL?
    let feedbackFormURL: URL?
    let telemetryEndpoint: URL?

    static func bundled(bundle: Bundle) -> FeedbackConfiguration {
        FeedbackConfiguration(
            supportEmail: nonemptyString(bundle.object(forInfoDictionaryKey: "JoyrideSupportEmail")),
            waitlistURL: secureURL(bundle.object(forInfoDictionaryKey: "JoyrideWaitlistURL")),
            feedbackFormURL: secureURL(bundle.object(forInfoDictionaryKey: "JoyrideFeedbackFormURL")),
            telemetryEndpoint: secureURL(bundle.object(forInfoDictionaryKey: "JoyrideTelemetryEndpoint"))
        )
    }

    var supportEmailURL: URL? {
        guard let supportEmail else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [URLQueryItem(name: "subject", value: "Joyride feedback")]
        return components.url
    }

    private static func nonemptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func secureURL(_ value: Any?) -> URL? {
        guard let string = nonemptyString(value),
              let url = URL(string: string),
              url.scheme?.lowercased() == "https" else { return nil }
        return url
    }
}

enum ProductAnalyticsEvent: String, Codable, CaseIterable, Sendable {
    case appOpened = "app_opened"
    case packImported = "pack_imported"
    case packSelected = "pack_selected"
    case generationStarted = "generation_started"
    case generationSucceeded = "generation_succeeded"
    case generationFailed = "generation_failed"
    case agentConnected = "agent_connected"
    case statePresented = "state_presented"
    case feedbackOpened = "feedback_opened"
}

struct ProductAnalyticsRecord: Codable, Sendable {
    let event: ProductAnalyticsEvent
    let occurredAt: Date
    let tier: StateTier?
    let provider: ModelProvider?
    let outcome: String?

    enum CodingKeys: String, CodingKey {
        case event
        case occurredAt = "occurred_at"
        case tier
        case provider
        case outcome
    }
}

@MainActor
final class ProductAnalyticsStore {
    private let preferences: AppPreferences
    private let configuration: FeedbackConfiguration
    private let defaults: UserDefaults

    init(
        preferences: AppPreferences,
        configuration: FeedbackConfiguration,
        defaults: UserDefaults
    ) {
        self.preferences = preferences
        self.configuration = configuration
        self.defaults = defaults
    }

    func record(
        _ event: ProductAnalyticsEvent,
        tier: StateTier?,
        provider: ModelProvider?,
        outcome: String?
    ) {
        let key = "productAnalytics.count.\(event.rawValue)"
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
        defaults.set(Date(), forKey: "productAnalytics.last.\(event.rawValue)")

        guard preferences.analyticsOptIn,
              let endpoint = configuration.telemetryEndpoint else { return }
        let record = ProductAnalyticsRecord(
            event: event,
            occurredAt: Date(),
            tier: tier,
            provider: provider,
            outcome: normalizedOutcome(outcome)
        )
        Task {
            do {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.timeoutInterval = 5
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(record)
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                defaults.removeObject(forKey: "productAnalytics.lastUploadError")
            } catch {
                defaults.set(error.localizedDescription, forKey: "productAnalytics.lastUploadError")
            }
        }
    }

    private func normalizedOutcome(_ value: String?) -> String? {
        guard let value else { return nil }
        switch value {
        case "success", "failure", "cancelled": return value
        default: return "failure"
        }
    }
}
