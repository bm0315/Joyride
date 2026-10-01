"""Hermes lifecycle bridge for the local Joyride application."""

from __future__ import annotations

import hashlib
import json
import logging
import os
import queue
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable, Mapping
from typing import Protocol


LOGGER = logging.getLogger(__name__)
DEFAULT_ENDPOINT = "http://127.0.0.1:8765/v1/events"
REQUEST_TIMEOUT_SECONDS = 0.35


class PluginContext(Protocol):
    def register_hook(self, hook_name: str, callback: Callable[..., object]) -> object: ...


AvatarEvent = dict[str, str]
PrivacyConfig = tuple[bool, tuple[str, ...]]


def _validated_endpoint(raw_value: str) -> str:
    parsed = urllib.parse.urlparse(raw_value)
    if (
        parsed.scheme != "http"
        or parsed.hostname not in {"127.0.0.1", "localhost"}
        or parsed.path != "/v1/events"
        or parsed.params
        or parsed.query
        or parsed.fragment
    ):
        raise ValueError("JOYRIDE_ENDPOINT must be a loopback HTTP /v1/events URL")
    return raw_value


def _opaque_id(value: object, fallback: str) -> str:
    normalized = value if isinstance(value, str) and value else fallback
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()[:24]


def _contains_any(value: str, keywords: tuple[str, ...]) -> bool:
    return any(keyword in value for keyword in keywords)


def _infer_state(tool_name: str, args: object) -> str:
    try:
        serialized = json.dumps(args, ensure_ascii=False, default=str)[:4096]
    except (TypeError, ValueError, OverflowError):
        serialized = ""
    value = f"{tool_name} {serialized}".lower()

    if _contains_any(value, FLIGHT_KEYWORDS):
        return "checking_flights"
    if _contains_any(value, HOTEL_KEYWORDS):
        return "booking_hotel"
    if _contains_any(value, TRAVEL_KEYWORDS):
        return "travel"
    if _contains_any(value, CALENDAR_KEYWORDS):
        return "calendar"
    if _contains_any(value, SHOPPING_KEYWORDS):
        return "shopping"
    if _contains_any(value, FOOD_KEYWORDS):
        return "food_ordering"
    if _contains_any(value, MEETING_KEYWORDS):
        return "meeting"
    if _contains_any(value, CODE_KEYWORDS):
        return "coding"
    if _contains_any(value, FILE_KEYWORDS):
        return "finding_files"
    if _contains_any(value, RESEARCH_KEYWORDS):
        return "researching"
    return "working"


def _local_context(tool_name: str, args: object) -> str:
    try:
        serialized = json.dumps(args, ensure_ascii=False, default=str)[:4096]
    except (TypeError, ValueError, OverflowError):
        serialized = ""
    return f"{tool_name} {serialized}".lower()


FLIGHT_KEYWORDS = (
    "flight", "airline", "airfare", "airport", "skyscanner", "trip.com", "ctrip",
    "航班", "机票", "机场",
)
SHOPPING_KEYWORDS = (
    "shopping", "shop", "cart", "checkout", "purchase", "amazon", "taobao", "tmall",
    "jd.com", "pinduoduo", "购物", "商品", "下单", "比价",
)
HOTEL_KEYWORDS = ("hotel", "lodging", "booking.com", "airbnb", "酒店", "住宿")
TRAVEL_KEYWORDS = ("itinerary", "travel", "trip_plan", "maps", "行程", "旅行", "攻略")
CALENDAR_KEYWORDS = ("calendar", "schedule", "event.create", "日历", "日程")
FOOD_KEYWORDS = ("restaurant", "food", "meal", "delivery", "外卖", "点餐", "餐厅")
MEETING_KEYWORDS = ("meeting", "zoom", "teams", "email", "mail", "会议", "邮件")
CODE_KEYWORDS = ("terminal", "shell", "exec", "command", "code", "compile", "build", "test", "git")
FILE_KEYWORDS = ("file", "folder", "filesystem", "read_file", "write_file", "glob", "find", "文件", "目录")
RESEARCH_KEYWORDS = (
    "browser", "browse", "search", "research", "web", "fetch", "crawl", "scrape",
    "read_url", "perplexity", "google", "bing", "搜索", "查找", "资料", "网页",
)


