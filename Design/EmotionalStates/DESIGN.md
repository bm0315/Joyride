# Emotional State Policy Design

## Goal

Preserve the authored meaning of emotional states. `staring_at_owner` represents a deliberate attention cue, not a random idle frame.

## Deterministic idle policy

When the last active agent finishes, the app records an idle epoch. A pure time-based policy selects the state:

- Initial cooldown: `resting`
- Neutral idle: `idle`
- Attention-seeking interval: `staring_at_owner`
- Long idle: `daydreaming_hearts`
- Late-night long idle: `goodnight`, with `dreaming` as the deeper-sleep stage

The policy is deterministic for a given idle duration and local hour. It does not randomly rotate emotional states. Pack fallback media handles missing emotional assets without changing the requested state.

## Attention hook

The coordinator exposes a local pre-notification action that temporarily requests `staring_at_owner`. It is not an agent event and is not added to the network protocol until a real notification caller exists.

Starting any work activity cancels the idle epoch and any attention override. Finishing work starts a new idle epoch.

## Acceptance criteria

- Generic idle rotation never selects `staring_at_owner` at random.
- The idle policy is unit-testable with injected duration and hour values.
- Work immediately overrides emotional states.
- A local pre-notification request selects `staring_at_owner` and expires predictably.
- Late-night states are selected only during configured local night hours.
