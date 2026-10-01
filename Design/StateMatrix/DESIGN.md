# State Matrix Design

## Goal

Make the 24-state matrix a versioned data contract instead of a README roadmap. Every state carries a commercial tier so packs, generation, validation, and future marketplace filtering use the same source of truth.

## Canonical states

| Tier | States |
| --- | --- |
| `basic` | `working`, `thinking`, `researching`, `coding`, `finding_files`, `waiting`, `greeting`, `idle` |
| `advanced` | `checking_flights`, `booking_hotel`, `travel`, `calendar`, `shopping`, `unboxing`, `meeting`, `food_ordering` |
| `emotional` | `staring_at_owner`, `daydreaming_hearts`, `resting`, `dreaming`, `grooming`, `celebrating`, `missing_you`, `goodnight` |

The core library owns this catalog, including each state's tier, display name, work/emotional classification, priority, and fallback order.

## Pack contract

- The pack format identifier is `joyride-pack` and `format_version` is `3`.
- Every state entry requires a `tier` value.
- A declared tier must match the canonical catalog. A mismatched tier is a validation error.
- Packs may contain a subset of the 24 states, but every canonical state must resolve through the documented fallback graph.
- State paths must remain inside the pack, state IDs must be unique, and the anchor hash must match the referenced anchor image.
- Animation metadata remains optional. A static image is the fallback when animation metadata is absent.

## Fallback behavior

Fallbacks preserve semantic proximity and allow the existing eight-image default pack to run the full state engine:

- Coding and file work fall back to `working`.
- Waiting falls back to `thinking`, then `resting`.
- Greeting falls back to `staring_at_owner`, then `working`.
- Neutral idle falls back to `resting`.
- Hotel and travel work fall back to `researching` or `checking_flights`.
- Calendar and meeting work fall back to `working`.
- Unboxing and food ordering fall back to `shopping`.
- Dreaming and goodnight fall back to `resting`.
- Grooming and missing-you fall back to `staring_at_owner`.
- Celebrating falls back to `daydreaming_hearts`.

The player continues to report the requested state while rendering fallback media. This keeps state semantics observable without forcing every pack to ship 24 assets immediately.

## Acceptance criteria

- The core exposes exactly 24 canonical state IDs and three tiers.
- A v3 manifest without `tier` fails validation.
- A state with the wrong tier fails validation.
- The bundled pack validates and resolves media for all 24 states.
- Settings and generation can filter states by tier.
