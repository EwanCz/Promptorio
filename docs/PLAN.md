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
- [x] Autoloads: `EventBus`, `GameState`, `Settings`, `LLMManager` (+ `LLMProvider` base, `MockProvider`, `AnthropicProvider`)
- [x] `Main` scene (HBox split: FactoryView 80% / Bar 20%, `UI` CanvasLayer for popups) and base `Machine` scene with `ChipComponent`
- [x] Tool-call schema and state JSON format (see "Machine / chip API"). Base `Machine` scene is now frozen: subclasses inherit it, don't edit it without telling the team

### Autoload API (for Machine / ChipComponent / UI work)
- `LLMManager.request_decision(requester_id: int, system_prompt: String, state: Dictionary, tools: Array)`. `requester_id` is `get_instance_id()`. Results come back as `decision_received(requester_id, tool_calls: Array[Dictionary])` (each `{name, args}`) or `decision_failed(requester_id, reason)`. A queued request replaced by a newer one from the same requester fails with `"superseded"`. Re-validate with `is_instance_valid(instance_from_id(id))` on receipt.
- Tool schema format (what `get_tool_schemas()` returns): `{name, description, input_schema: {type: "object", properties: {key: {type: "number"|"integer"|"boolean", minimum, maximum}}}}`.
- `GameState`: `TICK_RATE`, `GRID_SIZE`, `CELL_SIZE`, `tick_count`, `money`, `can_place(cell)`, `register_machine(machine, cell) -> bool`, `unregister_machine(cell)`, `get_machine_at(cell)`, `get_machines()`, `cell_to_world(cell)`, `world_to_cell(pos)`, `add_money(amount)`.
- `EventBus` signals: `tick_fired(tick)`, `machine_exploded(machine)`, `machine_registered/unregistered(machine, cell)`, `machine_selected(machine)`, `money_changed(amount)`, `chip_log_added(machine, message)`, `settings_changed`, `chip_registered/chip_removed(chip)` (emitted by `ChipRegistry`), `llm_request_started(requester_id)`, `llm_request_finished(requester_id, success)` (emitted by `LLMManager`). `Settings.provider` accepts `"mock"` or `"anthropic"`.
- `Settings`: `api_key`, `provider` (`"mock"` for now), `model`, `max_concurrency`, `request_timeout`, `chip_cooldown`, `max_tokens`, `save_settings()`.
- Tests: `tests/run.sh [filter]` runs every `tests/test_*.gd` headless (~15 s, exit 1 on failure). How to write tests: see "Testing" in `CLAUDE.md`.
- Headless gotcha: after adding a new `class_name` script, run `godot --headless --import` once to refresh the class cache, otherwise it fails to parse. `godot --headless --quit` still errors until a main scene exists.

### Machine / chip API
- `Machine` (`scripts/machines/machine.gd`): `get_tool_schemas()`, `get_state() -> Dictionary` (compact: `type`, `enabled`, `status`, plus subclass fields), `apply_tool_call(name, args) -> bool` (whitelists the name, requires every schema arg, type-checks and clamps, then calls the `_apply()` override), `log_chip(message)` (emits `chip_log_added`). Base tool: `set_enabled(on: bool)`. `status` is `Machine.Status` (`NORMAL`, `DOWN`, `OVERHEATING`).
- `ChipRessource` (`scripts/chip/chip_ressource.gd`, a `Resource`, pure data): `id`, `name`, `description`, `prompt`.
- `ChipRegistry` (autoload, `scripts/chip/chip_registry.gd`): `add(name, prompt, desc = "") -> ChipRessource` (null if the name is empty or taken), `remove(id) -> bool`, `get_from_id(id)`, `get_all()`. Emits `EventBus.chip_registered/chip_removed`.
- `ChipComponent` (`scripts/chip/chip_component.gd`, a `Node`, child of the `Machine`): holds a `ChipRessource` (`chip`), `timeout` (ticks between timer calls, `set_timeout()`), `pending`. `call_llm(reason) -> bool` asks the LLM (named `call_llm` because `Object.call` is native); cooldown (`Settings.chip_cooldown`) and one request in flight apply per chip. The answer goes through `Machine.apply_tool_call`; signal `decision_applied(reason, applied)`.
- `Machine`: `chips: Array[ChipComponent]`, `attach_chip(chip_id, timeout_ticks) -> ChipComponent` (null if unknown or already attached), `detach_chip(id)`, `get_chip(id)`, signal `chip_decision_applied(chip_id, reason, applied)`.
- Scenes: `scenes/main.tscn` is the project main scene; `scenes/machines/machine.tscn` is the base machine.

## Phase 1 — Parallel tracks (h4–20)
| Dev | Track |
|---|---|
| A (LLM) | `LLMProvider` base, `MockProvider`, `AnthropicProvider`, `HTTPRequest` pool, queue, timeout, 429 backoff, signals |
| B (Sim) | Grid placement, fixed-rate tick, Miner/Smelter/Assembler/Collector logic, smelter temperature model, explosion fail state |
| C (UI) | 80/20 split (Factory View + camera, Bar with Build / Chip Registry pages), Chip Page popup (pauses game), machine tooltip, settings dialog (key, provider, model), chip decision log. Spec in `docs/UI.md` |

