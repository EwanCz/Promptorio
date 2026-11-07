# Promptorio — 48h MVP Plan

Living document. Update it when scope or decisions change, and tick items off as they land.

## Decisions
- **LLM:** provider-agnostic adapter (`LLMProvider`). Anthropic first, OpenAI-compatible if time allows, plus a mock provider.
- **API key:** player-entered in a settings UI, stored in `user://settings.cfg`. A dev can also put it in a git-ignored `.env` at the project root (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, see `.env.example`). The key saved from the dialog wins, `.env` is the fallback. `.env` is only read by the editor build (`OS.has_feature("editor")`), never saved to `settings.cfg`, never shown in the dialog, never exported or committed.
- **Chip triggers:** fixed timer, state thresholds, events (input empty / output full / error), and a manual "Ask chip now" button.
- **Chips and prompts:** a machine can have several chips. Each chip has exactly one prompt and its own timeout, cooldown and in-flight slot, so chips never compete with each other.
- **Simulation clock:** physics-driven, with elapsed-time catch-up at 10 Hz; paused time is excluded.
- **Prototype build economy:** start with 100 money. Build costs: Miner 20, Smelter 30, Assembler 40, Conveyor 2. The map-center Collector is free and fixed. Charge only after a valid placement; removing a machine gives no refund.
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
- `Settings`: `api_key`, `provider` (`"mock"` for now), `model`, `max_concurrency`, `request_timeout`, `chip_cooldown`, `max_tokens`, `save_settings()`. Keys: `get_api_key(provider)` is the key the game sends (saved key, else `.env`), `get_saved_api_key(provider)` only the dialog one, `get_key_source(provider)` is `"settings"`, `".env"` or `""`. `load_env()` reads `env_path` (default `res://.env`) at startup in the editor.
- Tests: `tests/run.sh [filter]` runs every `tests/test_*.gd` headless (~15 s, exit 1 on failure). How to write tests: see "Testing" in `CLAUDE.md`.
- Headless gotcha: after adding a new `class_name` script, run `godot --headless --import` once to refresh the class cache, otherwise it fails to parse. `godot --headless --quit` still errors until a main scene exists.

