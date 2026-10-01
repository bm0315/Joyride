# Joyride Local Benchmark

Measured: October 1, 2026 at 21:36 Asia/Shanghai

Environment: macOS 26.6.2, arm64, Joyride 0.2.0 debug/ad-hoc signed build

| Metric | Joyride player | OpenClaw adapter | Hermes adapter |
| --- | ---: | ---: | ---: |
| State-switch latency P50 | 2.58 ms | — | — |
| State-switch latency P95 | 154.05 ms | — | — |
| Mean CPU over 10 seconds | 1.10% | — | — |
| Mean resident memory | 80.41 MB | — | — |
| Lifecycle hook coverage | — | 4/4 | 4/4 |

Latency samples: `154.05 ms`, `2.58 ms`, and `1.93 ms`. The first sample includes a cold image decode; the
next two use assets already present in the preload cache. Latency begins when the local listener receives
`POST /v1/events` and ends after the WebView decodes the new asset and enters the next rendering frame.

Hook coverage:

- OpenClaw: `model_call_started`, `before_tool_call`, `after_tool_call`, and `agent_end`.
- Hermes: `pre_llm_call`, `pre_tool_call`, `post_tool_call`, and `on_session_end`.

Machine-readable raw data is stored in `BENCHMARK.json`. Reproduce the measurement with:

```bash
python3 Tools/benchmark.py --samples 3 --resource-seconds 10 --output BENCHMARK.json
```

This is a short local benchmark, not a performance guarantee for other machines or optimized release
builds.
