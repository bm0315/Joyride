# Joyride Protocol

This document defines both **Avatar Pack v1**, the downloadable product format, and `agent-avatar/1`,
the local event protocol between agents and the Joyride player. Pack assets are independent of agent
SDKs: adapters publish state, while the player selects media from the active pack.

## Avatar Pack v1

### Archive layout

A distributable pack is a ZIP archive with a manifest and an image directory at its root:

```text
manifest.json
images/
  anchor.webp
  working.webp
  thinking.webp
  …
```

Joyride also accepts one enclosing top-level directory. Every resource path must remain under `images/`.
Absolute paths, `..` segments, and symbolic links are rejected. The client limits archives to 200 MB and
expanded packs to 500 MB.

### manifest.json

```json
{
  "format": "agent-avatar-pack",
  "format_version": 1,
  "id": "com.example.blue-friend",
  "name": "Blue Friend",
  "version": "1.0.0",
  "character": {
    "anchor_image": "images/anchor.webp",
    "anchor_image_hash": "64-character-lowercase-sha256"
  },
  "generator": {
    "provider": "openai",
    "model": "gpt-image-2.5-sunburst",
    "prompt_version": "avatar-scenes-1.0.0"
  },
  "states": [
    {
      "id": "working",
      "triggers": ["run_started", "tool:default"],
      "priority": 3,
      "media": {"path": "images/working.webp", "type": "image"},
      "reference_anchor_hash": "same-sha256-as-character",
      "animation": {
        "kind": "static",
        "fallback": "programmatic_micro_motion",
        "duration_ms": null
      }
    }
  ]
}
```

Rules:

- `format` is exactly `agent-avatar-pack`. The current `format_version` is integer `1`. Newer versions
  are rejected explicitly instead of being silently downgraded.
- `id` is a stable product identifier containing 1–80 lowercase letters, digits, dots, underscores, or
  hyphens.
- `character.anchor_image_hash` is the SHA-256 digest of the anchor file. Joyride recomputes it on import.
- A v1 pack contains exactly one copy of all eight standard states.
- Every state's `reference_anchor_hash` equals the character anchor hash. The official generation
  pipeline uploads the same anchor file for every generation call, making its consistency source
  auditable. For a third-party finished pack, the client can verify the declared binding but cannot infer
  from output pixels whether a remote generator honestly used the reference.
- `generator` records the provider, model, and platform scene-prompt matrix version. Certification is
  derived from a local client whitelist. A package cannot certify itself.
- `triggers` are declarative marketplace metadata. Runtime arbitration remains event-driven.

### Standard states

| `id` | Suggested trigger | Default priority |
| --- | --- | ---: |
| `working` | General tool execution or private mode | 3 |
| `checking_flights` | Flight search or booking | 4 |
| `shopping` | Product comparison, cart, or purchase | 4 |
| `staring_at_owner` | Random idle scene | 2 |
| `thinking` | Model call, planning, or post-tool reasoning | 3 |
| `researching` | Search, browsing, or document reading | 4 |
| `resting` | Random idle scene | 1 |
| `daydreaming_hearts` | Random idle scene | 2 |

### Animation reservation

`media.type` accepts `image`, `animated_image`, or `video`. The optional `animation` object follows these
rules:

- Static art should use `kind: "static"` and `fallback: "programmatic_micro_motion"`.
- Animated image packages use `animated_image`; short videos use `video` and should be silent and loopable.
- When animation is unsupported or suspended for power saving, the player displays a static first frame
  or programmatic micro-motion without changing the protocol version.

### Model certification

The certification whitelist contains only models confirmed to support reference-image editing and used by
a pipeline that actually reuses the anchor. Registry version `2026-10-01` contains:

- OpenAI: `gpt-image-2.5-sunburst`, `gpt-image-2.5-flare`, `gpt-image-2`, and
  `gpt-image-2-2026-04-21`.

Packs made by other models can still be imported and played. They are labeled **Uncertified** and cannot
enter marketplace recommendations. The local, versioned client registry cannot be overridden by a pack.

### BYOK generation rules

- The API key stays in the user's macOS Keychain. Joyride sends images directly to the selected service,
  and usage is billed to that key.
- The platform distributes only a versioned scene-prompt matrix; it does not receive the key or photo.
- All eight state requests upload the same anchor bytes and write the same SHA-256 into every state.
- The user must confirm ownership or authorization before generation from a photo.
- Platform-funded generation is reserved but not implemented in v1. A missing key never causes an
  implicit upload or paid fallback.

## Local event protocol: agent-avatar/1

Joyride listens only on `127.0.0.1:8765` and does not accept remote connections.

### Endpoints

- `GET /health`: liveness check.
- `GET /v1/config`: exposes `privacy_mode` and `keyword_blacklist` to local adapters.
- `GET /v1/metrics`: returns the latest render latency, current state, concurrent activity count, and
  supported pack version.
- `POST /v1/events`: submits one lifecycle event and returns HTTP 202 on acceptance.

The maximum request body is 8 KiB. Unknown fields are ignored and required fields receive runtime
validation.

```json
{
  "protocol": "agent-avatar/1",
  "source": "openclaw",
  "kind": "tool_started",
  "activity_id": "opaque-run-id",
  "operation_id": "opaque-tool-id",
  "tool": "private",
  "state_hint": "researching"
}
```

### Events and state mapping

| `kind` | Default result |
| --- | --- |
| `run_started` | `thinking` |
| `model_started` | `thinking` |
| `model_finished` | `working` |
| `tool_started` | Uses `state_hint`, otherwise classifies the tool name |
| `tool_finished` | Returns to `thinking` |
| `run_finished` | Clears the activity |
| `idle` | Clears all activities from that `source` |

`state_hint` accepts all eight standard states. Official OpenClaw and Hermes adapters publish work states.
When no work remains, the player chooses among the three idle states every 20–38 seconds.

### Privacy contract

- Prompts, replies, tool arguments, and tool results are never sent to Joyride.
- Task, session, and tool-call identifiers are SHA-256 hashed and truncated to 24 opaque characters.
- An adapter temporarily examines tool names and arguments inside the agent process, then sends only the
  inferred state.
- Adapters refresh local privacy configuration within five seconds. A blacklist match sends only
  `working`.
- Private mode also forces every active state to `working` inside the player, protecting users of older
  adapters.
- Official adapters accept only loopback HTTP endpoints.

### Concurrent arbitration

- Joyride displays one winner. Higher priority wins; the most recently updated candidate breaks ties.
- Work states remain visible for at least five seconds to prevent rapid tool calls from flickering.
- A `+N` badge shows hidden concurrent agents and expands into their current states.
