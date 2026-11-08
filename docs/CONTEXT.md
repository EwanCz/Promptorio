# Promptorio

Godot 4 (GDScript) 2D Factorio-like. Every machine has an "AI chip" whose behavior is defined by a player-written system prompt. The engine sends machine state (JSON) to an LLM asynchronously; the LLM answers with tool calls that control the machine.

48h hackathon, 2-3 devs. Prefer simple, working and demoable over general and elegant. No speculative abstractions.

Read `docs/PLAN.md` for project goals, decisions and risks, and the relevant issue for task status, whether it is in GitHub, Superflix or another tracker. Update the relevant issue as work progresses when the tracker is accessible; update the plan when goals or decisions change. Keep implemented behavior documented alongside the code; `docs/IMPLEMENTATION.md` is a historical reference, not a task tracker.

## Scope (MVP)
- Machines: Miner -> Smelter -> Assembler -> Collector. Conveyors are plain, hardcoded logic (AI on conveyors is post-MVP). In the current prototype, select a conveyor with the `select_conveyor` action (default `5`), rotate its direction with `rotate_placement` (default `R`), and place it with a left click on an empty grid cell. It holds one item and attempts to deliver it to the adjacent machine in its facing direction every five 10 Hz ticks; a blocked delivery stays on the conveyor. Adjacent machines can also pass items directly, without a conveyor.
- Items: (Coal/Silver/Redstone/etc...). They are the resource catalog (`ItemCatalog`, `data/items.tres`, table in `docs/IMPLEMENTATION.md` "Resources"): each has a price, one machine type that builds it and its inputs; the Resources popup (Bar button) lists them all.
  - Fuze them in a Assembler which take one or more different ressources.
  - Each assembler take any ressources with a max stock size in each assembler. Any resource can be stored in any smelter/assembler, needed or not; only the `discard_stock` tool removes it.
  - The IA will be prompted the ressource to build then will by itself check in the stockage if can be built. If the ressource can be made. Consume them then start a assemble event on for the ressource be build.
  - Ressources are spawned from a miner on the map it will then be transfer via the conveyor to tranform them in smelter/assembler or directly to a collector to sell them.
- AI-controllable loop in each machine.
  - A machine can have multiple AI chips. Each chip is its own brain: it has exactly one prompt and its own timeout (ex: a maintenance chip, a production chip).
  - Each chip is defined in the chip registry (`ChipRegistry`): name, description and its prompt text. A machine's `ChipComponent` runs a chip taken from it.
- Chip editor with option to create/update/remove chips in the registry (Chip Registry page + Chip Page popup, see `docs/UI.md`).
- UI information on click per machine (Machine tooltip: a panel in the bottom half of the Bar, see `docs/UI.md`).

## Architecture

### Autoloads (singletons)
- `LLMManager` (`scripts/llm/llm_manager.gd`): the only code allowed to do HTTP. Queue, concurrency cap, timeouts, retries.
- `GameState` (`scripts/core/game_state/`): grid, machine registry, tick clock, resources.
- `Settings` (`scripts/core/settings.gd`): API key, provider, model, cooldowns, and audio (`master_volume` 0.8, `sfx_volume` 1.0, both 0..1, and `muted`, in the `[audio]` section; clamped on load; `apply_audio()` pushes them to the buses). Persisted via `ConfigFile` in `user://settings.cfg`.
- `EventBus` (`scripts/core/event_bus.gd`): global signals only. No logic.

