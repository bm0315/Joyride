#!/usr/bin/env python3
"""Measure Joyride state latency, resource use, and adapter hook coverage."""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import time
import urllib.request
from pathlib import Path


def request_json(url: str, method: str, payload: dict[str, object] | None) -> dict[str, object]:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"} if data is not None else {},
        method=method,
    )
    with urllib.request.urlopen(request, timeout=1.0) as response:
        value = json.loads(response.read().decode("utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError(f"Expected an object from {url}")
    return value


def process_sample(process_name: str) -> tuple[float, int]:
    result = subprocess.run(
        ["/usr/bin/pgrep", "-x", process_name],
        check=True,
        capture_output=True,
        text=True,
    )
    pid = result.stdout.splitlines()[0]
    sample = subprocess.run(
        ["/bin/ps", "-p", pid, "-o", "%cpu=", "-o", "rss="],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.split()
    return float(sample[0]), int(sample[1])


def measure_resources(process_name: str, seconds: int) -> tuple[float, float]:
    cpu_values: list[float] = []
    rss_values: list[int] = []
    for _ in range(seconds):
        cpu, rss = process_sample(process_name)
        cpu_values.append(cpu)
        rss_values.append(rss)
        time.sleep(1)
    return statistics.mean(cpu_values), statistics.mean(rss_values) / 1024


def measure_transition(base_url: str, sample: int, state_hint: str) -> float:
    activity_id = f"benchmark-{sample}"
    payload = {
        "protocol": "agent-avatar/1",
        "source": "benchmark",
        "kind": "tool_started",
        "activity_id": activity_id,
        "operation_id": f"operation-{sample}",
        "tool": "private",
        "state_hint": state_hint,
    }
    request_json(f"{base_url}/v1/events", "POST", payload)
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        metrics = request_json(f"{base_url}/v1/metrics", "GET", None)
        if metrics.get("state") == state_hint and isinstance(
            metrics.get("state_switch_latency_ms"), (int, float)
        ):
            latency = float(metrics["state_switch_latency_ms"])
            request_json(
                f"{base_url}/v1/events",
                "POST",
                {
                    "protocol": "agent-avatar/1",
                    "source": "benchmark",
                    "kind": "run_finished",
                    "activity_id": activity_id,
                },
            )
            return latency
        time.sleep(0.02)
    raise RuntimeError("Timed out waiting for the rendered state metric")


def wait_for_idle(base_url: str) -> None:
    deadline = time.monotonic() + 7
    while time.monotonic() < deadline:
        metrics = request_json(f"{base_url}/v1/metrics", "GET", None)
        if metrics.get("state") in {"resting", "staring_at_owner", "daydreaming_hearts"}:
            return
        time.sleep(0.1)
    raise RuntimeError("Timed out waiting for the player to return to idle")


def hook_coverage(project: Path) -> dict[str, dict[str, object]]:
    openclaw = (project / "Adapters/OpenClaw/index.ts").read_text(encoding="utf-8")
    hermes = (project / "Adapters/Hermes/__init__.py").read_text(encoding="utf-8")
    expected = {
        "OpenClaw": (openclaw, ["model_call_started", "before_tool_call", "after_tool_call", "agent_end"]),
        "Hermes": (hermes, ["pre_llm_call", "pre_tool_call", "post_tool_call", "on_session_end"]),
    }
    return {
        name: {
            "covered": sum(hook in content for hook in hooks),
            "expected": len(hooks),
            "hooks": [hook for hook in hooks if hook in content],
        }
        for name, (content, hooks) in expected.items()
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8765")
    parser.add_argument("--resource-seconds", type=int, default=5)
    parser.add_argument("--samples", type=int, default=3)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    project = Path(__file__).resolve().parents[1]
    state_hints = ["checking_flights", "shopping", "researching"]
    latencies: list[float] = []
    for index in range(args.samples):
        latencies.append(measure_transition(args.base_url, index + 1, state_hints[index % len(state_hints)]))
        wait_for_idle(args.base_url)
    cpu, rss = measure_resources("Joyride", args.resource_seconds)
    sorted_latencies = sorted(latencies)
    p95_index = min(len(sorted_latencies) - 1, round(0.95 * (len(sorted_latencies) - 1)))
    report = {
        "measured_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "state_switch_latency_ms_p50": round(statistics.median(latencies), 2),
        "state_switch_latency_ms_p95": round(sorted_latencies[p95_index], 2),
        "state_switch_latency_samples_ms": [round(value, 2) for value in latencies],
        "cpu_percent_mean": round(cpu, 2),
        "memory_rss_mb_mean": round(rss, 2),
        "hook_coverage": hook_coverage(project),
        "resource_sample_seconds": args.resource_seconds,
    }
    rendered = json.dumps(report, ensure_ascii=False, indent=2)
    print(rendered)
    if args.output is not None:
        args.output.write_text(rendered + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