### Machine / chip API
- `Machine` (`scripts/machines/machine.gd`): `get_tool_schemas()` (the shared tools, then the type's own `_own_tool_schemas()`), `get_state() -> Dictionary` (compact: `type`, `enabled`, `status`, plus subclass fields), `apply_tool_call(name, args) -> bool` (whitelists the name, requires every schema arg, type-checks and clamps, then calls the `_apply()` override), `log_chip(message)` (emits `chip_log_added`). Shared tool: `set_enabled(on: bool)`. Every subclass overrides `_own_tool_schemas()` with tools unique to its type (names never clash with the shared ones) and handles them in `_apply`: Miner `set_mine_ticks(ticks 5..100)`, Smelter `set_cooling(on)`, Assembler `set_stock_limit(limit 1..10)`, Conveyor `set_direction(direction 0..3: right, down, left, up)`, Collector `set_accepting(on)`. `get_state()` shows the value each tool changes. `status` is `Machine.Status` (`NORMAL`, `DOWN`, `OVERHEATING`).
- `ChipRessource` (`scripts/chip/chip_ressource.gd`, a `Resource`, pure data): `id`, `name`, `description`, `prompt`.
- `ChipRegistry` (autoload, `scripts/chip/chip_registry.gd`): `add(name, prompt, desc = "") -> ChipRessource` (null if the name is empty or taken), `remove(id) -> bool`, `get_from_id(id)`, `get_all()`. Emits `EventBus.chip_registered/chip_removed`.
- `ChipComponent` (`scripts/chip/chip_component.gd`, a `Node`, child of the `Machine`): holds a `ChipRessource` (`chip`), `timeout` (ticks between timer calls, `set_timeout()`), `pending`. `call_llm(reason) -> bool` asks the LLM (named `call_llm` because `Object.call` is native); cooldown (`Settings.chip_cooldown`) and one request in flight apply per chip. The answer goes through `Machine.apply_tool_call`; signal `decision_applied(reason, applied)`. Triggers: timer (`timeout` ticks), event (a name from `Machine.get_events()` that was not there on the previous tick, such as `error`, `output_full`, `input_empty`), threshold (`set_threshold(state_key, value)`: a numeric state value rising above `value`) and manual (`call_llm("manual")`, the tooltip's "Ask now"). Events and thresholds fire on the crossing only. A trigger dropped by the cooldown or an in-flight request is not queued, the timer is the fallback. The reason (`timer`, `event:<name>`, `threshold:<key>`, `manual`) is passed to `decision_applied` and logged.
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
- [x] Real HTTP path tested offline (`tests/test_llm_http.gd`): timeout, transport failure, non-200, invalid JSON, 429 backoff and cap. Seam: `LLMManager._send(request)` is the only code that touches `HTTPRequest`; tests subclass it (`tests/support/scripted_llm_manager.gd`) and also override `_wait_backoff(seconds)` to record the requested retry delays (1 s, 2 s, 4 s) without waiting.

### Simulation (track B, done)
- [x] Chain Miner -> Smelter -> Assembler -> Collector over plain `Conveyor`s, driven by `EventBus.tick_fired`. `Machine` gained `facing`, `receive(item) -> bool` (default refuses), `_tick()` (override per type, skipped while `DOWN`) and `_push(item)` (hands an item to the machine in front). Items are strings: `ore` -> `ingot` -> `part`.
- [x] `Miner`: 1 ore / `mine_ticks` (20), stalls while its output is blocked. `CraftMachine` (base of `Smelter` and `Assembler`): per-item input stock capped at 10, `Recipe` resource (`data/recipes/smelt.tres`: 1 ore -> ingot in 20 ticks; `assemble.tres`: 2 ingots -> part in 30 ticks), blocked output stalls it. `Collector` accepts everything and sells it (`PRICES`: ore 1, ingot 3, part 10; hardcoded, marked `shortcut:`). `Conveyor` holds one item and moves it on after 5 ticks.
- [x] Conveyor behavior: a conveyor is an ordinary placed machine with a facing direction. On each 10 Hz simulation tick it advances its held item; after 5 ticks it tries to deliver that item to the machine in the adjacent cell it faces. If the cell is empty or the machine refuses the item, it keeps the item and retries on later ticks. A conveyor accepts only one item at a time. Machines can also pass items directly to an adjacent machine, so conveyors are optional links rather than automatic belts between every machine.
- [x] Smelter temperature: working +0.6/tick, idle -0.3/tick, `set_cooling(on)` an extra -0.7/tick, floor 20. `OVERHEATING` at 100 (back to `NORMAL` at 80), explodes at 150: `DOWN`, stock lost, `EventBus.machine_exploded`, then a 0.6 s flash, fade and spark burst, after which the smelter is destroyed and its cell is free (the player has to rebuild it). The art reddens from 60° (white) to fully red at 150° (`Smelter._update_heat_tint`). Without a chip a busy smelter explodes after ~22 s; `set_cooling(true)` or `set_enabled(false)` keeps it stable (the demo fail/win state). `get_tool_schemas()` exposes `set_enabled` and `set_cooling`.
- [x] Placement (`Placement`, `scripts/world/placement.gd`, node in `World`): Input Map actions (physical-key defaults, layout independent) `select_miner` / `select_smelter` / `select_assembler` / `select_conveyor` (`1`, `2`, `3`, `5`), `rotate_placement` (`R`, facing right, down, left, up) and `cancel_placement` (`Esc`) drive it; `Main` forwards them to `Placement.handle_input()`; left click on a grid cell places. Refuses out-of-grid, occupied cells, and miners off a minesite. The Collector is placed at the map center on start and is not selectable: no action, no Build page entry, and `select` / `try_place` refuse it. Machines unregister themselves from `GameState` when freed. `Placement.select(type)` is what both the shortcuts and the Build page call; `place(type, cell)` applies the rules without cost and `try_place(type, cell)` adds the `COSTS` charge (once, only on success; emits `placement_rejected(reason)` otherwise).
- Head-on rule: two machines facing each other (`target.facing == -facing`) pass nothing to one another, in either direction (`Machine._push`), e.g. a smelter facing a conveyor that points back at it: both stay blocked until one is turned. The Collector has no facing and never counts. Test: `tests/test_simulation.gd`.
- Prototype conveyor controls: trigger `select_conveyor` (`5`) to select a conveyor, `rotate_placement` (`R`) to rotate its output direction clockwise, then left-click a free grid cell to place it. The direction is shown by the belt art and the tooltip (no arrow label over the machine); the status label is only a dot while it holds an item. No machine shows its name over it any more: the label is empty except the smelter temperature / BOOM and the conveyor dot. The Build page selects the same types through `Placement.select`.
- Paid placement, machine removal/rotation, the Build page and the tooltip actions are track C and are done (see "Bar and popups" below). The hover highlight still does not show the minesite rule; chip-to-LLM wiring remains in Phase 2.

### AI tool inventory (as implemented)
What `get_tool_schemas()` returns today. Only `Machine` (base) and `Smelter` define tools; `Miner`, `Assembler`, `Conveyor` and `Collector` add none. Every argument is required, and a missing or wrongly typed value rejects the whole call (logged to the ChipLog, machine unchanged). A chip can be attached to any machine, including a conveyor or the Collector, so every machine type is listed.

| Tool | Args | Origin | Effect |
|------|------|--------|--------|
| `set_enabled` | `on: boolean` | inherited from `Machine`, on every machine | Sets `enabled` (reported as `enabled` in the state sent to the LLM). See the per-machine effect below. |
| `set_cooling` | `on: boolean` | `Smelter` only | Sets `cooling`: an extra -0.7 °/tick (see Smelter temperature above). Reported as `temperature` and `cooling` in the state. |

| Machine | Tools | What `set_enabled(false)` does |
|---------|-------|--------------------------------|
| Miner | `set_enabled` | Stops mining progress. An ore already held is still pushed on. |
| Smelter | `set_enabled`, `set_cooling` | Starts no new craft and pauses a running one (progress is kept, `true` resumes it). A finished output is still pushed on and input is still accepted. It counts as idle, so it cools -0.3/tick. |
| Assembler | `set_enabled` | Same as the Smelter without the temperature. |
| Conveyor | `set_enabled` | Nothing. `enabled` is stored and reported, but conveyor logic never reads it, so it keeps moving items. |
| Collector | `set_enabled` | Nothing. Same as the Conveyor; it keeps selling. |

Design gaps:
- No tool takes a number or an integer yet (the `number`/`integer` clamping in `apply_tool_call` is only exercised by a test machine). No speed, recipe or rotation control exists for the LLM.
- `set_enabled` is a no-op on `Conveyor` and `Collector`, yet it is advertised to their chips. Either hide it there or give `enabled` a meaning (also an open question: conveyor AI is post-MVP).
- The Assembler has no machine-specific control, so an assembler chip can only switch it on and off.
- `get_state()` sends `type`, `enabled`, `status` plus per-type fields; there is no tool to read more.

### Grid and camera (track B, done)
- [x] `GridMap2D` (`scripts/world/grid_map_2d.gd`, `TileMapLayer` in `World`): ground and minesite tiles from `data/tilesets/factory_tileset.tres` (100 px atlas tiles, layer scaled to `CELL_SIZE` 64), hover highlight (green/red from `GameState.can_place`), signals `cell_hovered(cell)` / `cell_clicked(cell)`, `get_hovered_cell(world_pos)`, `is_minesite(cell)`. Placement (`Placement`, see Simulation below) enforces bounds, occupancy and the minesite rule for miners through `GameState.can_place` and `is_minesite`.
- [x] `FactoryCamera` (`scripts/world/camera.gd`): wheel zoom at cursor (0.4-2.0), middle-drag / arrow-key pan, clamped to the grid.

### Bar and popups (track C)
- [x] `BarPanel` (`scripts/ui/bar_panel.gd`): one tab per child of `Pages` (title from the node name), Settings button.
- [x] Chip Registry page (`ChipRegistryPage`): list of chips + `new chip` (blank draft, `name = "Blank"`, saved only on Save).
- [x] `ChipPage` popup: edit/save/remove, pauses the game while open. `ChipRegistry.update()` and `EventBus.chip_updated` were added for it.
- [x] `MachineTooltip`: id, type, state, chips (prompt preview, timeout in ticks, remove), add chip from the registry, Log button. Opens through `EventBus.machine_selected`, which `main.gd` emits on `GridMap2D.cell_clicked`; a second click or an empty cell closes it.
- [x] `ChipLog` (last 200 lines per machine from `chip_log_added`) and `SettingsDialog` (key, provider, model).
- [x] Build page: list Miner / Smelter / Assembler / Conveyor and their prices; show current money and disable unaffordable choices. Selecting a machine enters placement mode; valid placement charges once, invalid placement charges nothing. The fixed map-center Collector is not buildable.
- [x] Machine interaction: tooltip can rotate a placed output machine and remove a placed machine. Removal unregisters/frees the machine, discards its stock and attached chips, frees its cell, and gives no refund. The fixed Collector cannot be removed. Rebuilding uses the normal price and placement validation. `R` (`rotate_placement`) also rotates the machine whose tooltip is open: one press turns both it and the next placement (`MachineTooltip.rotate_machine()`, called from `Main`).
- [x] Tooltip current action: Miner production rate and blocked output; CraftMachine recipe, stock, progress/time remaining and blocked output; Conveyor facing and held item; Collector sales. Smelter also shows temperature/cooling. State is shown separately as normal/down/overheating.
- [x] Build/machine action feedback: selected build type is visible, placement mode can be canceled with Escape, invalid placement and insufficient money are communicated, and machine tooltip actions do not click through to the world.

## Phase 2 — Integration (h20–32)
- [x] `ChipComponent` wired to `LLMManager`: timer, threshold, event and manual triggers, per-chip cooldown, one request in flight per chip (`tests/test_chip_triggers.gd`). The tooltip has an "Ask now" button and an "Ask when <state value> > <limit>" picker per chip.
- [x] Each machine exposes `get_tool_schemas()` and `apply_tool_call()` (validates and clamps all LLM args): the shared `set_enabled` plus one tool unique to its type (see "Machine / chip API"). Checked per type in `tests/test_machine_tools.gd` and on all five machine scenes in `tests/test_chip_integration.gd`.
- [x] Full loop on the mock provider: Miner -> Conveyor -> Smelter (with a chip) -> Conveyor -> Collector, chip timer -> `LLMManager` -> tool call -> machine, items still sold (`tests/test_chip_integration.gd`).
- [x] Full loop on the real API, system side: the key comes from the Settings dialog or `.env` (`Settings.get_api_key`, used by `AnthropicProvider` and `CodexProvider`). Without a key a request fails at once with `no API key (set one in Settings or .env)` and sends nothing. A non-200 reply is reported as `HTTP <status> (<error type>)` (the API's message is dropped, it may echo part of the key) and shows in the chip log as `chip request failed: ...`; the machine keeps its last settings. Tested offline end to end through the Anthropic wire format in `tests/test_real_api_loop.gd` (the `LLMManager` autoload runs the scripted test double for each test).

## Phase 3 — Game feel and demo (h32–42)
- [ ] Demo scenario with a visible win and fail state (bad prompt -> smelter explodes, good prompt -> stable)
- [x] Machine art (`assets/tiles/`, 16 px pixel art drawn at x4 = one 64 px cell, nearest filter). `Machine` has `front_texture` / `back_texture` exports and a `facing` setter that redraws: the front art for every facing, the back art while facing up if the machine has one. Smelter and Assembler have both (`smelter_front/back`, `assembler_front/back`), Miner (`miner`) and Collector (`collector_front`) one view. Smelter and Assembler set `turn_front_sideways`: facing left or right turns the front art a quarter turn so its doorway points the way the machine outputs (the sprite is moved back over its cell; no side art exists). Miner and Collector keep their one upright view. Conveyor: `up_texture` (`convoyer_up4`) and `side_texture` (`convoyer_side1`) with `flip_h` for left and `flip_v` for down; its frame stays still and the `Belt` sprite scrolls the surface 2 px per tick from the tick number, so all belts stay in phase and the scroll comes back to its first pose every 4 ticks (the art repeats every 8 px; `tests/test_machine_art.gd` checks that). Unused art (left in `assets/Tiles/`): `convoyer_up1/2/3/5`, `convoyer_side2/3` (end caps and half-step variants), `blue_front`. Scenes touched: `machine.tscn` (base sprite, now empty until `_ready`) and the five machine scenes.
- [ ] Chip activity feedback: "thinking…" indicator, decision bubbles
- [ ] 2-3 example prompts for first-time players

## Phase 4 — Polish (h42–48)
- [ ] Bug fixes and graceful API-failure handling
- [ ] Build/export test, and check that no key is baked into the export (`.env` must not be in the export filter)
- [ ] README and demo rehearsal

## Risks and mitigations
1. **Latency or rate limits during the demo:** mock provider, per-chip cooldown, small fast model.
2. **Malformed or unsafe LLM output:** whitelist and clamp in `apply_tool_call`. A failed call leaves the machine on its last settings.
3. **Scene merge conflicts:** each dev owns different scenes, and the base `Machine` scene is frozen after Phase 0.
