import Foundation

public enum StateTier: String, Codable, CaseIterable, Sendable {
    case basic
    case advanced
    case emotional

    public var displayName: String { rawValue.capitalized }
}

public enum AvatarStateID: String, Codable, CaseIterable, Sendable {
    case working
    case thinking
    case researching
    case coding
    case findingFiles = "finding_files"
    case waiting
    case greeting
    case idle
    case checkingFlights = "checking_flights"
    case bookingHotel = "booking_hotel"
    case travel
    case calendar
    case shopping
    case unboxing
    case meeting
    case foodOrdering = "food_ordering"
    case staringAtOwner = "staring_at_owner"
    case daydreamingHearts = "daydreaming_hearts"
    case resting
    case dreaming
    case grooming
    case celebrating
    case missingYou = "missing_you"
    case goodnight

    public var tier: StateTier {
        switch self {
        case .working, .thinking, .researching, .coding, .findingFiles, .waiting, .greeting, .idle:
            .basic
        case .checkingFlights, .bookingHotel, .travel, .calendar, .shopping, .unboxing, .meeting, .foodOrdering:
            .advanced
        case .staringAtOwner, .daydreamingHearts, .resting, .dreaming, .grooming, .celebrating, .missingYou, .goodnight:
            .emotional
        }
    }

    public var displayName: String {
        switch self {
        case .working: "Working"
        case .thinking: "Thinking"
        case .researching: "Researching"
        case .coding: "Coding"
        case .findingFiles: "Finding files"
        case .waiting: "Waiting"
        case .greeting: "Greeting"
        case .idle: "Idle"
        case .checkingFlights: "Checking flights"
        case .bookingHotel: "Booking a hotel"
        case .travel: "Planning travel"
        case .calendar: "Updating calendar"
        case .shopping: "Shopping"
        case .unboxing: "Unboxing"
        case .meeting: "In a meeting"
        case .foodOrdering: "Ordering food"
        case .staringAtOwner: "Watching you"
        case .daydreamingHearts: "Daydreaming"
        case .resting: "Resting"
        case .dreaming: "Dreaming"
        case .grooming: "Grooming"
        case .celebrating: "Celebrating"
        case .missingYou: "Missing you"
        case .goodnight: "Goodnight"
        }
    }

    public var priority: Int {
        switch self {
        case .checkingFlights, .bookingHotel, .travel, .calendar, .shopping, .unboxing, .meeting, .foodOrdering:
            5
        case .researching, .coding, .findingFiles:
            4
        case .working, .thinking:
            3
        case .waiting, .greeting, .staringAtOwner, .celebrating:
            2
        case .idle, .daydreamingHearts, .resting, .dreaming, .grooming, .missingYou, .goodnight:
            1
        }
    }

    public var isWorkState: Bool {
        tier != .emotional && self != .greeting && self != .idle
    }

    public var fallbackCandidates: [AvatarStateID] {
        switch self {
        case .working: []
        case .thinking, .researching, .coding, .findingFiles: [.working]
        case .waiting: [.thinking, .resting, .working]
        case .greeting: [.staringAtOwner, .working]
        case .idle: [.resting, .working]
        case .checkingFlights: [.researching, .working]
        case .bookingHotel, .travel: [.researching, .checkingFlights, .working]
        case .calendar, .meeting, .shopping: [.working]
        case .unboxing, .foodOrdering: [.shopping, .working]
        case .staringAtOwner, .daydreamingHearts: [.resting, .working]
        case .resting: [.idle, .working]
        case .dreaming, .goodnight: [.resting, .working]
        case .grooming, .missingYou: [.staringAtOwner, .resting, .working]
        case .celebrating: [.daydreamingHearts, .staringAtOwner, .working]
        }
    }

    public var defaultTriggers: [String] {
        switch self {
        case .working: ["tool:default"]
        case .thinking: ["run_started", "model_started", "tool_finished"]
        case .researching: ["tool:web", "tool:search"]
        case .coding: ["tool:shell", "tool:code"]
        case .findingFiles: ["tool:file"]
        case .waiting: ["wait:subagent", "wait:long_task"]
        case .greeting: ["session:new"]
        case .idle: ["idle:neutral"]
        case .checkingFlights: ["tool:flight"]
        case .bookingHotel: ["tool:hotel"]
        case .travel: ["tool:travel"]
        case .calendar: ["tool:calendar"]
        case .shopping: ["tool:shopping"]
        case .unboxing: ["task:order_complete", "tool:shipping"]
        case .meeting: ["tool:meeting", "tool:email"]
        case .foodOrdering: ["tool:restaurant", "tool:delivery"]
        case .staringAtOwner: ["idle:attention", "notification:before"]
        case .daydreamingHearts: ["idle:long"]
        case .resting: ["idle:cooldown"]
        case .dreaming: ["idle:deep_night"]
        case .grooming: ["idle:grooming"]
        case .celebrating: ["task:milestone"]
        case .missingYou: ["idle:owner_away"]
        case .goodnight: ["idle:night"]
        }
    }
}

public enum AgentEventKind: String, Codable, Sendable {
    case runStarted = "run_started"
    case modelStarted = "model_started"
    case toolStarted = "tool_started"
    case toolFinished = "tool_finished"
    case runFinished = "run_finished"
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
        if let protocolVersion, protocolVersion != "joyride/1" {
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
