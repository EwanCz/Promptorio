# Promptorio — 48h MVP Plan

Living document. Update it when scope or decisions change, and tick items off as they land.

## Decisions
- **LLM:** provider-agnostic adapter (`LLMProvider`). Anthropic first, OpenAI-compatible if time allows, plus a mock provider.
- **API key:** player-entered in a settings UI, stored in `user://settings.cfg`. `.env` is dev-only and never exported or committed.
- **Chip triggers:** fixed timer, state thresholds, events (input empty / output full / error), and a manual "Ask chip now" button.
- **Chips and prompts:** a machine can have several chips. Each chip has exactly one prompt and its own timeout, cooldown and in-flight slot, so chips never compete with each other.
- **Simulation clock:** physics-driven, with elapsed-time catch-up at 10 Hz; paused time is excluded.
- **Team and scope:** 2-3 devs, one tight loop (Miner -> Smelter -> Assembler) with a visible win/fail state. Conveyors are plain logic. AI on conveyors and logistics nodes is post-MVP.

Architecture and async HTTP rules live in `CLAUDE.md`.

## Phase 0 — Foundations (h0–4, everyone)
- [x] Autoloads: `EventBus`, `GameState`, `Settings`, `LLMManager` (+ `LLMProvider` base and `MockProvider`; `AnthropicProvider` still to do)
- [x] `Main` scene (HBox split: FactoryView 80% / Bar 20%, `UI` CanvasLayer for popups) and base `Machine` scene with `ChipComponent`
- [x] Tool-call schema and state JSON format (see "Machine / chip API"). Base `Machine` scene is now frozen: subclasses inherit it, don't edit it without telling the team

### Autoload API (for Machine / ChipComponent / UI work)
- `LLMManager.request_decision(requester_id: int, system_prompt: String, state: Dictionary, tools: Array)`. `requester_id` is `get_instance_id()`. Results come back as `decision_received(requester_id, tool_calls: Array[Dictionary])` (each `{name, args}`) or `decision_failed(requester_id, reason)`. A queued request replaced by a newer one from the same requester fails with `"superseded"`. Re-validate with `is_instance_valid(instance_from_id(id))` on receipt.
- Tool schema format (what `get_tool_schemas()` returns): `{name, description, input_schema: {type: "object", properties: {key: {type: "number"|"integer"|"boolean", minimum, maximum}}}}`.
- `GameState`: `TICK_RATE`, `GRID_SIZE`, `CELL_SIZE`, `tick_count`, `money`, `can_place(cell)`, `register_machine(machine, cell) -> bool`, `unregister_machine(cell)`, `get_machine_at(cell)`, `get_machines()`, `cell_to_world(cell)`, `world_to_cell(pos)`, `add_money(amount)`.
- `EventBus` signals: `tick_fired(tick)`, `machine_registered/unregistered(machine, cell)`, `machine_selected(machine)`, `money_changed(amount)`, `chip_log_added(machine, message)`, `settings_changed`.
- `Settings`: `api_key`, `provider` (`"mock"` for now), `model`, `max_concurrency`, `request_timeout`, `chip_cooldown`, `max_tokens`, `save_settings()`.
- Tests: `tests/run.sh [filter]` runs every `tests/test_*.gd` headless (~15 s, exit 1 on failure). How to write tests: see "Testing" in `CLAUDE.md`.
- Headless gotcha: after adding a new `class_name` script, run `godot --headless --import` once to refresh the class cache, otherwise it fails to parse. `godot --headless --quit` still errors until a main scene exists.

### Machine / chip API
- `Machine` (`scripts/machines/machine.gd`): `get_tool_schemas()`, `get_state() -> Dictionary` (compact: `type`, `enabled`, `status`, plus subclass fields), `apply_tool_call(name, args) -> bool` (whitelists the name, requires every schema arg, type-checks and clamps, then calls the `_apply()` override), `log_chip(message)` (emits `chip_log_added`). Base tool: `set_enabled(on: bool)`. `status` is `Machine.Status` (`NORMAL`, `DOWN`, `OVERHEATING`).
- `ChipComponent` (one child node per chip; a machine can have several): target API is one prompt per chip, `set_prompt(name, text, timeout)`, `request_decision(reason) -> bool`, `pending`, signal `decision_applied(reason, applied)`. Timers count `tick_fired` ticks. Cooldown comes from `Settings.chip_cooldown`. Threshold and event triggers are not wired yet: machine subclasses call `request_decision("...")`.
- Scenes: `scenes/main.tscn` is the project main scene; `scenes/machines/machine.tscn` is the base machine.

## Phase 1 — Parallel tracks (h4–20)
| Dev | Track |
|---|---|
| A (LLM) | `LLMProvider` base, `MockProvider`, `AnthropicProvider`, `HTTPRequest` pool, queue, timeout, 429 backoff, signals |
| B (Sim) | Grid placement, fixed-rate tick, Miner/Smelter/Assembler/Collector logic, smelter temperature model, explosion fail state |
| C (UI) | 80/20 split (Factory View + camera, Bar with Build / Prompt Registry pages), Prompt Page popup (pauses game), machine tooltip, settings dialog (key, provider, model), chip decision log. Spec in `docs/UI.md` |

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
