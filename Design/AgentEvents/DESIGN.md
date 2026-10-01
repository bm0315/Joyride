# Agent Event Contract Design

## Goal

Keep the event protocol limited to lifecycle signals that adapters can emit consistently, and guarantee that a run begins before its model and tool activity.

## Event kinds

The v1 Joyride event contract contains:

- `run_started`
- `model_started`
- `tool_started`
- `tool_finished`
- `run_finished`

`model_finished` is removed because the current adapter APIs do not expose it consistently and it is not needed to close tool activity. `idle` is removed because idle is derived locally after all active runs finish; an external synthetic idle event would compete with the player policy.

## Adapter sequencing

Each adapter tracks active run IDs in process memory. On the first model callback for a run it emits `run_started`, then `model_started`, in that order. Further model callbacks emit only `model_started`. A terminal callback emits `run_finished` and removes the run from the active set.

If a tool callback arrives before a model callback, the adapter emits `run_started` before the tool event. This makes the contract robust to provider hook ordering.

## Privacy

Run and agent IDs are hashed in the agent process before transmission. Tool names may be classified locally, but arguments, outputs, prompts, and task text never enter the event payload.

## Loopback endpoint

The canonical default endpoint is `http://127.0.0.1:18765/v1/events`. Port 8765 is already occupied by another local service on the development Mac, so keeping it would leave the player running without an event listener. The app, official adapters, CLI examples, benchmark tool, and protocol documentation must use the same default. `JOYRIDE_PORT`, `JOYRIDE_ENDPOINT`, and the OpenClaw endpoint setting remain explicit overrides.

An upgrade notice must tell users to update the app and adapter together when moving from the former default port. The player does not bind the former port as a compatibility listener because doing so could interfere with the service that already owns it.

## Acceptance criteria

- Every adapter emits one `run_started` before any event in a run.
- Every completed run emits `run_finished` and clears adapter state.
- The protocol schema and manifest triggers contain no `model_finished` or `idle` event kinds.
- Adapter tests cover first-event ordering, repeated model calls, tool-first ordering, and completion.
- The app and official clients agree on port `18765` when no override is configured.
- The README documents the coordinated app-and-adapter upgrade requirement.
