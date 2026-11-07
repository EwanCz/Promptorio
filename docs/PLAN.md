# Promptorio — 48h MVP Plan

Living document. Update it when scope or decisions change, and tick items off as they land.

## Decisions
- **LLM:** provider-agnostic adapter (`LLMProvider`). Anthropic first, OpenAI-compatible if time allows, plus a mock provider.
- **API key:** player-entered in a settings UI, stored in `user://settings.cfg`. `.env` is dev-only and never exported or committed.
- **Chip triggers:** fixed timer, state thresholds, events (input empty / output full / error), and a manual "Ask chip now" button.
- **Team and scope:** 2-3 devs, one tight loop (Miner -> Smelter -> Assembler) with a visible win/fail state. Conveyors are plain logic. AI on conveyors and logistics nodes is post-MVP.

Architecture and async HTTP rules live in `CLAUDE.md`.

## Phase 0 — Foundations (h0–4, everyone)
- [ ] Autoloads: `EventBus`, `GameState`, `Settings`, `LLMManager`
- [ ] `Main` scene and base `Machine` scene with `ChipComponent`
- [ ] Agree on the tool-call schema and state JSON format (then freeze the base `Machine` scene)

## Phase 1 — Parallel tracks (h4–20)
| Dev | Track |
|---|---|
| A (LLM) | `LLMProvider` base, `MockProvider`, `AnthropicProvider`, `HTTPRequest` pool, queue, timeout, 429 backoff, signals |
| B (Sim) | Grid placement, fixed-rate tick, Miner/Smelter/Assembler/Collector logic, smelter temperature model, explosion fail state |
| C (UI) | Build bar, prompt editor popup, settings dialog (key, provider, model), chip decision log |

## Phase 2 — Integration (h20–32)
- [ ] `ChipComponent` wired to `LLMManager`: timer, threshold, event and manual triggers, per-chip cooldown, one request in flight per chip
- [ ] Each machine exposes `get_tool_schemas()` and `apply_tool_call()` (validates and clamps all LLM args)
- [ ] Full loop on the mock provider, then on the real API

## Phase 3 — Game feel and demo (h32–42)
- [ ] Demo scenario with a visible win and fail state (bad prompt -> smelter explodes, good prompt -> stable)
- [ ] Chip activity feedback: "thinking…" indicator, decision bubbles
- [ ] 2-3 example prompts for first-time players

## Phase 4 — Polish (h42–48)
- [ ] Bug fixes and graceful API-failure handling
- [ ] Build/export test, and check that no key is baked into the export
- [ ] README and demo rehearsal

## Risks and mitigations
1. **Latency or rate limits during the demo:** mock provider, per-chip cooldown, small fast model.
2. **Malformed or unsafe LLM output:** whitelist and clamp in `apply_tool_call`. A failed call leaves the machine on its last settings.
3. **Scene merge conflicts:** each dev owns different scenes, and the base `Machine` scene is frozen after Phase 0.
