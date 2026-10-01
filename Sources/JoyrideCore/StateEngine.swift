import Foundation

public struct ActiveAgentSummary: Equatable, Sendable {
    public let source: String
    public let state: AvatarStateID

    public init(source: String, state: AvatarStateID) {
        self.source = source
        self.state = state
    }
}

public struct StateSnapshot: Equatable, Sendable {
    public let state: AvatarStateID?
    public let source: String?
    public let activeCount: Int
    public let activeAgents: [ActiveAgentSummary]

    public init(state: AvatarStateID?, source: String?, activeCount: Int, activeAgents: [ActiveAgentSummary]) {
        self.state = state
        self.source = source
        self.activeCount = activeCount
        self.activeAgents = activeAgents
    }
}

public struct StateEngine: Sendable {
    private struct ActiveTool: Sendable {
        let state: AvatarStateID
        let updatedAt: Date
    }

    private struct Activity: Sendable {
        var fallbackState: AvatarStateID
        var tools: [String: ActiveTool]
        var updatedAt: Date
    }

    private var activities: [String: Activity] = [:]

    public init() {}

    @discardableResult
    public mutating func apply(_ event: AgentEvent, at date: Date) -> StateSnapshot {
        let key = activityKey(for: event)

        switch event.kind {
        case .runStarted, .modelStarted:
            updateActivity(key: key, fallback: .thinking, date: date)
        case .toolStarted:
            var activity = activities[key] ?? Activity(
                fallbackState: .thinking,
                tools: [:],
                updatedAt: date
            )
            let operationKey = event.operationID ?? event.tool ?? "tool"
            let state = event.stateHint ?? ToolClassifier.classify(toolName: event.tool ?? "")
            activity.tools[operationKey] = ActiveTool(state: state, updatedAt: date)
            activity.updatedAt = date
            activities[key] = activity
        case .toolFinished:
            guard var activity = activities[key] else { break }
            let operationKey = event.operationID ?? event.tool ?? "tool"
            activity.tools.removeValue(forKey: operationKey)
            activity.fallbackState = .thinking
            activity.updatedAt = date
            activities[key] = activity
        case .runFinished:
            activities.removeValue(forKey: key)
        }

        return snapshot()
    }

    public func snapshot() -> StateSnapshot {
        let candidates = activities.map { key, activity -> (AvatarStateID, Date, String) in
            let source = String(key.prefix { $0 != ":" })
            if activity.tools.isEmpty {
                return (activity.fallbackState, activity.updatedAt, source)
            }
            let selected = activity.tools.values.max { left, right in
                if left.state.priority != right.state.priority {
                    return left.state.priority < right.state.priority
                }
                return left.updatedAt < right.updatedAt
            }!
            return (selected.state, selected.updatedAt, source)
        }

        let representatives = Dictionary(grouping: candidates, by: { $0.2 }).compactMap { source, values in
            values.max { left, right in
                if left.0.priority != right.0.priority {
                    return left.0.priority < right.0.priority
                }
                return left.1 < right.1
            }.map { ($0.0, $0.1, source) }
        }

        let selected = representatives.max { left, right in
            if left.0.priority != right.0.priority {
                return left.0.priority < right.0.priority
            }
            return left.1 < right.1
        }
        let summaries = representatives
            .map { ActiveAgentSummary(source: $0.2, state: $0.0) }
            .sorted { left, right in
                if left.state.priority != right.state.priority {
                    return left.state.priority > right.state.priority
                }
                return left.source < right.source
            }
        return StateSnapshot(
            state: selected?.0,
            source: selected?.2,
            activeCount: summaries.count,
            activeAgents: summaries
        )
    }

    private mutating func updateActivity(key: String, fallback: AvatarStateID, date: Date) {
        var activity = activities[key] ?? Activity(
            fallbackState: fallback,
            tools: [:],
            updatedAt: date
        )
        activity.fallbackState = fallback
        activity.updatedAt = date
        activities[key] = activity
    }

    private func activityKey(for event: AgentEvent) -> String {
        "\(event.source):\(event.activityID ?? "default")"
    }
}