### LLM (track A, done)
- [x] `LLMProvider` base, `AnthropicProvider`, `MockProvider` (deterministic canned answer: first tool, booleans `true`, integers at `minimum`, numbers at the midpoint; latency stays random 0.3-1.5 s; empty tool list gives no calls)
- [x] `HTTPRequest` pool, queue, `max_concurrency`, timeout, 429 exponential backoff (3 retries max), `decision_received` / `decision_failed`
- [x] Real HTTP path tested offline (`tests/test_llm_http.gd`): timeout, transport failure, non-200, invalid JSON, 429 backoff and cap. Seam: `LLMManager._send(request)` is the only code that touches `HTTPRequest`; tests subclass it (`tests/support/scripted_llm_manager.gd`) and set `backoff_base` small.

### Simulation (track B, done)
- [x] Chain Miner -> Smelter -> Assembler -> Collector over plain `Conveyor`s, driven by `EventBus.tick_fired`. `Machine` gained `facing`, `receive(item) -> bool` (default refuses), `_tick()` (override per type, skipped while `DOWN`) and `_push(item)` (hands an item to the machine in front). Items are strings: `ore` -> `ingot` -> `part`.
- [x] `Miner`: 1 ore / `mine_ticks` (20), stalls while its output is blocked. `CraftMachine` (base of `Smelter` and `Assembler`): per-item input stock capped at 10, `Recipe` resource (`data/recipes/smelt.tres`: 1 ore -> ingot in 20 ticks; `assemble.tres`: 2 ingots -> part in 30 ticks), blocked output stalls it. `Collector` accepts everything and sells it (`PRICES`: ore 1, ingot 3, part 10; hardcoded, marked `shortcut:`). `Conveyor` holds one item and moves it on after 5 ticks.
- [x] Conveyor behavior: a conveyor is an ordinary placed machine with a facing direction. On each 10 Hz simulation tick it advances its held item; after 5 ticks it tries to deliver that item to the machine in the adjacent cell it faces. If the cell is empty or the machine refuses the item, it keeps the item and retries on later ticks. A conveyor accepts only one item at a time. Machines can also pass items directly to an adjacent machine, so conveyors are optional links rather than automatic belts between every machine.
- [x] Smelter temperature: working +0.6/tick, idle -0.3/tick, `set_cooling(on)` an extra -0.7/tick, floor 20. `OVERHEATING` at 100 (back to `NORMAL` at 80), explodes at 150: `DOWN`, stock lost, `EventBus.machine_exploded`. Without a chip a busy smelter explodes after ~22 s; `set_cooling(true)` or `set_enabled(false)` keeps it stable (the demo fail/win state). `get_tool_schemas()` exposes `set_enabled` and `set_cooling`.
- [x] Placement (`Placement`, `scripts/world/placement.gd`, node in `World`): Input Map actions (physical-key defaults, layout independent) `select_miner` / `select_smelter` / `select_assembler` / `select_collector` / `select_conveyor` (`1`-`5`), `rotate_placement` (`R`, facing right, down, left, up) and `cancel_placement` (`Esc`) drive it; `Main` forwards them to `Placement.handle_input()`; left click on a grid cell places. Refuses out-of-grid, occupied cells, and miners off a minesite. A Collector is placed at the map center on start. Machines unregister themselves from `GameState` when freed. `Placement.select(type)` / `place(type, cell)` are the hooks for the Bar's BuildPage (track C).
- Prototype conveyor controls: trigger `select_conveyor` (`5`) to select a conveyor, `rotate_placement` (`R`) to rotate its output direction clockwise, then left-click a free grid cell to place it. The direction and whether it holds an item are shown in its status label. The BuildPage is not wired to placement yet.
- Not done: no way to remove or rebuild a machine (an exploded smelter stays), no money cost for building, the hover highlight does not show the minesite rule, no tooltip or chip wiring (Phase 2).

### Grid and camera (track B, done)
- [x] `GridMap2D` (`scripts/world/grid_map_2d.gd`, `TileMapLayer` in `World`): ground and minesite tiles from `data/tilesets/factory_tileset.tres` (100 px atlas tiles, layer scaled to `CELL_SIZE` 64), hover highlight (green/red from `GameState.can_place`), signals `cell_hovered(cell)` / `cell_clicked(cell)`, `get_hovered_cell(world_pos)`, `is_minesite(cell)`. Placing machines is still done through `GameState.register_machine`; the minesite rule is not enforced yet.
- [x] `FactoryCamera` (`scripts/world/camera.gd`): wheel zoom at cursor (0.4-2.0), middle-drag / arrow-key pan, clamped to the grid.

### Bar and popups (track C)
- [x] `BarPanel` (`scripts/ui/bar_panel.gd`): one tab per child of `Pages` (title from the node name), Settings button.
- [x] Chip Registry page (`ChipRegistryPage`): list of chips + `new chip` (blank draft, `name = "Blank"`, saved only on Save).
- [x] `ChipPage` popup: edit/save/remove, pauses the game while open. `ChipRegistry.update()` and `EventBus.chip_updated` were added for it.
- [x] `MachineTooltip`: id, type, state, chips (prompt preview, timeout in ticks, remove), add chip from the registry, Log button. Opens through `EventBus.machine_selected`, which `main.gd` emits on `GridMap2D.cell_clicked`; a second click or an empty cell closes it.
- [x] `ChipLog` (last 200 lines per machine from `chip_log_added`) and `SettingsDialog` (key, provider, model).
- [ ] Build page: blocked, no buildable machine or cost exists yet.
- [ ] Tooltip "current action" line (production rate, consumed resource, time remaining): blocked until machine subclasses expose it.

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
