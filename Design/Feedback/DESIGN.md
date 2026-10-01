# Feedback Channel Design

## Goal

Provide an explicit, privacy-preserving path for waitlist signups, feedback, support contact, and product metrics. The product must not advertise a 100-person threshold without a countable channel.

## Configuration

The app reads these optional deployment values from its bundle configuration:

- `JoyrideSupportEmail`
- `JoyrideWaitlistURL`
- `JoyrideFeedbackFormURL`
- `JoyrideTelemetryEndpoint`

Missing values are displayed as not configured. The app must never invent an email address or service URL.
The official build ships with `bm0315@msn.com` as its support email. Waitlist, feedback-form, and telemetry URLs remain unset until their owners provide explicit HTTPS destinations.

## User interface

Settings contains a Feedback section with:

- Join Waitlist
- Open Feedback Form
- Email Support
- Share anonymous product metrics

Buttons whose destination is not configured are disabled and labeled accordingly. The current waitlist count is shown only when a trusted waitlist service provides it; a device-local count is not presented as global interest.

## Analytics privacy contract

Analytics is opt-in and disabled by default. Only allowlisted event names may be recorded:

- `app_opened`
- `pack_imported`
- `pack_selected`
- `generation_started`
- `generation_succeeded`
- `generation_failed`
- `agent_connected`
- `state_presented`
- `feedback_opened`

Allowed properties are limited to state tier, provider, and success/failure category. Prompts, task text, tool arguments/results, filenames, raw agent IDs, API keys, and pack images are forbidden.

Events are counted locally in user defaults. Network delivery occurs only when the user opts in and an HTTPS telemetry endpoint is configured. Delivery uses bounded batches and surfaces failures without blocking the player.

## Acceptance criteria

- Feedback destinations are configurable without a code change.
- Missing destinations are visibly disabled.
- Analytics is off on first launch.
- Non-allowlisted payload fields cannot be encoded.
- No analytics request is made without both consent and a configured HTTPS endpoint.
- The UI never treats a local counter as the global 100-person waitlist count.
