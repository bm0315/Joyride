from __future__ import annotations

import importlib.util
import json
import pathlib
import unittest


MODULE_PATH = pathlib.Path(__file__).with_name("__init__.py")
SPEC = importlib.util.spec_from_file_location("agent_avatar_hermes", MODULE_PATH)
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
            "protocol": "agent-avatar/1",
            "source": "hermes",
            "kind": "tool_started",
            "state_hint": "researching",
        }
        self.assertNotIn("nightingale", json.dumps(event).lower())


if __name__ == "__main__":
    unittest.main()
