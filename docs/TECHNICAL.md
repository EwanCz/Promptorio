# Promptorio — Technical overview

How the AI agents of Promptorio work, and how we used AI agents to build it. For the rules every contributor
must follow, see [`CONTEXT.md`](CONTEXT.md) (the async HTTP rules in particular); for the player-facing
behavior, see [`IMPLEMENTATION.md`](IMPLEMENTATION.md).

There are two kinds of agents in this project:

1. **In-game agents**: the "AI chips" that drive machines, and the Orchestrator that manages chips.
2. **Development agents**: the AI agents we used to build the game, coordinated by an orchestrator called superfliX.

## 1. In-game agents

### The decision loop

```
 Machine ── ChipComponent (one per chip) ──► LLMManager (autoload) ──► LLMProvider ──► model
    ▲              │  timer or "Ask now"            queue, pool, retries      anthropic / openai / mock
    │              │  state JSON + tool schemas                                   │
    └── apply_tool_call() ◄── decision_received(tool calls) ◄───────────────────┘
        whitelist, type-check, clamp
```

1. A `ChipComponent` (child of a `Machine`) holds one chip, a `ChipRessource`: name, description and a
   player-written system prompt. A machine can have several chips; each has its own timeout, cooldown and
   in-flight flag, so chips never compete with each other.
2. Only two things wake a chip: its fixed timer (`timeout` ticks at 10 Hz) and the manual "Ask now" button.
   Both call `ChipComponent.call_llm(reason)`. Machine events (overheating, output full...) never wake a chip.
   The machine's state is only sent when the chip is asked.
3. `call_llm` is dropped, not queued, when a request is already in flight (`pending`) or the per-chip cooldown
   (`Settings.chip_cooldown`, 5 s by default) has not elapsed.
4. The request is `LLMManager.request_decision(requester_id, prompt, machine.get_state(), machine.get_tool_schemas())`.
   The prompt is the system prompt; the state is a compact JSON of the machine; the tools are the machine's
   tool schemas. The model answers with tool calls (tool choice is automatic, so it may answer with none).
5. The answer comes back as the `decision_received` / `decision_failed` signals, filtered by `requester_id`.
   Each tool call goes through `Machine.apply_tool_call`, the only way LLM output touches a machine.

### LLMManager (`scripts/llm/llm_manager.gd`, autoload)

The only code allowed to do HTTP. It owns:

- **Queue and concurrency cap**: at most `Settings.max_concurrency` (default 4) requests in flight; the rest
  wait. A newer request from the same requester replaces its older queued one, which fails with `"superseded"`.
- **HTTPRequest pool**: one node per in-flight request, reused afterwards. A node is never shared between
  concurrent requests.
- **Timeouts and retries**: `Settings.request_timeout` (20 s). HTTP 429 is retried with exponential backoff,
  at most `MAX_RETRIES` (3) times. Network errors, non-200 statuses and unparsable JSON become
  `decision_failed(requester_id, reason)`; the machine simply keeps its last settings.
- **Requester check**: before sending and after every `await`, the requester must still be a valid node inside
  the tree. A machine deleted while its request is in flight is dropped silently.
- **Key check**: `check_key()` sends a free request (list models) and reports `valid`, `invalid` or `error` on
  `EventBus.key_checked`, shown as the key icon in the Bar.
- **Error reports** carry the HTTP status and error type only; the configured key is masked. Provider messages
  are only added with the opt-in `PROMPTORIO_DEBUG_LLM=1` in an editor run.

Tests replace the single network function `_send()` with scripted responses (`tests/support/`), so the suite
never touches the network.

### Providers (`scripts/llm/providers/`)

`LLMProvider` is the base class. Nothing outside this folder knows a wire format.

| Provider | Purpose |
|---|---|
| `AnthropicProvider` | Messages API, tool use. |
| `OpenAIProvider` | Responses API. |
| `MockProvider` | Offline, deterministic: ignores the prompt and returns the first tool with fixed arguments after 0.3 to 1.5 s. Default. |

Each implements `build_request(system_prompt, state, tools)` (returns `{url, headers, body}`),
`parse_response(body)` (returns a normalized `[{name, args}]`), `build_check_request()` and `config_error()`.
The provider is picked by `Settings.provider`. A relay origin can replace the official endpoint per provider
(`Settings.get_base_url`); it must be an https origin, otherwise nothing is sent. The key comes only from
`Settings` (or a git-ignored `.env` in editor runs), and is never logged.