class EventPoster:
    def __init__(self, endpoint: str) -> None:
        self._endpoint = endpoint
        self._config_endpoint = urllib.parse.urljoin(endpoint, "/v1/config")
        self._events: queue.Queue[tuple[AvatarEvent, str]] = queue.Queue(maxsize=64)
        self._last_warning_at = 0.0
        self._privacy_config: PrivacyConfig = (False, ())
        self._config_expires_at = 0.0
        self._worker = threading.Thread(
            target=self._run,
            name="joyride-events",
            daemon=True,
        )
        self._worker.start()

    def submit(self, event: AvatarEvent, local_context: str) -> None:
        try:
            self._events.put_nowait((event, local_context))
        except queue.Full:
            now = time.monotonic()
            if now - self._last_warning_at >= 60:
                self._last_warning_at = now
                LOGGER.warning("Joyride event queue is full; dropping lifecycle updates")

    def _run(self) -> None:
        while True:
            event, local_context = self._events.get()
            try:
                private_mode, keywords = self._read_privacy_config()
                safe_event = dict(event)
                if private_mode or _contains_any(local_context, keywords):
                    safe_event["state_hint"] = "working"
                self._post(safe_event)
            finally:
                self._events.task_done()

    def _read_privacy_config(self) -> PrivacyConfig:
        now = time.monotonic()
        if now < self._config_expires_at:
            return self._privacy_config
        request = urllib.request.Request(self._config_endpoint, method="GET")
        try:
            with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
                raw_value = json.loads(response.read(8192).decode("utf-8"))
            if not isinstance(raw_value, dict):
                raise ValueError("privacy config must be an object")
            private_mode = raw_value.get("privacy_mode")
            keywords = raw_value.get("keyword_blacklist")
            if not isinstance(private_mode, bool) or not isinstance(keywords, list):
                raise ValueError("privacy config has invalid fields")
            normalized = tuple(
                item.lower() for item in keywords if isinstance(item, str) and item
            )
            self._privacy_config = (private_mode, normalized)
            self._config_expires_at = now + 5.0
        except (OSError, ValueError, json.JSONDecodeError, urllib.error.URLError):
            self._config_expires_at = now + 1.0
        return self._privacy_config

    def _post(self, event: AvatarEvent) -> None:
        request = urllib.request.Request(
            self._endpoint,
            data=json.dumps(event, separators=(",", ":")).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
                if response.status < 200 or response.status >= 300:
                    raise RuntimeError(f"Joyride returned HTTP {response.status}")
        except (OSError, RuntimeError, urllib.error.URLError) as error:
            now = time.monotonic()
            if now - self._last_warning_at >= 60:
                self._last_warning_at = now
                LOGGER.warning("Joyride is unavailable: %s", error)


def _string_value(values: Mapping[str, object], *keys: str) -> str:
    for key in keys:
        value = values.get(key)
        if isinstance(value, str) and value:
            return value
    return ""


def register(ctx: PluginContext) -> None:
    endpoint = _validated_endpoint(os.environ.get("JOYRIDE_ENDPOINT", DEFAULT_ENDPOINT))
    poster = EventPoster(endpoint)
    active_runs: set[str] = set()
    active_runs_lock = threading.Lock()

    def activity_id(kwargs: Mapping[str, object]) -> str:
        return _opaque_id(
            _string_value(kwargs, "session_id", "task_id", "turn_id"),
            "hermes-run",
        )

    def ensure_run_started(run_id: str) -> None:
        with active_runs_lock:
            if run_id in active_runs:
                return
            active_runs.add(run_id)
            poster.submit({
                "protocol": "joyride/1",
                "source": "hermes",
                "kind": "run_started",
                "activity_id": run_id,
            }, "")

    def model_started(**kwargs: object) -> None:
        run_id = activity_id(kwargs)
        ensure_run_started(run_id)
        poster.submit({
            "protocol": "joyride/1",
            "source": "hermes",
            "kind": "model_started",
            "activity_id": run_id,
        }, "")

    def tool_started(**kwargs: object) -> None:
        tool_name = _string_value(kwargs, "tool_name") or "unknown"
        args = kwargs.get("args", {})
        run_id = activity_id(kwargs)
        ensure_run_started(run_id)
        poster.submit({
            "protocol": "joyride/1",
            "source": "hermes",
            "kind": "tool_started",
            "activity_id": run_id,
            "operation_id": _opaque_id(
                _string_value(kwargs, "tool_call_id"),
                tool_name,
            ),
            "tool": "private",
            "state_hint": _infer_state(tool_name, args),
        }, _local_context(tool_name, args))

    def tool_finished(**kwargs: object) -> None:
        tool_name = _string_value(kwargs, "tool_name") or "unknown"
        run_id = activity_id(kwargs)
        ensure_run_started(run_id)
        poster.submit({
            "protocol": "joyride/1",
            "source": "hermes",
            "kind": "tool_finished",
            "activity_id": run_id,
            "operation_id": _opaque_id(
                _string_value(kwargs, "tool_call_id"),
                tool_name,
            ),
            "tool": "private",
        }, "")

    def run_finished(**kwargs: object) -> None:
        run_id = activity_id(kwargs)
        ensure_run_started(run_id)
        poster.submit({
            "protocol": "joyride/1",
            "source": "hermes",
            "kind": "run_finished",
            "activity_id": run_id,
        }, "")
        with active_runs_lock:
            active_runs.discard(run_id)

    ctx.register_hook("pre_llm_call", model_started)
    ctx.register_hook("pre_tool_call", tool_started)
    ctx.register_hook("post_tool_call", tool_finished)
    ctx.register_hook("on_session_end", run_finished)
