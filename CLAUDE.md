# Promptorio — CLAUDE.md

Godot 4 (GDScript) 2D Factorio-like. Every machine has an "AI chip" whose behavior is defined by a player-written system prompt. The engine sends machine state (JSON) to an LLM asynchronously; the LLM answers with tool calls that control the machine.

48h hackathon, 2-3 devs. Prefer simple, working and demoable over general and elegant. No speculative abstractions.

Roadmap, phases, decisions and risks: see `docs/PLAN.md`. Read it before starting a task and keep it updated (tick completed items, record changed decisions).

## Scope (MVP)
- Machines: Miner -> Smelter -> Assembler. Conveyors are plain, hardcoded logic (AI on conveyors is post-MVP).
- One AI-controllable loop with a visible win/fail state (e.g. smelter overheats and explodes).
- Prompt editor UI per machine, API-key settings UI, a log of chip decisions.

## Architecture

### Autoloads (singletons)
- `LLMManager` (`scripts/llm/llm_manager.gd`): the only code allowed to do HTTP. Queue, concurrency cap, timeouts, retries.
- `GameState` (`scripts/core/game_state.gd`): grid, machine registry, tick clock, resources.
- `Settings` (`scripts/core/settings.gd`): API key, provider, model, cooldowns. Persisted via `ConfigFile` in `user://settings.cfg`.
- `EventBus` (`scripts/core/event_bus.gd`): global signals only. No logic.

### Scene / node layout
```
Main (Node2D)
├─ World (Node2D)
│  ├─ GridMap2D        (TileMapLayer for ground + placement validation)
│  └─ Machines (Node2D) (children are Machine scenes)
├─ UI (CanvasLayer)
│  ├─ BuildBar, PromptEditor (popup), ChipLog, SettingsDialog
└─ Camera2D
```
Machine scene (`scenes/machines/machine.tscn`, base; Miner/Smelter/Assembler inherit it):
```
Machine (Node2D, machine.gd)
├─ Sprite2D
├─ ChipComponent (Node, chip_component.gd)   # prompt, triggers, cooldown, pending flag
└─ Label / ProgressBar (status)
```

### LLM adapter (provider-agnostic)
- `LLMProvider` (base class, `scripts/llm/providers/llm_provider.gd`) defines:
  - `build_request(system_prompt: String, state: Dictionary, tools: Array) -> Dictionary` returns `{url, headers, body}`
  - `parse_response(body: Dictionary) -> Array[Dictionary]` returns a normalized list of `{name, args}` tool calls
- Implementations: `AnthropicProvider` first; `OpenAICompatProvider` second if time allows. Nothing outside `scripts/llm/providers/` knows provider formats.
- Machines expose their tool schemas via `get_tool_schemas()` (e.g. `set_speed(value: 0..1)`, `set_cooling(on: bool)`). `apply_tool_call(name, args)` is the only way LLM output touches a machine.

### Chip triggers
`ChipComponent` requests a decision on: fixed timer, state threshold (temp > X), events (input empty / output full / error), manual "Ask chip now" button. All go through one method, `request_decision(reason: String)`, which enforces the per-chip cooldown and the "one request in flight per chip" rule.

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
scenes/   machines/, ui/, world/
scripts/  core/, llm/ (providers/), machines/, ui/
data/     machine and recipe resources (.tres)
assets/   art, audio
```

## Workflow
- Branch per feature, small commits (conventional commits, e.g. `feat(llm): add queue`). Don't commit directly to `main` for features. Never commit `.env` or keys.
- Don't edit `project.godot` or `.tscn` by hand unless necessary. If you must, keep changes minimal. Scenes merge badly, so tell the team which scene you're touching.
- Before saying a task is done, run the project headless if possible (`godot --headless --quit`) to catch parse errors, and say if something was not run or tested.
- When unsure about an architecture decision, ask rather than inventing a new pattern.
