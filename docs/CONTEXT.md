# Promptorio

Godot 4 (GDScript) 2D Factorio-like. Every machine has an "AI chip" whose behavior is defined by a player-written system prompt. The engine sends machine state (JSON) to an LLM asynchronously; the LLM answers with tool calls that control the machine.

48h hackathon, 2-3 devs. Prefer simple, working and demoable over general and elegant. No speculative abstractions.

Roadmap, phases, decisions and risks: see `docs/PLAN.md`. Read it before starting a task and keep it updated (tick completed items, record changed decisions).

## Scope (MVP)
- Machines: Miner -> Smelter -> Assembler -> Collector. Conveyors are plain, hardcoded logic (AI on conveyors is post-MVP).
- Ressource: (Coal/Silver/Redstone/etc...).
  - Fuze them in a Assembler which take one or more different ressources.
  - Each assembler take any ressources with a max stock size in each assembler.
  - The IA will be prompted the ressource to build then will by itself check in the stockage if can be built. If the ressource can be made. Consume them then start a assemble event on for the ressource be build.
  - Ressources are spawned from a miner on the map it will then be transfer via the conveyor to tranform them in smelter/assembler or directly to a collector to sell them.
- AI-controllable loop in each machine.
  - A machine can have multiple AI chips. Each chip is its own brain: it has exactly one prompt and its own timeout (ex: a maintenance chip, a production chip).
  - Each chip is defined in the chip registry (`ChipRegistry`): name, description and its prompt text. A machine's `ChipComponent` runs a chip taken from it.
- Chip editor with option to create/update/remove chips in the registry (Chip Registry page + Chip Page popup, see `docs/UI.md`).
- UI information on click per machine (Machine tooltip, see `docs/UI.md`).

## Architecture

### Autoloads (singletons)
- `LLMManager` (`scripts/llm/llm_manager.gd`): the only code allowed to do HTTP. Queue, concurrency cap, timeouts, retries.
- `GameState` (`scripts/core/game_state/`): grid, machine registry, tick clock, resources.
- `Settings` (`scripts/core/settings.gd`): API key, provider, model, cooldowns. Persisted via `ConfigFile` in `user://settings.cfg`.
- `EventBus` (`scripts/core/event_bus.gd`): global signals only. No logic.

### Scene / node layout
Screen split (see `docs/UI.md`): Factory View 80% left, Bar 20% right. The world is rendered in a `SubViewport` so the camera and the 80% region stay independent of the UI.
```
Main (Node)
├─ Game (HBoxContainer, full rect)
│  ├─ FactoryView (SubViewportContainer, stretch, size_flags_stretch_ratio 4)
│  │  └─ SubViewport
│  │     └─ World (Node2D)
│  │        ├─ GridMap2D        (TileMapLayer: ground, minesites, placement validation)
│  │        ├─ Machines (Node2D) (children are Machine scenes; Collector at map center)
│  │        └─ Camera2D          (zoom in/out, pan x/y; camera.gd)
│  └─ Bar (PanelContainer, size_flags_stretch_ratio 1)
│     └─ VBoxContainer
│        ├─ PageTabs (TabBar / HBox of page markers at the top)
│        └─ Pages (each page a Control, only one visible)
│           ├─ BuildPage          (list of buildable machines + money cost)
│           └─ ChipRegistryPage (list of chip names, "new chip" button on top)
└─ UI (CanvasLayer, popups over everything)
   ├─ ChipPage        (popup, centered; name, description, message; edit/save/remove)
   ├─ MachineTooltip  (opens on machine click, closes on second click)
   ├─ ChipLog         (log page opened from the tooltip)
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
- Implementations: `AnthropicProvider` first; `OpenAICompatProvider` second if time allows. Nothing outside `scripts/llm/providers/` knows provider formats.
- Machines expose their tool schemas via `get_tool_schemas()` (e.g. `set_speed(value: 0..1)`, `set_cooling(on: bool)`). `apply_tool_call(name, args)` is the only way LLM output touches a machine.

### Chip triggers
Each `ChipComponent` (one chip, one prompt) requests a decision on: fixed timer, state threshold (temp > X), events (input empty / output full / error), manual "Ask chip now" button. All go through one method, `request_decision(reason: String)`, which enforces the per-chip cooldown and the "one request in flight per chip" rule.

## Async HTTP rules (CRITICAL)
1. Never block the main thread. No `OS.delay_*`, no polling loops with `HTTPClient.poll()` in `_process`, no synchronous waits.
2. Use `HTTPRequest` nodes + `await`. One `HTTPRequest` node can only run one request at a time, so `LLMManager` keeps a small pool (default 4). Each in-flight request gets its own node. Never share a node between concurrent requests.
3. Always set `request.timeout` (default 20s). Handle every result: `RESULT_SUCCESS` plus non-200 status, timeouts, JSON parse failures. Failure must never crash or stall a machine; the machine keeps running on its last-known settings.
4. Queue requests when the pool is full. Respect `Settings.max_concurrency` and handle HTTP 429 with exponential backoff (cap 3 retries). Drop the oldest queued request for a chip if it enqueues a newer one (state goes stale fast).
5. One in-flight request per chip (`ChipComponent.pending`). Triggers that fire while pending are ignored, not queued.
6. After every `await`, re-validate: `is_instance_valid(machine)`, and `machine.is_inside_tree()`. Machines can be deleted while a request is in flight.
7. Never trust LLM output. Parse with `JSON.parse_string`, check the type, whitelist tool names against `get_tool_schemas()`, validate and clamp every argument. Ignore unknown calls and log them to the ChipLog.
8. Communicate through signals (`decision_received`, `decision_failed`), not by returning values across frames. UI never calls HTTP directly.
9. Send compact state JSON (only fields the chip needs). Keep `max_tokens` small (<= 300). Always force tool use / structured output.
10. Secrets: the API key comes only from `Settings` (player-entered in UI). Never hardcode, log, or print it. `.env` is dev-only and must stay out of git and out of exports. Check `.gitignore` before committing.
11. Add a `mock` provider (canned responses, random latency) so the game and UI can be developed and demoed with no network or key.

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
Env: `GODOT` (godot binary, default `godot`), `TEST_TIMEOUT` (seconds, default 120).

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
- New `class_name` scripts need a class-cache refresh; `tests/run.sh` does it, a bare `godot --headless -s` does not.
- Not covered yet: the real HTTP path (timeouts, non-200, bad JSON, 429 backoff). Add tests with the `AnthropicProvider`.

## Features

### LLM
The llm system is linked via the `LLMManager`. It store multiple LLMProvider for claude/codex/... .
It help to call the models via a `chat` function. It can be take the message + the related tools.
The chat get a list of tools to call with arguments. It save the machine which made the chat-call to call the functions related to the machine (ex: prompt ask to make a axe. The llm will ask to call the tool "make" with the param axe on the machine which called it).
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