### Tools: how a machine is controlled

Every machine exposes `get_tool_schemas()`: the shared `set_enabled(on)` plus the tools of its type (for example
`set_mine_ticks` on the Miner, `set_cooling` on the Smelter, `set_product` on Smelter and Assembler). The full list
is in `IMPLEMENTATION.md`, "AI tool inventory".

LLM output is never trusted. `Machine.apply_tool_call(name, args)`:

1. ignores a tool name that is not in the machine's schemas;
2. requires every argument of the schema and type-checks it;
3. clamps numbers to the schema's bounds;
4. only then calls the machine's own `_apply()`, and logs the result in the ChipLog.

A refused call sets `Machine.refusal`, which is written to the log with the reason.

### Orchestrator (`scripts/machines/orchestrator.gd`)

A late-game, expensive machine (150) whose chip manages other chips instead of producing. Its state lists the
machines in range (a square of 1 to 8 cells) and the registry chips; its tools are `assign_chip`, `remove_chip`,
`set_range`, `create_chip` and `revise_chip`.

- It never calls a tool on another machine. It only attaches or detaches registry chips, which then run on their
  own timers like any chip.
- **Ownership**: `ChipComponent.assigned_by` (0 for the player, else the Orchestrator's machine id) and
  `ChipRessource.created_by` are the only records. An Orchestrator touches only what it owns; a player's
  assignment or chip is never overridden. Editing a generated chip by hand claims it for the player.
- **Revision is gated**: `revise_chip` needs at least 5 recent decisions observed on the chip
  (`ChipComponent.outcome_counts()`: `applied`, `none`, `failed` over the last 20) and a cooldown of 300 ticks, so
  a prompt cannot be rewritten on a single bad answer.
- Deleting an Orchestrator releases everything it owns; the chips stay attached and keep running.

The costs, range and thresholds are starting numbers that still need playtesting (issue #29).

### Predefined behaviors (no AI)

`PredefinedBehaviors` is a small fixed table of canned schedules for Miner and Smelter, run by
`PredefinedBehaviorComponent`. No prompt, no `LLMManager`, no key. Their tool calls go through the same
`apply_tool_call` path, so they are not a shortcut around validation. This is what makes the game playable
without a key.

### Debugging an agent

- **ChipLog** (button in the machine tooltip): the timeline of what a machine's chips asked and applied.
- **Session log**: `user://logs/session_<date>_<time>.log`, one line per machine log message, with keys masked.
- **Chip indicator** above each machine: spinner while a request is pending, then check, dash or cross.

## 2. Development agents

The game was built with AI agents. We used an AI orchestrator called **superfliX** to run them, with one agent
per type of task, each with its own scope:

| Agent | Role |
|---|---|
| UX / UI | Layouts, themes, menus, visual feedback (`docs/UI.md`). |
| Game design | Mechanics, economy, orders, balance (`docs/PLAN.md`). |
| Sound design | Sound effects and audio settings. |
| Project manager | Turns the work into issues and assigns an agent to each task. |
| Reviewer | Reviews the pull requests and merges them. |

How the work flows:

1. The project manager creates the issues and assigns the agents.
2. Each agent works on its own branch (`agent/<name>/<id>`) and opens a pull request. Branches and scene files are
   shared, so scene ownership is announced to avoid merge conflicts (`.tscn` files merge badly).
3. The reviewer reviews each pull request against `CLAUDE.md` and `docs/`, then merges it. A pull request author
   does not merge its own work.
4. The reviewer also audits `main` and reports problems to the project manager, who opens an issue for each.

Every agent reads `CLAUDE.md` first (`AGENTS.md` and `CLAUDE.md` both link to `docs/CONTEXT.md`), so the
architecture, the async HTTP rules, the conventions and the testing rules are the same for all of them. Rules
that keep the output reliable:

- Every feature ships with tests, and the whole suite (`tests/run.sh`) must pass before a commit.
- `godot --headless --quit` must be clean before a task is called done.
- Behavior changes are documented in the same change.
- Issues are the source of truth for task status; `docs/PLAN.md` records goals and decisions only.
