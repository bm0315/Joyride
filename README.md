# Joyride

**An enhanced companion plug-in for the Muse virtual avatar.**

Joyride turns an agent's real work into a living desktop character. It reads privacy-minimized lifecycle
events from supported agents, chooses the winning state when several agents are active, and plays the
matching scene from a replaceable avatar pack. When work stops, the character rests, daydreams, or looks
back at its owner.

<p align="center">
  <img src="Assets/packs/default/images/state-01-working.webp" width="31%" alt="Joyride agent working">
  <img src="Assets/packs/default/images/state-06-researching.webp" width="31%" alt="Joyride agent researching">
  <img src="Assets/packs/default/images/state-08-daydreaming-hearts.webp" width="31%" alt="Joyride agent daydreaming">
</p>

> Joyride is an independent, unofficial enhancement companion. It is not affiliated with or endorsed by
> the makers of Muse.

## What it does

- **Avatar Pack v1.** Downloadable ZIP packages with strict manifests, anchor-image hashing, model
  certification, animation metadata, and explicit format-version checks.
- **Local avatar library.** Import, switch, and move packs to the Trash without changing an agent plug-in.
- **Eight states.** `working`, `thinking`, `researching`, `shopping`, `checking_flights`, plus three idle
  scenes: `resting`, `staring_at_owner`, and `daydreaming_hearts`.
- **BYOK generation.** An OpenAI API key stays in macOS Keychain. A user-authorized reference photo is
  sent directly from the Mac to the Images Edits API; every generated state reuses the exact same anchor.
- **Privacy controls.** Private mode collapses all task meaning into neutral `working`. A local keyword
  blacklist is evaluated inside the agent process, so matched task text never reaches Joyride.
- **Multi-agent arbitration.** One winner is visible; a `+N` badge expands to show the other active agents.
- **Resident-app safeguards.** Current-pack image preloading, paused animation while hidden or occluded,
  an explicit click-through recovery path, and strict pack-version rejection.
- **Future-ready media.** Static images, animated images, and short video are represented in v1; static
  art receives a lightweight programmatic motion fallback.

See [PROTOCOL.md](PROTOCOL.md) for the complete pack format, event contract, certification rules, and
privacy model.

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
2. Choose **Import ZIP** and select a valid Avatar Pack v1 archive.
3. Select the pack and switch to it. Deletion uses the macOS Trash and the active pack cannot be deleted.

Packs made by models outside the local reference-image whitelist remain playable, but are labeled
**Uncertified** and are ineligible for future marketplace recommendations.

## Generate a pack with your own API key

1. Save an OpenAI API key to macOS Keychain in Joyride settings.
2. Choose a certified model and a reference photo.
3. Confirm **I own this photo or have permission to use it**.
4. Generate the eight-state pack. Calls go directly to OpenAI and usage is charged to the key owner.

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
swift run AgentAvatarCoreChecks

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
python3 Tools/agent_avatarctl.py tool_started \
  --source demo --activity-id run-1 --operation-id tool-1 \
  --tool private --state-hint checking_flights --port 8765

python3 Tools/agent_avatarctl.py run_finished \
  --source demo --activity-id run-1 --port 8765
```

Set `AGENT_AVATAR_PORT` to change the app port. Set the OpenClaw plug-in `endpoint` or the Hermes
`AGENT_AVATAR_ENDPOINT` variable to match it. Official adapters reject non-loopback endpoints.

## License

[MIT](LICENSE)
