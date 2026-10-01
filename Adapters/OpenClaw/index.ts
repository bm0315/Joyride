import { createHash } from "node:crypto";
import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";

type AvatarState =
  | "working"
  | "checking_flights"
  | "shopping"
  | "thinking"
  | "researching";

type EventKind =
  | "model_started"
  | "tool_started"
  | "tool_finished"
  | "run_finished";

type AvatarEvent = {
  protocol: "agent-avatar/1";
  source: "openclaw";
  kind: EventKind;
  activity_id: string;
  operation_id?: string;
  tool?: "private";
  state_hint?: AvatarState;
};

type PrivacyConfig = {
  privacy_mode: boolean;
  keyword_blacklist: string[];
};

const defaultEndpoint = "http://127.0.0.1:8765/v1/events";
const requestTimeoutMilliseconds = 350;

function readEndpoint(config: Record<string, unknown> | undefined): string {
  const configured = config?.endpoint;
  if (configured === undefined) {
    return defaultEndpoint;
  }
  if (typeof configured !== "string") {
    throw new TypeError("Joyride endpoint must be a string.");
  }

  const parsed = new URL(configured);
  const isLoopback = parsed.hostname === "127.0.0.1" || parsed.hostname === "localhost";
  if (parsed.protocol !== "http:" || !isLoopback || parsed.pathname !== "/v1/events") {
    throw new TypeError("Joyride endpoint must be a loopback HTTP /v1/events URL.");
  }
  return parsed.toString();
}

function opaqueID(value: string | undefined, fallback: string): string {
  return createHash("sha256")
    .update(value && value.length > 0 ? value : fallback)
    .digest("hex")
    .slice(0, 24);
}

function inferState(toolName: string, params: Record<string, unknown>): AvatarState {
  const text = `${toolName} ${JSON.stringify(params).slice(0, 4_096)}`.toLowerCase();
  if (containsAny(text, flightKeywords)) {
    return "checking_flights";
  }
  if (containsAny(text, shoppingKeywords)) {
    return "shopping";
  }
  if (containsAny(text, researchKeywords)) {
    return "researching";
  }
  return "working";
}

function containsBlacklistedKeyword(
  toolName: string,
  params: Record<string, unknown>,
  keywords: readonly string[],
): boolean {
  const text = `${toolName} ${JSON.stringify(params).slice(0, 4_096)}`.toLowerCase();
  return containsAny(text, keywords.map((keyword) => keyword.toLowerCase()));
}

function containsAny(value: string, keywords: readonly string[]): boolean {
  return keywords.some((keyword) => value.includes(keyword));
}

const flightKeywords = [
  "flight", "airline", "airfare", "airport", "skyscanner", "trip.com", "ctrip",
  "航班", "机票", "机场",
] as const;

const shoppingKeywords = [
  "shopping", "shop", "cart", "checkout", "purchase", "amazon", "taobao", "tmall",
  "jd.com", "pinduoduo", "购物", "商品", "下单", "比价",
] as const;

const researchKeywords = [
  "browser", "browse", "search", "research", "web", "fetch", "crawl", "scrape",
  "read_url", "perplexity", "google", "bing", "搜索", "查找", "资料", "网页",
] as const;

export default definePluginEntry({
  id: "joyride",
  name: "Joyride",
  description: "Sends privacy-minimized lifecycle state to the local Joyride app.",
  register(api) {
    const endpoint = readEndpoint(api.pluginConfig);
    const configEndpoint = new URL("/v1/config", endpoint).toString();
    let lastWarningAt = 0;
    let privacyConfig: PrivacyConfig = { privacy_mode: false, keyword_blacklist: [] };
    let configExpiresAt = 0;

    const readPrivacyConfig = async (): Promise<PrivacyConfig> => {
      if (Date.now() < configExpiresAt) {
        return privacyConfig;
      }
      try {
        const response = await fetch(configEndpoint, {
          signal: AbortSignal.timeout(requestTimeoutMilliseconds),
        });
        if (!response.ok) {
          throw new Error(`Joyride config returned HTTP ${response.status}.`);
        }
        const value: unknown = await response.json();
        if (
          typeof value !== "object" || value === null
          || typeof (value as { privacy_mode?: unknown }).privacy_mode !== "boolean"
          || !Array.isArray((value as { keyword_blacklist?: unknown }).keyword_blacklist)
        ) {
          throw new TypeError("Joyride config response is invalid.");
        }
        const candidate = value as { privacy_mode: boolean; keyword_blacklist: unknown[] };
        privacyConfig = {
          privacy_mode: candidate.privacy_mode,
          keyword_blacklist: candidate.keyword_blacklist.filter(
            (item): item is string => typeof item === "string" && item.length > 0,
          ),
        };
        configExpiresAt = Date.now() + 5_000;
      } catch {
        configExpiresAt = Date.now() + 1_000;
      }
      return privacyConfig;
    };

    const postEvent = async (
      event: AvatarEvent,
      localContext?: { toolName: string; params: Record<string, unknown> },
    ): Promise<void> => {
      try {
        const config = await readPrivacyConfig();
        const mustNeutralize = config.privacy_mode || (
          localContext !== undefined
          && containsBlacklistedKeyword(localContext.toolName, localContext.params, config.keyword_blacklist)
        );
        const safeEvent = mustNeutralize
          ? { ...event, state_hint: "working" as const }
          : event;
        const response = await fetch(endpoint, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify(safeEvent),
          signal: AbortSignal.timeout(requestTimeoutMilliseconds),
        });
        if (!response.ok) {
          throw new Error(`Joyride returned HTTP ${response.status}.`);
        }
      } catch (error: unknown) {
        const now = Date.now();
        if (now - lastWarningAt >= 60_000) {
          lastWarningAt = now;
          const detail = error instanceof Error ? error.message : "unknown transport error";
          api.logger.warn(`Joyride is unavailable: ${detail}`);
        }
      }
    };

    api.on("model_call_started", (event, context) => {
      void postEvent({
        protocol: "agent-avatar/1",
        source: "openclaw",
        kind: "model_started",
        activity_id: opaqueID(context.runId ?? event.runId, "openclaw-run"),
      });
    });

    api.on("before_tool_call", (event, context) => {
      void postEvent({
        protocol: "agent-avatar/1",
        source: "openclaw",
        kind: "tool_started",
        activity_id: opaqueID(context.runId ?? event.runId, "openclaw-run"),
        operation_id: opaqueID(context.toolCallId ?? event.toolCallId, event.toolName),
        tool: "private",
        state_hint: inferState(event.toolName, event.params),
      }, { toolName: event.toolName, params: event.params });
    });

    api.on("after_tool_call", (event, context) => {
      void postEvent({
        protocol: "agent-avatar/1",
        source: "openclaw",
        kind: "tool_finished",
        activity_id: opaqueID(context.runId ?? event.runId, "openclaw-run"),
        operation_id: opaqueID(context.toolCallId ?? event.toolCallId, event.toolName),
        tool: "private",
      });
    });

    api.on("agent_end", (event, context) => {
      void postEvent({
        protocol: "agent-avatar/1",
        source: "openclaw",
        kind: "run_finished",
        activity_id: opaqueID(context.runId ?? event.runId, "openclaw-run"),
      });
    });
  },
});
