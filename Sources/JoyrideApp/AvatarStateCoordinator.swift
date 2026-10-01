import JoyrideCore
import Foundation

@MainActor
final class AvatarStateCoordinator {
    typealias PresentationHandler = (AvatarStateID, String, Int, [ActiveAgentSummary], Date) -> Void

    private let minimumDwell: TimeInterval = 5
    private let onPresentation: PresentationHandler
    private var engine = StateEngine()
    private var currentState: AvatarStateID = .resting
    private var currentSource = "Idle"
    private var currentAdditionalCount = 0
    private var currentAgents: [ActiveAgentSummary] = []
    private var privacyMode = false
    private var lastTransition = Date.distantPast
    private var idleBeganAt: Date?
    private var attentionOverrideUntil: Date?
    private var timer: Timer?

    init(onPresentation: @escaping PresentationHandler) {
        self.onPresentation = onPresentation
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reconcile(at: Date())
            }
        }
    }

    func start() {
        lastTransition = Date()
        onPresentation(currentState, currentSource, 0, [], lastTransition)
    }

    func receive(_ event: AgentEvent, at date: Date) {
        _ = engine.apply(event, at: date)
        reconcile(at: date)
    }

    func preview(_ state: AvatarStateID) {
        transition(to: state, source: "Preview", additionalCount: 0, agents: [], at: Date(), force: true)
    }

    func setPrivacyMode(_ enabled: Bool) {
        privacyMode = enabled
        reconcile(at: Date())
    }

    func prepareForNotification(at date: Date) {
        attentionOverrideUntil = date.addingTimeInterval(8)
        reconcile(at: date)
    }

    private func reconcile(at date: Date) {
        let snapshot = engine.snapshot()
        if let desired = snapshot.state {
            idleBeganAt = nil
            attentionOverrideUntil = nil
            let source = snapshot.source.map(sourceDisplayName) ?? "Agent"
            let visibleState: AvatarStateID = privacyMode ? .working : desired
            let visibleAgents = privacyMode
                ? snapshot.activeAgents.map { ActiveAgentSummary(source: $0.source, state: .working) }
                : snapshot.activeAgents
            transition(
                to: visibleState,
                source: privacyMode ? "Private mode" : source,
                additionalCount: max(0, snapshot.activeCount - 1),
                agents: visibleAgents,
                at: date,
                force: privacyMode || shouldPreempt(with: visibleState)
            )
            return
        }

        if idleBeganAt == nil {
            idleBeganAt = date
        }
        let idleDuration = date.timeIntervalSince(idleBeganAt ?? date)
        let hour = Calendar.current.component(.hour, from: date)
        let desired: AvatarStateID
        if let overrideUntil = attentionOverrideUntil, date < overrideUntil {
            desired = .staringAtOwner
        } else {
            attentionOverrideUntil = nil
            desired = IdleStatePolicy.state(idleDuration: idleDuration, localHour: hour)
        }
        transition(
            to: desired,
            source: "Idle",
            additionalCount: 0,
            agents: [],
            at: date,
            force: currentState.isWorkState || attentionOverrideUntil != nil
        )
    }

    private func shouldPreempt(with desired: AvatarStateID) -> Bool {
        desired.isWorkState && (!currentState.isWorkState || desired.priority > currentState.priority)
    }

    private func transition(
        to state: AvatarStateID,
        source: String,
        additionalCount: Int,
        agents: [ActiveAgentSummary],
        at date: Date,
        force: Bool
    ) {
        if state == currentState {
            if source != currentSource || additionalCount != currentAdditionalCount || agents != currentAgents {
                currentSource = source
                currentAdditionalCount = additionalCount
                currentAgents = agents
                onPresentation(currentState, currentSource, additionalCount, agents, date)
            }
            return
        }
        guard force || date.timeIntervalSince(lastTransition) >= minimumDwell else { return }

        currentState = state
        currentSource = source
        currentAdditionalCount = additionalCount
        currentAgents = agents
        lastTransition = date
        onPresentation(state, source, additionalCount, agents, date)
    }

    private func sourceDisplayName(_ value: String) -> String {
        switch value.lowercased() {
        case "openclaw": "OpenClaw"
        case "hermes": "Hermes"
        case "codex": "Codex"
        case "claude-code": "Claude Code"
        default: value
        }
    }
}