### Scene / node layout
The project starts on the main menu (`scenes/menu/main_menu.tscn`: Play, Load Game, Chips, Options, Exit, see `docs/UI.md`), which switches to `scenes/main.tscn` below. `GameState` survives scene changes, so a new game calls `GameState.reset()` first; a save picked in the menu waits in `SaveGame.pending` until `Main` restores it.
Screen split (see `docs/UI.md`): Factory View 80% left, Bar 20% right. The world is rendered in a `SubViewport` so the camera and the 80% region stay independent of the UI.
```
Main (Node)
├─ Game (HBoxContainer, full rect)
│  ├─ FactoryView (SubViewportContainer, stretch, size_flags_stretch_ratio 4)
│  │  └─ SubViewport
│  │     └─ World (Node2D)
│  │        ├─ GridMap2D        (TileMapLayer: ground, minesites, placement validation)
│  │        ├─ Machines (Node2D) (children are Machine scenes; Collector at map center; conveyors are placed as Machine scenes)
│  │        └─ Camera2D          (zoom in/out, pan x/y; camera.gd)
│  └─ Bar (PanelContainer, size_flags_stretch_ratio 1)
│     └─ VBoxContainer
│        ├─ KeyStatus (API key state as key icon + badge, hidden for mock)
│        ├─ OrderStatus (current order: resource icon, progress "N/M", reward coin + amount)
│        ├─ TopHalf (VBoxContainer, top half of the Bar)
│        │  ├─ PageTabs (HFlowContainer of page markers at the top)
│        │  └─ PageScroll (ScrollContainer)
│        │     └─ Pages (MarginContainer, only one page visible)
│        │        ├─ BuildPage          (list of buildable machines + money cost)
│        │        └─ ChipRegistryPage (list of chip names, "new chip" button on top)
│        ├─ MachineTooltip (PanelContainer, bottom half of the Bar: selected machine info, scrollable)
│        └─ BarButtons (HBoxContainer, far bottom, right-aligned: Menu, Resources, Save / Load, Settings icon buttons)
└─ UI (CanvasLayer, popups over everything)
   ├─ ChipPage        (popup, centered; name, description, message; edit/save/remove)
   ├─ ChipLog         (icon timeline opened from the machine panel)
   ├─ ResourcesPage   (popup, every resource: machine, needs, ticks, price)
   ├─ ToolsPage       (popup, every tool of every machine type)
   ├─ SaveDialog      (save slots, import/export a save file; pauses the game)
   ├─ PauseMenu       (Resume / Restart / Main Menu; pauses the game; Bar "Menu" button or Escape)
   └─ SettingsDialog
```
UI rules:
- UI is `Control` nodes only, laid out with anchors and Containers (`HBox/VBox/Margin`), never hand-placed pixels. One shared `Theme` resource on the root.
- Opening `ChipPage` pauses the game (`get_tree().paused = true`, popup `process_mode = PROCESS_MODE_ALWAYS`). Closing resumes it.
- `MachineTooltip` shows: machine id, type, connected chips with their prompt and timeout, "add chip" (picks a chip from the registry), "log" button, current action (miner: production rate; smelter/assembler: consumed resource and time remaining), state (normal/down/overheating).
- Chips live in a registry (`ChipRegistry` `Resource`, saved as `.tres`; each chip holds its name, description and prompt text). `Bar`, `ChipPage` and the tooltip read and write it; none of them talk to `LLMManager`.
- A chip is a `Resource`. A machine's chip holds a reference to the same chip resource stored in the registry, not a copy. Editing a chip in the registry updates every connected chip at once.
- Player edits are saved to `user://chip_registry.tres`. The default registry ships in `data/chip_registry.tres` (`res://` is read-only in exported builds) and is loaded only when no user copy exists.
- UI reads machine state through `GameState` and `EventBus` signals (calls down, signals up). Mouse input on the Bar uses `mouse_filter` so clicks never reach the map beneath, and map clicks only count inside `FactoryView`.

Machine scene (`scenes/machines/machine.tscn`, base; Miner/Smelter/Assembler inherit it):
```
Machine (Node2D, machine.gd)
├─ Sprite2D
├─ ChipComponent (Node, chip_component.gd)   # one per chip (a machine can have several): one prompt, timeout, triggers, cooldown, pending flag
└─ Label / ProgressBar (status)
```

### LLM adapter (provider-agnostic)
- `LLMProvider` (base class, `scripts/llm/providers/llm_provider.gd`) defines:
  - `build_request(system_prompt: String, state: Dictionary, tools: Array) -> Dictionary` returns `{url, headers, body}`
  - `parse_response(body: Dictionary) -> Array[Dictionary]` returns a normalized list of `{name, args}` tool calls
  - `build_check_request()` returns the free key-check GET (list models), and `config_error()` returns a message when the provider's relay base URL is unusable (see "Provider base URL")
