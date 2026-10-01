# Joyride Protocol

This document defines Avatar Pack v3 and the `joyride/1` loopback event protocol. Packs are independent of agent SDKs: adapters publish privacy-minimized lifecycle events, the player arbitrates a state, and the selected pack supplies the media.

## Avatar Pack v3

### Archive layout

A distributable pack is a ZIP archive with this root layout:

```text
manifest.json
images/
  anchor.webp
  working.webp
  …
```

One enclosing top-level directory is accepted. Every resource must stay under `images/`. Absolute paths, `..` segments, and symbolic links are rejected. Archives are limited to 200 MB compressed and 500 MB expanded.

### Manifest

```json
{
  "format": "joyride-pack",
  "format_version": 3,
  "id": "com.example.blue-friend",
  "name": "Blue Friend",
  "version": "1.0.0",
  "character": {
    "anchor_image": "images/anchor.webp",
    "anchor_image_hash": "64-character-lowercase-sha256"
  },
  "generator": {
    "provider": "google",
    "model": "gemini-3.1-flash-image",
    "prompt_version": "joyride-scenes-3.0.0"
  },
  "states": [
    {
      "id": "working",
      "tier": "basic",
      "triggers": ["tool:default"],
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

- `format` is `joyride-pack`; `format_version` is integer `3`.
- `id` contains 1–80 lowercase letters, digits, dots, underscores, or hyphens.
- Every state requires `tier`. Its value must match the canonical matrix below.
- State IDs are unique. A pack may supply one or more states; the player resolves omitted states through its versioned semantic fallback graph.
- `character.anchor_image_hash` is the SHA-256 of the anchor bytes and is recomputed on import.
- Every `reference_anchor_hash` equals the character anchor hash. The official generation pipeline submits the same reference bytes for every state request.
- `generator` records provider, model, and prompt-matrix version. Certification is derived from the player registry; a pack cannot certify itself.
- `triggers` are declarative metadata. Runtime behavior is driven by events and local idle policy.

### Canonical state matrix

| Tier | State IDs |
| --- | --- |
| `basic` | `working`, `thinking`, `researching`, `coding`, `finding_files`, `waiting`, `greeting`, `idle` |
| `advanced` | `checking_flights`, `booking_hotel`, `travel`, `calendar`, `shopping`, `unboxing`, `meeting`, `food_ordering` |
| `emotional` | `staring_at_owner`, `daydreaming_hearts`, `resting`, `dreaming`, `grooming`, `celebrating`, `missing_you`, `goodnight` |

The requested state remains visible in the UI even when its media falls back. Preferred mappings include coding and file work to `working`; hotel and travel to `researching`; calendar and meeting to `working`; unboxing and food ordering to `shopping`; dreaming and goodnight to `resting`; and grooming or missing-you to `staring_at_owner`. A same-tier asset, then the first pack asset, is the final fallback for partial tier packs.

### Animation reservation

`media.type` accepts `image`, `animated_image`, or `video`. Static art uses `kind: "static"` and may request `programmatic_micro_motion`. Animated images and silent loopable video are preloaded when possible. When playback is suspended, Joyride displays a static frame without changing the protocol version.

### Model certification

Registry version `2026-10-02` certifies reference-image models by provider:

- OpenAI: `gpt-image-2.5-sunburst`, `gpt-image-2.5-flare`, `gpt-image-2`, `gpt-image-2-2026-04-21`
- Google: `gemini-3.1-flash-image`, `gemini-3-pro-image`
- Anthropic: no image-output model is certified

Uncertified packs remain importable and playable, but are excluded from marketplace recommendations.

### BYOK generation

- OpenAI, Google, and Anthropic credentials are stored as separate macOS Keychain items.
- OpenAI and Google can render packs with a shared reference image. Anthropic credentials are accepted for future orchestration, but generation is disabled because Claude does not produce image output.
- Generation creates one eight-state tier at a time and includes the same anchor in every request.
- The user must confirm portrait ownership or authorization.
- The platform supplies only the scene prompt matrix. Keys, photos, and provider usage stay between the Mac and the selected provider.

## Local event protocol: joyride/1

Joyride listens only on `127.0.0.1:18765` by default.

### Endpoints

- `GET /health`: liveness.
- `GET /v1/config`: local privacy mode and keyword blacklist for adapters.
- `GET /v1/metrics`: render latency, current state, unique active-agent count, and supported pack version.
- `POST /v1/events`: accepts one event and returns HTTP 202.

The maximum request body is 8 KiB. Unknown fields are ignored; known fields receive runtime validation.

```json
{
  "protocol": "joyride/1",
  "source": "openclaw",
  "kind": "tool_started",
  "activity_id": "opaque-run-id",
  "operation_id": "opaque-tool-id",
  "tool": "private",
  "state_hint": "researching"
}
```

### Events

| Kind | Result |
| --- | --- |
| `run_started` | Creates a run in `thinking` |
| `model_started` | Selects `thinking` |
| `tool_started` | Uses `state_hint`, otherwise classifies the tool name |
| `tool_finished` | Returns that run to `thinking` |
| `run_finished` | Removes the run |

Official adapters emit exactly one `run_started` before the first model or tool event in a run. Idle is derived by the player after no active runs remain; there is no external `idle` event. Likewise, the protocol has no `model_finished` event because current adapters cannot emit it consistently.

### Privacy contract

- Prompts, replies, tool arguments, and tool results are never sent to Joyride.
- Session and tool-call IDs are SHA-256 hashed and truncated in the agent process.
- Adapters inspect tool context locally, then send only an inferred state.
- Blacklist matches publish only neutral `working`. Private mode also forces active presentation to `working` in the player.
- Official adapters accept loopback HTTP event endpoints only.

### Concurrency

- Internal runs and tools are grouped by `source` before presentation.
- Each source contributes one highest-priority, most-recent representative state.
- The global winner is shown. The badge is `unique active agents - 1`, and the expanded list contains one row per active source.

### Emotional idle policy

Emotional states are deterministic rather than random. Daytime idle progresses from `resting` to neutral `idle`, then one attention interval of `staring_at_owner`, then `daydreaming_hearts`. Late-night idle uses `goodnight` and `dreaming`. A local pre-notification action may temporarily request `staring_at_owner`; it is not a network event.

## Feedback and telemetry

Waitlist, feedback form, support email, and telemetry destinations are deployment configuration. Missing values remain visibly unconfigured. Anonymous product metrics are opt-in and off by default. The only accepted properties are state tier, model provider, and normalized outcome; prompts, task text, tool payloads, filenames, IDs, keys, and images are forbidden. A global 100-person threshold is displayed only when a trusted waitlist service provides the count.
