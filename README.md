# Joyride

*From "I'm busy" to "here's what I'm doing" — 24 living states, downloadable skins, zero task data leaves your Mac.*

Joyride turns an agent's real work into a living desktop character. It reads privacy-minimized lifecycle
events from supported agents, chooses the winning state when several agents are active, and plays the
matching scene from a replaceable avatar pack. When work stops, the character rests, daydreams, or looks
back at its owner.

<p align="center">
  <img src="Assets/previews/working-typing-v3.gif" width="31%" alt="Joyride agent typing on a keyboard">
  <img src="Assets/previews/researching-files-v3.gif" width="31%" alt="Joyride agent switching between research files">
  <img src="Assets/previews/daydreaming-heart-burst-v3.gif" width="31%" alt="Joyride agent surrounded by outward-floating hearts">
</p>

> Joyride is an independent, unofficial enhancement companion. It is not affiliated with or endorsed by
> the makers of Muse.

## What it does

- **Avatar Pack v3.** Downloadable ZIP packages with required commercial tiers, anchor-image hashing,
  model certification, animation metadata, and explicit format-version checks.
- **Local avatar library.** Import, switch, and move packs to the Trash without changing an agent plug-in.
- **Twenty-four states in three tiers.** Basic, advanced, and emotional state IDs live in the v3 data
  contract, and partial packs use semantic media fallbacks.
- **Multi-provider BYOK.** OpenAI, Google, and Anthropic keys are stored separately in macOS Keychain.
  OpenAI and Google generate with a shared user-authorized reference; Anthropic is clearly marked as
  non-rendering because Claude does not currently produce image output.
- **Privacy controls.** Private mode collapses all task meaning into neutral `working`. A local keyword
  blacklist is evaluated inside the agent process, so matched task text never reaches Joyride.
- **Multi-agent arbitration.** One winner is visible; a `+N` badge expands to show the other active agents.
- **Feedback channel.** Deployments can configure a waitlist, support email, feedback form, and opt-in
  anonymous metrics without shipping task content.
- **Resident-app safeguards.** Current-pack image preloading, paused animation while hidden or occluded,
  a visible hide control, an explicit click-through recovery path, and strict pack-version rejection.
- **Future-ready media.** Static images, animated images, and short video are represented in v3; static
  art receives a lightweight programmatic motion fallback.

See [PROTOCOL.md](PROTOCOL.md) for the complete pack format, event contract, certification rules, and
privacy model.

## State Matrix

The full matrix is part of Avatar Pack v3. Waitlist interest remains measurable through the configurable
Feedback channel; product capability is no longer represented as an uncounted README promise.

### Basic scenes

1. `working` — Typing at a computer while wearing headphones. Trigger: a tool call is running.
2. `thinking` — Resting their chin on one hand, with a question mark or light bulb. Trigger: planning or
   reasoning with no active tool call.
3. `researching` — Reviewing documents with a magnifying glass. Trigger: searching the web or reading a
   webpage.
4. `coding` — Working in a terminal or code editor. Trigger: shell commands or coding-related tool calls.
5. `finding_files` — Searching through folders. Trigger: file reading, writing, or search tools.
6. `waiting` — Checking a watch or watching a spinner. Trigger: waiting for a subagent or long-running task.
7. `greeting` — Waving hello. Trigger: a new session begins.
8. `idle` — Neutral daydreaming. Trigger: no active task.

### Extended scenes

9. `checking_flights` — Viewing a flight information panel. Trigger: flight searches or ticket booking.
10. `booking_hotel` — Browsing hotel cards. Trigger: hotel searches or reservations.
11. `travel` — Planning with a map and itinerary. Trigger: travel research or itinerary planning.
12. `calendar` — Updating a calendar. Trigger: calendar reading or writing.
13. `shopping` — Holding shopping bags. Trigger: price comparisons or adding items to a cart.
14. `unboxing` — Opening a package or mystery box. Trigger: a successful purchase or delivery tracking.
15. `meeting` — Appearing in a video meeting. Trigger: meeting- or email-related tasks.
16. `food_ordering` — Browsing food or holding a delivery bag. Trigger: restaurant or food-delivery searches.

### Emotional scenes

17. `staring_at_owner` — Leaning closer to the camera and looking at the owner. Trigger: seeking attention
    while idle or preparing to send a notification.