- Implementations: `AnthropicProvider` (Messages API), `OpenAIProvider` (Responses API) and `MockProvider` (offline, deterministic). `Settings.provider` is `mock`, `anthropic` or `openai`. Nothing outside `scripts/llm/providers/` knows provider formats. Neither real provider has been run against its live API: tests use scripted responses.
- Machines expose their tool schemas via `get_tool_schemas()` (the shared `set_enabled(on: bool)` plus one tool per machine type, e.g. `set_mine_ticks(ticks: mining time of the resource..100)` on the Miner and `set_cooling(on: bool)` on the Smelter; a reference list is in `docs/IMPLEMENTATION.md`, "AI tool inventory"). `apply_tool_call(name, args)` is the only way LLM output touches a machine.

### Chip triggers
Each `ChipComponent` (one chip, one prompt) requests a decision on exactly two triggers: its fixed timer and the manual "Ask now" button. A machine's state or events (temperature, OVERHEATING, error, output full, input empty) never wake a chip; temperature and status are only sent in the state when the chip is asked. All go through one method, `request_decision(reason: String)`, which enforces the per-chip cooldown and the "one request in flight per chip" rule.

## Async HTTP rules (CRITICAL)
1. Never block the main thread. No `OS.delay_*`, no polling loops with `HTTPClient.poll()` in `_process`, no synchronous waits.
2. Use `HTTPRequest` nodes + `await`. One `HTTPRequest` node can only run one request at a time, so `LLMManager` keeps a small pool (default 4). Each in-flight request gets its own node. Never share a node between concurrent requests.
3. Always set `request.timeout` (default 20s). Handle every result: `RESULT_SUCCESS` plus non-200 status, timeouts, JSON parse failures. Failure must never crash or stall a machine; the machine keeps running on its last-known settings.
4. Queue requests when the pool is full. Respect `Settings.max_concurrency` and handle HTTP 429 with exponential backoff (cap 3 retries). Drop the oldest queued request for a chip if it enqueues a newer one (state goes stale fast).
5. One in-flight request per chip (`ChipComponent.pending`). Triggers that fire while pending are ignored, not queued.
6. After every `await`, re-validate: `is_instance_valid(machine)`, and `machine.is_inside_tree()`. Machines can be deleted while a request is in flight.
7. Never trust LLM output. Parse with `JSON.parse_string`, check the type, whitelist tool names against `get_tool_schemas()`, validate and clamp every argument. Ignore unknown calls and log them to the ChipLog.
8. Communicate through signals (`decision_received`, `decision_failed`), not by returning values across frames. UI never calls HTTP directly.
9. Send compact state JSON (only fields the chip needs). Keep `max_tokens` small (<= 300). Offer tools with automatic choice so the model can return no tool calls when the prompt says to do nothing.
10. Secrets: the API key comes only from `Settings` (player-entered in UI, or a dev `.env` read by `Settings` in the editor). Never hardcode, log, or print it. `.env` is dev-only and must stay out of git and out of exports. Check `.gitignore` before committing.
11. Add a `mock` provider (canned responses, random latency) so the game and UI can be developed and demoed with no network or key.

### Provider base URL (relay)
Requests go to the official endpoint (`https://api.anthropic.com`, `https://api.openai.com`) unless a relay origin is configured for that provider. Resolution order (`Settings.get_base_url(provider)`): the Base URL saved from the Settings dialog (`user://settings.cfg`, any build), then the `ANTHROPIC_BASE_URL` / `OPENAI_BASE_URL` process variable, then the same variable in `.env`. The last two apply in editor runs only; exported builds ignore them. Blank means the official endpoint. Each provider has its own value.
- The value is an https origin (`https://relay.example.com`, optional port): no path, query, credentials or IPv6 literal. Trailing slashes are trimmed, then the provider's paths are appended: `/v1/messages` and `/v1/models?limit=1` (Anthropic chat and key check), `/v1/responses` and `/v1/models` (OpenAI).
- `LLMProvider.config_error()` rejects anything else, so `LLMManager` fails the request (or the key check reports "could not verify") before sending, and the key never goes to a malformed or plain-http target. The message does not repeat the value. The URL is never logged.
- Settings saved before the rename of `codex` to `openai` still load: `codex_api_key`, `codex_model` and `provider = codex` are migrated.

