#!/usr/bin/env python3
"""Send a validated test event to a running Joyride application."""

from __future__ import annotations

import argparse
import json
import urllib.error
import urllib.request


EVENT_KINDS = (
    "run_started",
    "model_started",
    "model_finished",
    "tool_started",
    "tool_finished",
    "run_finished",
    "idle",
)
STATE_HINTS = (
    "working",
    "checking_flights",
    "shopping",
    "thinking",
    "researching",
)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=EVENT_KINDS)
    parser.add_argument("--source", required=True)
    parser.add_argument("--activity-id")
    parser.add_argument("--operation-id")
    parser.add_argument("--tool")
    parser.add_argument("--state-hint", choices=STATE_HINTS)
    parser.add_argument("--port", type=int, required=True)
    return parser.parse_args()


def build_event(arguments: argparse.Namespace) -> dict[str, str]:
    event = {
        "protocol": "agent-avatar/1",
        "source": arguments.source,
        "kind": arguments.kind,
    }
    optional_fields = {
        "activity_id": arguments.activity_id,
        "operation_id": arguments.operation_id,
        "tool": arguments.tool,
        "state_hint": arguments.state_hint,
    }
    event.update({key: value for key, value in optional_fields.items() if value is not None})
    return event


def main() -> int:
    arguments = parse_arguments()
    if arguments.port < 1 or arguments.port > 65_535:
        raise ValueError("--port must be between 1 and 65535")

    request = urllib.request.Request(
        f"http://127.0.0.1:{arguments.port}/v1/events",
        data=json.dumps(build_event(arguments), separators=(",", ":")).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=1) as response:
            print(response.read().decode("utf-8"))
    except urllib.error.URLError as error:
        raise RuntimeError(f"Joyride request failed: {error}") from error
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
