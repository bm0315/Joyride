import Foundation

public enum AvatarStateID: String, Codable, CaseIterable, Sendable {
    case working
    case checkingFlights = "checking_flights"
    case shopping
    case staringAtOwner = "staring_at_owner"
    case thinking
    case researching
    case resting
    case daydreamingHearts = "daydreaming_hearts"

    public var fileName: String {
        switch self {
        case .working: "state-01-working.webp"
        case .checkingFlights: "state-02-checking-flights.webp"
        case .shopping: "state-03-shopping.webp"
        case .staringAtOwner: "state-04-staring-at-owner.webp"
        case .thinking: "state-05-thinking.webp"
        case .researching: "state-06-researching.webp"
        case .resting: "state-07-resting.webp"
        case .daydreamingHearts: "state-08-daydreaming-hearts.webp"
        }
    }

    public var displayName: String {
        switch self {
        case .working: "Working"
        case .checkingFlights: "Checking flights"
        case .shopping: "Shopping"
        case .staringAtOwner: "Watching you"
        case .thinking: "Thinking"
        case .researching: "Researching"
        case .resting: "Resting"
        case .daydreamingHearts: "Daydreaming"
        }
    }

    public var priority: Int {
        switch self {
        case .checkingFlights, .shopping, .researching: 4
        case .working, .thinking: 3
        case .staringAtOwner, .daydreamingHearts: 2
        case .resting: 1
        }
    }

    public var isWorkState: Bool {
        switch self {
        case .working, .checkingFlights, .shopping, .thinking, .researching: true
        case .staringAtOwner, .resting, .daydreamingHearts: false
        }
    }
}

public enum AgentEventKind: String, Codable, Sendable {
    case runStarted = "run_started"
    case modelStarted = "model_started"
    case modelFinished = "model_finished"
    case toolStarted = "tool_started"
    case toolFinished = "tool_finished"
    case runFinished = "run_finished"
    case idle
}

public struct AgentEvent: Codable, Equatable, Sendable {
    public let protocolVersion: String?
    public let source: String
    public let kind: AgentEventKind
    public let activityID: String?
    public let operationID: String?
    public let tool: String?
    public let stateHint: AvatarStateID?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol"
        case source
        case kind
        case activityID = "activity_id"
        case operationID = "operation_id"
        case tool
        case stateHint = "state_hint"
    }

    public init(
        protocolVersion: String?,
        source: String,
        kind: AgentEventKind,
        activityID: String?,
        operationID: String?,
        tool: String?,
        stateHint: AvatarStateID?
    ) {
        self.protocolVersion = protocolVersion
        self.source = source
        self.kind = kind
        self.activityID = activityID
        self.operationID = operationID
        self.tool = tool
        self.stateHint = stateHint
    }

    public func validated() throws -> AgentEvent {
        if let protocolVersion, protocolVersion != "agent-avatar/1" {
            throw AgentEventValidationError.unsupportedProtocol(protocolVersion)
        }
        guard Self.isValidIdentifier(source, maximumLength: 64) else {
            throw AgentEventValidationError.invalidField("source")
        }
        if let activityID, !Self.isValidIdentifier(activityID, maximumLength: 160) {
            throw AgentEventValidationError.invalidField("activity_id")
        }
        if let operationID, !Self.isValidIdentifier(operationID, maximumLength: 160) {
            throw AgentEventValidationError.invalidField("operation_id")
        }
        if let tool, tool.isEmpty || tool.count > 256 {
            throw AgentEventValidationError.invalidField("tool")
        }
        if kind == .toolStarted || kind == .toolFinished {
            guard let tool, !tool.isEmpty else {
                throw AgentEventValidationError.missingField("tool")
            }
        }
        return self
    }

    private static func isValidIdentifier(_ value: String, maximumLength: Int) -> Bool {
        guard !value.isEmpty, value.count <= maximumLength else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x21 && scalar.value <= 0x7E
        }
    }
}

public enum AgentEventValidationError: LocalizedError, Equatable {
    case unsupportedProtocol(String)
    case invalidField(String)
    case missingField(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedProtocol(value): "Unsupported protocol: \(value)"
        case let .invalidField(field): "Invalid field: \(field)"
        case let .missingField(field): "Missing field: \(field)"
        }
    }
}