### LLM diagnostics (opt-in, local)
By default a failed HTTP call reaches the ChipLog as `HTTP <status> (<error type>)` only, because a provider's message can echo part of the key. To see the message while debugging, launch the editor (or the project from it) with `PROMPTORIO_DEBUG_LLM=1`, e.g. `PROMPTORIO_DEBUG_LLM=1 godot --editor`; the log line becomes `HTTP 400 (invalid_request_error): <message>`.
- Limits: only the exact value `1` enables it, and only when `OS.has_feature("editor")`, so exported builds ignore it. It adds the provider's error `message` for non-200 answers and nothing else; no headers, request body or raw response body is ever logged, and a non-JSON body adds nothing.
- The message is made one line, the configured API key and any 20+ character token-like run are replaced by `[redacted]`, and it is cut at 200 characters (`...` marks the cut). The token mask is a heuristic (`shortcut:`): it can hide a long identifier and cannot catch a key shorter than 20 characters that is not the configured one.

### Save files
`SaveGame` (`scripts/core/save_game.gd`, static functions, no autoload) saves and restores the whole game as one JSON file (`version` 1). Slots live in `saves/` at the project root in an editor run (so a save can be committed and shared) and in `user://saves/` in an exported build (`SaveGame.default_save_dir()`); Import / Export in the `SaveDialog` popup reach any file. A file is never trusted: `SaveGame.validate()` checks the whole structure before anything is touched, and each machine clamps its own values in `_load_data()`. Machines add their state by overriding `_save_data()` / `_load_data()` (use the `_read_int` / `_read_float` / `_read_item` helpers). The save embeds the chips its machines use; loading overwrites a registry chip with the same id.

### Session log (local)
`SessionLog` appends every machine log line to `user://logs/session_<date>_<time>.log` (`time | #id type | message`), flushing each line. Only the message text is written (no request bodies or headers) and configured API keys are replaced by `[redacted]`. It is started by `Main`, skipped in headless runs, and does not change the ChipLog's 200-line cap.

### Visual feedback (UI rule)
Runtime status is an icon, not text: chip activity above each machine (`ChipIndicator`, owned by `Machine`: spinner while any chip is pending, then check / dash / cross for the last result), machine state in the tooltip, API key state in the Bar, placement refusal on the Build page, and the Chip Log (an icon timeline). Text stays for names, values (money, temperature), prompts, settings and control labels. Icons come from `Icons` (`scripts/ui/icons.gd`, 12x12 pixel art drawn from text grids, nearest filter); a UI icon that is not self-evident gets a hover description (`Icons.rect` / `Icons.apply`), and familiar actions (rotate, destroy, settings, add chip, ask now, log) are icon-only buttons (`Icons.button` / `Icons.apply_button`) with a hover. Technical detail stays in the session log. Details: `docs/UI.md`, "Visual feedback rule". There are no decision bubbles.

## GDScript conventions
- Godot 4.x only. Fully typed GDScript: type every variable, parameter and return (`var speed: float = 1.0`, `func foo(x: int) -> void`).
- Naming: `snake_case` for files, functions, variables; `PascalCase` for `class_name` and nodes; `UPPER_SNAKE` for constants; signals in past tense (`decision_received`); private members prefixed `_`.
- Script order: `class_name`, `extends`, signals, enums, constants, `@export`, public vars, private vars, `@onready`, lifecycle (`_ready`, `_process`), public methods, private methods.
- Prefer signals up, calls down. Use `@export` and `@onready var x: Node = %UniqueName` over hardcoded `get_node` paths.
- Use `Resource` subclasses (`.tres`) for static data (machine definitions, recipes) rather than hardcoded dictionaries.
- Game logic ticks in a fixed-rate simulation (`GameState` tick, default 10 Hz) separate from rendering. Don't put simulation in `_process`.
- Indentation: tabs (see `.editorconfig`). No unused code or commented-out blocks.

## Project layout
```
scenes/   machines/, ui/ (bar, pages, popups), world/
scripts/  core/, llm/ (providers/), machines/, ui/
data/     machine and recipe resources (.tres)
assets/   art, audio
tests/    headless test suite (see Testing)
```

## Testing
Every feature ships with tests, and every bug fix ships with a test that fails without the fix. Run the whole suite before every commit and before saying a task is done.

