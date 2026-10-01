import AgentAvatarCore
import Foundation

private enum CheckFailure: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message): message
        }
    }
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure.failed(message) }
}

private func event(
    source: String,
    kind: AgentEventKind,
    activityID: String?,
    operationID: String?,
    tool: String?,
    stateHint: AvatarStateID?
) -> AgentEvent {
    AgentEvent(
        protocolVersion: "agent-avatar/1",
        source: source,
        kind: kind,
        activityID: activityID,
        operationID: operationID,
        tool: tool,
        stateHint: stateHint
    )
}

@main
enum CoreChecks {
    static func main() throws {
        try lifecycleCheck()
        try concurrentPriorityCheck()
        try sourceIdleCheck()
        try validationCheck()
        try classifierCheck()
        try avatarPackCheck()
        print("Joyride core checks passed")
    }

    private static func lifecycleCheck() throws {
        var engine = StateEngine()
        let now = Date(timeIntervalSince1970: 100)
        try check(engine.apply(
            event(source: "test", kind: .runStarted, activityID: "run-1", operationID: nil, tool: nil, stateHint: nil),
            at: now
        ).state == .thinking, "run should start in thinking state")
        try check(engine.apply(
            event(source: "test", kind: .toolStarted, activityID: "run-1", operationID: "tool-1", tool: "web_search", stateHint: nil),
            at: now.addingTimeInterval(1)
        ).state == .researching, "web search should map to researching")
        try check(engine.apply(
            event(source: "test", kind: .toolFinished, activityID: "run-1", operationID: "tool-1", tool: "web_search", stateHint: nil),
            at: now.addingTimeInterval(2)
        ).state == .thinking, "tool completion should return to thinking")
        try check(engine.apply(
            event(source: "test", kind: .runFinished, activityID: "run-1", operationID: nil, tool: nil, stateHint: nil),
            at: now.addingTimeInterval(3)
        ).state == nil, "run completion should clear activity")
    }

    private static func concurrentPriorityCheck() throws {
        var engine = StateEngine()
        let now = Date(timeIntervalSince1970: 100)
        _ = engine.apply(
            event(source: "hermes", kind: .toolStarted, activityID: "run-1", operationID: "tool-1", tool: "terminal", stateHint: nil),
            at: now
        )
        let snapshot = engine.apply(
            event(source: "openclaw", kind: .toolStarted, activityID: "run-2", operationID: "tool-2", tool: "private", stateHint: .checkingFlights),
            at: now.addingTimeInterval(1)
        )
        try check(snapshot.state == .checkingFlights, "specific task state should win arbitration")
        try check(snapshot.source == "openclaw", "winning state should preserve its source")
        try check(snapshot.activeCount == 2, "concurrent activities should be counted")
        try check(snapshot.activeAgents.count == 2, "concurrent activities should be listed")
    }

    private static func sourceIdleCheck() throws {
        var engine = StateEngine()
        let now = Date(timeIntervalSince1970: 100)
        _ = engine.apply(
            event(source: "openclaw", kind: .runStarted, activityID: "run-1", operationID: nil, tool: nil, stateHint: nil),
            at: now
        )
        _ = engine.apply(
            event(source: "hermes", kind: .runStarted, activityID: "run-2", operationID: nil, tool: nil, stateHint: nil),
            at: now.addingTimeInterval(1)
        )
        let snapshot = engine.apply(
            event(source: "openclaw", kind: .idle, activityID: nil, operationID: nil, tool: nil, stateHint: nil),
            at: now.addingTimeInterval(2)
        )
        try check(snapshot.state == .thinking, "idling one source must keep other sources active")
        try check(snapshot.source == "hermes", "remaining source should be Hermes")
    }

    private static func validationCheck() throws {
        let valid = event(
            source: "test",
            kind: .toolStarted,
            activityID: "run-1",
            operationID: nil,
            tool: "browser",
            stateHint: nil
        )
        _ = try valid.validated()

        let invalid = AgentEvent(
            protocolVersion: "agent-avatar/2",
            source: "test",
            kind: .runStarted,
            activityID: nil,
            operationID: nil,
            tool: nil,
            stateHint: nil
        )
        do {
            _ = try invalid.validated()
            throw CheckFailure.failed("invalid protocol version should be rejected")
        } catch is AgentEventValidationError {
            return
        }
    }

    private static func classifierCheck() throws {
        try check(ToolClassifier.classify(toolName: "search_flights") == .checkingFlights, "flight classification failed")
        try check(ToolClassifier.classify(toolName: "shopping_cart") == .shopping, "shopping classification failed")
        try check(ToolClassifier.classify(toolName: "browser.search") == .researching, "research classification failed")
        try check(ToolClassifier.classify(toolName: "terminal") == .working, "working classification failed")
    }

    private static func avatarPackCheck() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-avatar-core-check-\(UUID().uuidString)", isDirectory: true)
        let images = root.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let anchor = Data("anchor".utf8)
        try anchor.write(to: images.appendingPathComponent("anchor.png"))
        let hash = try AvatarPackValidator.sha256Hex(of: images.appendingPathComponent("anchor.png"))
        var states: [AvatarPackManifest.State] = []
        for state in AvatarStateID.allCases {
            let path = "images/\(state.rawValue).png"
            try Data(state.rawValue.utf8).write(to: root.appendingPathComponent(path))
            states.append(AvatarPackManifest.State(
                id: state,
                triggers: ["test"],
                priority: state.priority,
                media: AvatarPackManifest.Media(path: path, type: .image),
                referenceAnchorHash: hash,
                animation: AvatarPackManifest.Animation(
                    kind: "static",
                    fallback: "programmatic_micro_motion",
                    durationMilliseconds: nil
                )
            ))
        }
        let manifest = AvatarPackManifest(
            format: AvatarPackFormat.identifier,
            formatVersion: 1,
            id: "test.pack",
            name: "Test",
            version: "1.0.0",
            character: AvatarPackManifest.Character(anchorImage: "images/anchor.png", anchorImageHash: hash),
            generator: AvatarPackManifest.Generator(
                provider: "openai",
                model: "gpt-image-2.5-sunburst",
                promptVersion: "test-v1"
            ),
            states: states
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        try encoder.encode(manifest).write(to: root.appendingPathComponent("manifest.json"))
        let validation = try AvatarPackValidator.validate(directory: root)
        try check(validation.isCertified, "whitelisted reference-image model should be certified")
        try check(validation.manifest.states.count == 8, "pack should contain all eight states")
    }
}
