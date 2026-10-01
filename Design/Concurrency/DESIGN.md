# Multi-Agent Concurrency Design

## Goal

Make the badge, expanded list, and state arbitration use the same unit: one active agent source.

## Aggregation

The state engine may track multiple runs and tools for a source internally. Before producing a snapshot it groups activities by source and selects one representative candidate per source using priority first and most-recent update second.

The global winner is selected from those per-source representatives using the same ordering.

## Presentation contract

- `activeAgents` contains exactly one row per active source.
- `activeCount` equals `activeAgents.count`.
- The badge is `max(0, activeCount - 1)` because the visible avatar already represents the winning source.
- The expanded list contains one row per source, including the winner, and may show that source's current representative state.

Multiple tools from one source never increase the agent badge or add duplicate rows.

## Acceptance criteria

- One source with three active tools produces one row, count `1`, and no `+N` badge.
- Two sources produce two rows, count `2`, and a `+1` badge.
- State arbitration still honors privacy mode, task blacklist suppression, priority, and recency.
- The winning source is stable when a lower-priority tool starts in the same source.