```
tests/run.sh              # whole suite (refreshes the class cache, exit 1 on any failure)
tests/run.sh llm          # only test files whose name contains "llm"
```
Env: `GODOT` (godot binary, default `godot`), `TEST_TIMEOUT` (seconds, default 120). `TEST_PROFILE=1` prints the slowest files and tests. `TEST_REAL_LATENCY=1` keeps the mock provider's real 0.3-1.5 s answer delay: by default the runner swaps in `tests/support/fast_mock_llm_manager.gd` (0.01-0.05 s, still an asynchronous timer), which cuts the suite from ~31 s to ~7 s. The production manager's own provider choice (and the mock's 0.3-1.5 s latency) is still covered in the default suite by `test_production_manager_picks_the_unmodified_mock_provider` and `test_mock_provider.gd`. Don't count on the mock's real latency in a test; hold a chip pending by hand when you need it to stay pending.

### Writing a test
- One file per feature: `tests/test_<feature>.gd`, starting with `extends "res://tests/test_case.gd"`. The runner finds it automatically.
- Every method named `test_*` is a test. It may `await` (coroutines are fine). Optional `before_each()` / `after_each()` hooks do setup and cleanup.
- Helpers from `test_case.gd`: `check(cond, label)`, `check_eq(actual, expected, label)`, `autoload("Name")`, `await wait_until(callable, timeout)`, `await wait_seconds(s)`.
- A test with zero checks fails (an aborted test must not look green). `tests/run.sh` also fails on any `SCRIPT ERROR` in the output.
- Example: `tests/test_game_state.gd` (simple), `tests/test_llm_manager.gd` (async with signals).

### Rules and gotchas
- Tests are headless, with no scene and no display. Autoloads are available through `autoload("Name")`; bare identifiers like `GameState` do not compile in test scripts. Test scene-based code by instantiating the scene from code.
- Never use the network or a real API key. Use `Settings.provider = "mock"`.
- Real time only: headless frames are uncapped, so never count frames for timeouts (`wait_until` / `wait_seconds` already use real time).
- Leave no global state behind. Disconnect any signals you connect, restore any `Settings` / `GameState` value you change, and free any node you create (`after_each()`). `test_settings.gd` shows how to back up and restore `user://settings.cfg`.
- Never store a lambda in a member variable of a test (it captures `self`, creating a reference cycle that leaks and prints "ObjectDB instances were leaked" at exit). Use a method for signal handlers, or a local lambda inside the test. A clean run prints no leak warnings.
- Test through public methods and signals, not private `_members`, unless there is no other way (the LLM queue tests read `_in_flight` / `_queue`).
- The map draws random minesites at every start. The runner forces a fixed layout (`GridMap2D.layout_override`, set in `tests/run_tests.gd`), so tests may rely on those cells; a test about the random draw clears it and puts it back.
- New `class_name` scripts need a class-cache refresh; `tests/run.sh` does it, a bare `godot --headless -s` does not.
- The real HTTP path is tested offline by replaying scripted responses through `LLMManager._send()` (`tests/test_llm_http.gd`, `tests/support/scripted_llm_manager.gd`). A real network round-trip is still untested.

## Features

### LLM
The llm system is linked via the `LLMManager`. It stores the providers (`mock`, `anthropic`, `openai`), one `LLMProvider` each.
It help to call the models via a `request_decision` function. It can be take the message + the related tools.
The request_decision get a list of tools to call with arguments. It save the machine which made the chat-call to call the functions related to the machine (ex: prompt ask to make a axe. The llm will ask to call the tool "make" with the param axe on the machine which called it).
> [!Warning]
> Complete

### SIM
Need to build the map by making a x/y grid of square tile where machine can be place on.
Need a tick rate limit to make the game update the ressource position and the machine action completion time. Link to the eventBus.
> [!Warning]
> Complete

### UI
Information in docs/UI.md search any information related to UI in this file.

## Workflow
- Branch per feature, small commits (conventional commits, e.g. `feat(llm): add queue`). Don't commit directly to `main` for features. Never commit `.env` or keys.
- Don't edit `project.godot` or `.tscn` by hand unless necessary. If you must, keep changes minimal. Scenes merge badly, so tell the team which scene you're touching.
- Before saying a task is done, run `tests/run.sh` (and the project headless with `godot --headless --quit` once a main scene exists) to catch parse errors and regressions, and say if something was not run or tested.
- New or changed behavior needs a test in `tests/` in the same commit (see Testing).
- When unsure about an architecture decision, ask rather than inventing a new pattern.
