# Joyride Naming Design

## Goal

Finish the product rename so public types, build targets, wire contracts, environment variables, tools, and bundled data all identify the product as Joyride.

## Canonical names

- Swift library target: `JoyrideCore`
- macOS executable target and product: `Joyride`
- check target: `JoyrideCoreChecks`
- event protocol: `joyride/1`
- pack format: `joyride-pack`
- event endpoint variable: `JOYRIDE_ENDPOINT`
- local port variable: `JOYRIDE_PORT`
- selected pack variable: `JOYRIDE_PACK`
- bundled pack ID: `app.joyride.default-blue`
- command-line helper: `joyridectl.py`

Application Support storage remains under `Joyride`, and the bundle identifier remains `app.joyride.desktop`.

## Migration policy

The repository and current documentation use only canonical Joyride names. This development build does not preserve public pre-rename type aliases or environment-variable aliases because they would extend an accidental pre-release API. User-created pack data is migrated by manifest parsing and re-import, not by keeping the retired wire identifier alive.

## Acceptance criteria

- Repository source and tracked artifacts contain no retired pre-rename identifiers.
- The built executable and app bundle are named Joyride.
- Adapters and CLI emit `joyride/1`.
- The default pack ID and format use Joyride names.
- Build, checks, adapter tests, and README examples use only the canonical names.
