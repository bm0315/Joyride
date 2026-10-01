# BYOK Generation Design

## Goal

Let users bring OpenAI, Google, or Anthropic credentials while keeping reference-image capability honest. The platform supplies the scene prompt matrix; model usage is billed to the user's provider account.

## Provider model

`ModelProvider` has three values: `openai`, `google`, and `anthropic`. Each provider has its own Keychain item, display metadata, model whitelist, and capability flags.

- OpenAI: reference-image pack generation is enabled for certified image models.
- Google: reference-image pack generation is enabled for certified Gemini image models.
- Anthropic: credentials can be stored for future prompt and orchestration features, but pack rendering is disabled because Claude does not currently produce image output.

The UI must explain unsupported capability rather than silently routing Anthropic requests to another provider.

## Certified model registry

Certification is provider-scoped. The initial registry includes the existing certified OpenAI image models plus:

- `gemini-3.1-flash-image`
- `gemini-3-pro-image`

Unknown models may be used only when an explicit development path permits them; their generated packs are marked uncertified and cannot enter recommendations.

## Generation contract

Image generators conform to one provider-neutral interface. Inputs are:

- provider and model
- source photo
- selected tier
- the canonical prompt for each selected state
- the portrait-rights confirmation

Generation produces one eight-state tier at a time. Every request includes the same source reference image. The resulting manifest records provider, model, prompt version, certification, state tiers, anchor path, and SHA-256 anchor hash.

Google generation uses the Gemini Interactions API with an image input and an image response. OpenAI uses the Images edit flow. Responses are runtime-validated; keys and raw provider responses are never logged.

## Failure behavior

- Missing credentials, unsupported provider capability, non-HTTPS endpoints, malformed responses, and invalid image data are explicit errors.
- Authentication and invalid-request failures are not retried.
- Provider-side transient failures may use a small bounded retry only when the request is safe to repeat.
- A partially generated pack is never imported.

## Acceptance criteria

- Three provider keys can be independently saved, replaced, and deleted.
- OpenAI and Google can be selected for generation.
- Anthropic shows an explicit no-image-generation explanation.
- The model menu changes with the provider.
- Every generated manifest has a stable anchor hash and correct state tiers.
- The prompt matrix contains all 24 canonical states.