18. `daydreaming_hearts` — Gazing dreamily with floating hearts. Trigger: a long period of inactivity.
19. `resting` — Relaxing with a pillow, blanket, and “Zzz” effects. Trigger: sleep mode or a task-free late
    night.
20. `dreaming` — Sleeping with a dream bubble. Trigger: sleep mode, with future support for a “Sweet Dreams
    Service.”
21. `grooming` — Looking in a mirror and touching up their appearance. Trigger: a random idle moment or a
    compliment from the owner.
22. `celebrating` — Tossing confetti. Trigger: completing a task milestone.
23. `missing_you` — Looking out the window. Trigger: no owner interaction for a long time.
24. `goodnight` — Turning off the lights under the moon. Trigger: late at night or when the owner says
    goodnight.

## Build on macOS

Requirements: macOS 14 or newer and Swift 6.2 or newer.

```bash
./Scripts/build-app.sh
open "dist/Joyride.app"
```

The avatar library and settings live under the person icon in the macOS menu bar. Before mouse
click-through is enabled, Joyride shows the exact menu-bar recovery action.

## Import an avatar pack

1. Open **Avatar Library & Settings** from the menu-bar icon.
2. Choose **Import ZIP** and select a valid Avatar Pack v3 archive.
3. Select the pack and switch to it. Deletion uses the macOS Trash and the active pack cannot be deleted.

Packs made by models outside the local reference-image whitelist remain playable, but are labeled
**Uncertified** and are ineligible for future marketplace recommendations.

## Generate a pack with your own API key

1. Choose OpenAI, Google, or Anthropic and save that provider's key to macOS Keychain.
2. For generation, choose OpenAI or Google, a certified model, one eight-state tier, and a reference photo.
3. Confirm **I own this photo or have permission to use it**.
4. Generate the tier pack. Calls go directly to the selected provider and usage is charged to the key owner.

Anthropic keys are stored independently for future orchestration features, but the generation button is
disabled for Anthropic because Claude does not produce image output.

Without a key, Joyride does not upload a photo or silently use platform credits. A platform-funded
generation route is reserved for a later release. The platform-owned asset is only the versioned scene
prompt matrix.

## OpenClaw adapter

The adapter uses the typed hooks `model_call_started`, `before_tool_call`, `after_tool_call`, and
`agent_end`.

```bash
openclaw plugins install --link "$PWD/Adapters/OpenClaw" --force
openclaw plugins enable joyride
openclaw config set plugins.entries.joyride.hooks.allowConversationAccess true --strict-json
openclaw gateway restart
openclaw plugins inspect joyride --runtime --json
```

OpenClaw classifies `agent_end` as a conversation hook, so explicit access is required. The adapter does
not read the message array. It only uses a hashed run identifier.

## Hermes adapter

```bash
mkdir -p "$HOME/.hermes/plugins/joyride"
cp -R Adapters/Hermes/. "$HOME/.hermes/plugins/joyride/"
hermes plugins enable joyride
```

The adapter uses `pre_llm_call`, `pre_tool_call`, `post_tool_call`, and `on_session_end`.

## Test and benchmark

```bash
# Core state engine and Avatar Pack validation
swift run JoyrideCoreChecks

# Hermes unit tests and official validation
python3 -m unittest Adapters/Hermes/test_adapter.py
hermes plugins validate Adapters/Hermes

# End-to-end render latency, CPU, RSS, and hook coverage
python3 Tools/benchmark.py --samples 3 --resource-seconds 10 --output BENCHMARK.json
```

The measured switch latency starts when the local server receives `POST /v1/events` and ends after the
WebView decodes the new asset and enters the next rendering frame. See [BENCHMARK.md](BENCHMARK.md) for
the latest measured values and limitations.

## Send a test state

```bash
python3 Tools/joyridectl.py tool_started \
  --source demo --activity-id run-1 --operation-id tool-1 \
  --tool private --state-hint checking_flights --port 18765

python3 Tools/joyridectl.py run_finished \
  --source demo --activity-id run-1 --port 18765
```

Set `JOYRIDE_PORT` to change the app port. Set the OpenClaw plug-in `endpoint` or the Hermes
`JOYRIDE_ENDPOINT` variable to match it. Official adapters reject non-loopback endpoints.

## License

[MIT](LICENSE)
