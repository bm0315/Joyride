import Foundation
import JoyrideCore

final class RuntimeConfigurationStore: @unchecked Sendable {
    private let lock = NSLock()
    private var value: PrivacyConfiguration

    init(_ value: PrivacyConfiguration) {
        self.value = value
    }

    func update(_ value: PrivacyConfiguration) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func snapshot() -> PrivacyConfiguration {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

final class RuntimeMetricsStore: @unchecked Sendable {
    private let lock = NSLock()
    private var lastReceivedAt: TimeInterval?
    private var lastPresentedAt: TimeInterval?
    private var lastLatencyMilliseconds: Double?
    private var state = "resting"
    private var activeCount = 0

    func eventReceived(at date: Date) {
        lock.lock()
        lastReceivedAt = date.timeIntervalSince1970
        lock.unlock()
    }

    func stateSelected(_ state: String, activeCount: Int) {
        lock.lock()
        self.state = state
        self.activeCount = activeCount
        lock.unlock()
    }

    func rendered(receivedAt: TimeInterval, presentedAt: Date) {
        lock.lock()
        lastPresentedAt = presentedAt.timeIntervalSince1970
        lastLatencyMilliseconds = max(0, (presentedAt.timeIntervalSince1970 - receivedAt) * 1_000)
        lock.unlock()
    }

    func jsonObject() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        var result: [String: Any] = [
            "state": state,
            "active_count": activeCount,
            "pack_format_version": AvatarPackFormat.currentVersion,
        ]
        if let lastReceivedAt { result["last_received_at"] = lastReceivedAt }
        if let lastPresentedAt { result["last_presented_at"] = lastPresentedAt }
        if let lastLatencyMilliseconds { result["state_switch_latency_ms"] = lastLatencyMilliseconds }
        return result
    }
}
