# Promptorio

A 2D factory-building game, built in Godot 4. You place Miners, Smelters, Assemblers and Conveyors to build a production line, then give each machine an "AI chip": a system prompt written in plain English that an LLM uses to decide what the machine should do next (change its mining pace, toggle cooling, switch what it builds, and so on). Write a good prompt and the machine runs itself well; write a careless one and you can watch a Smelter overheat and explode.

The game runs with no API key and no network out of the box, using a deterministic offline "mock" AI that lets you build and play the full loop before connecting a real provider.

## Requirements

- [Godot Engine 4.7](https://godotengine.org/download) or later (the project uses Godot 4.7 features).
- Git, to clone the repository.
- Optional: an Anthropic or OpenAI API key, only if you want chips to be driven by a real model instead of the built-in mock.

## Getting started

```sh
git clone git@github.com:EwanCz/Promptorio.git
cd Promptorio
```

Open the project in Godot:

1. Launch the Godot editor and choose **Import**.
2. Select the cloned folder's `project.godot`.
3. Once the project is open, press **Run** (F5) or the Play button in the top right.

The game starts on the main menu (Play, Load Game, Chips, Options, Exit). Choose **Play** to start a new factory.

## Controls

| Action | Key / Input |
|---|---|
| Select Miner / Smelter / Assembler | `1` / `2` / `3` |
| Select Conveyor | `5` |
| Place selected machine | Left click an empty grid cell |
| Rotate selected machine / placement | `R` |
| Cancel placement | `Escape` |
| Show / hide the side panel (the "Bar") | `E` |
| Pan camera | Arrow keys, or middle-mouse drag |
| Zoom camera | Mouse wheel |

The Orchestrator machine has no keyboard shortcut; build it from the Build page in the Bar. A Build page button, and a chip in the Chip Registry page, can also be dragged directly onto the map.

## Playing your first factory

The core loop is: **place → connect → attach a chip → fulfill an order.**

1. Open the **Build** page in the Bar (right side of the screen) and place a **Miner** on one of the highlighted minesite tiles. A freshly placed machine faces right by default; press `R` before placing to rotate it, or afterward to rotate it in place.
2. Place a **Smelter** on the empty tile the Miner is facing, so the Miner can hand its ore over directly (no Conveyor needed between adjacent machines).
3. Place a **Conveyor**, or another machine, on the tile the Smelter is facing, to carry ingots on toward the Collector at the center of the map.
4. Click the Smelter to open its tooltip, then use **add chip** to attach a chip from the Chip Registry (for example, the built-in "Smelter Cooler" chip). The chip checks in on its own timer, or immediately if you press **Ask now**.
5. Watch the Bar's **Order status** panel: selling the ordered resource at the Collector advances the order, and completing it pays a reward on top of the normal sale.

You start with 100 money. Build costs: Miner 20, Smelter 30, Assembler 40, Conveyor 2, Orchestrator 150. The Collector is fixed at the map center and free.

To see both ends of what a chip's prompt can cause, open **Load Game** from the main menu and load one of the bundled demo saves:

- `SmelterStable` — a well-managed Smelter that keeps cooling and keeps selling.
- `SmelterExplosion` — an unmanaged Smelter that overheats and explodes within about 30 seconds.

## Configuring an AI provider (optional)

By default `Settings.provider` is `mock`: a deterministic, offline stand-in that answers every chip instantly with no network call, so you can build and play with zero setup. The Bar's key icon shows a grey dot while `mock` is active, to make clear no real AI is reading your prompts.

To have chips driven by a real model instead:

1. Open **Settings** from the Bar.
2. Switch the provider to `anthropic` or `openai`.
3. Enter your API key (it is saved to `user://settings.cfg` on your machine and is never logged or exported).

As a developer, you can also drop keys into a git-ignored `.env` file at the project root instead of using the Settings dialog — copy `.env.example` to `.env` and fill in `ANTHROPIC_API_KEY` / `OPENAI_API_KEY`. This is read only by editor runs (`OS.has_feature("editor")`), never by an exported build, and a key saved through Settings always takes precedence over it. `.env` must never be committed.

The Bar's key icon reports whether the configured key was verified, rejected, or couldn't be checked; hover it for details.

## Running the tests

```sh
tests/run.sh          # whole suite, headless
tests/run.sh llm      # only test files whose name contains "llm"
```

Requires the `godot` binary on your `PATH` (or set `GODOT=/path/to/godot`). The suite runs offline against the mock provider only — no network access or real API key is ever used in tests.

## Project documentation

- [`docs/CONTEXT.md`](docs/CONTEXT.md) — architecture, coding conventions and the async HTTP rules (also the brief used by coding agents working on this repo, via `AGENTS.md` / `CLAUDE.md`).
- [`docs/PLAN.md`](docs/PLAN.md) — project goals, decisions and open risks.
- [`docs/IMPLEMENTATION.md`](docs/IMPLEMENTATION.md) — detailed reference of implemented features, the resource catalog and the AI tool inventory.
- [`docs/UI.md`](docs/UI.md) — UI layout and visual feedback rules.

## Credits

Third-party art and audio assets are credited in `assets/*/CREDITS.md`.
