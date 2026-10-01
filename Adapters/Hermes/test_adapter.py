from __future__ import annotations

import importlib.util
import json
import pathlib
import unittest
from unittest import mock


MODULE_PATH = pathlib.Path(__file__).with_name("__init__.py")
SPEC = importlib.util.spec_from_file_location("joyride_hermes", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Could not load Hermes adapter")
ADAPTER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ADAPTER)


class HermesAdapterTests(unittest.TestCase):
    def test_classifies_flights_without_exporting_payload(self) -> None:
        state = ADAPTER._infer_state("browser", {"query": "上海到东京机票"})
        self.assertEqual(state, "checking_flights")

    def test_classifies_shopping(self) -> None:
        state = ADAPTER._infer_state("browser", {"url": "https://amazon.com/cart"})
        self.assertEqual(state, "shopping")

    def test_classifies_research(self) -> None:
        state = ADAPTER._infer_state("web_search", {"query": "local-first software"})
        self.assertEqual(state, "researching")

    def test_rejects_remote_endpoint(self) -> None:
        with self.assertRaises(ValueError):
            ADAPTER._validated_endpoint("https://example.com/v1/events")

    def test_hashes_activity_identifiers(self) -> None:
        value = ADAPTER._opaque_id("private-session-id", "fallback")
        self.assertEqual(len(value), 24)
        self.assertNotIn("private", value)

    def test_blacklist_matches_only_in_local_context(self) -> None:
        context = ADAPTER._local_context("browser", {"query": "Project Nightingale budget"})
        self.assertTrue(ADAPTER._contains_any(context, ("nightingale",)))
        event = {
            "protocol": "joyride/1",
            "source": "hermes",
            "kind": "tool_started",
            "state_hint": "researching",
        }
        self.assertNotIn("nightingale", json.dumps(event).lower())

    def test_emits_one_run_started_before_repeated_model_events(self) -> None:
        context = FakeContext()
        poster = FakePoster()
        with mock.patch.object(ADAPTER, "EventPoster", return_value=poster):
            ADAPTER.register(context)

        context.hooks["pre_llm_call"](session_id="session-1")
        context.hooks["pre_llm_call"](session_id="session-1")
        context.hooks["on_session_end"](session_id="session-1")

        self.assertEqual(
            [event["kind"] for event in poster.events],
            ["run_started", "model_started", "model_started", "run_finished"],
        )

    def test_tool_first_order_starts_the_run(self) -> None:
        context = FakeContext()
        poster = FakePoster()
        with mock.patch.object(ADAPTER, "EventPoster", return_value=poster):
            ADAPTER.register(context)

        context.hooks["pre_tool_call"](
            session_id="session-2",
            tool_call_id="call-1",
            tool_name="read_file",
            args={"path": "private"},
        )

        self.assertEqual(
            [event["kind"] for event in poster.events],
            ["run_started", "tool_started"],
        )
        self.assertEqual(poster.events[1]["state_hint"], "finding_files")


class FakeContext:
    def __init__(self) -> None:
        self.hooks: dict[str, object] = {}

    def register_hook(self, hook_name: str, callback: object) -> object:
        self.hooks[hook_name] = callback
        return callback


class FakePoster:
    def __init__(self) -> None:
        self.events: list[dict[str, str]] = []

    def submit(self, event: dict[str, str], local_context: str) -> None:
        self.events.append(event)


if __name__ == "__main__":
    unittest.main()
