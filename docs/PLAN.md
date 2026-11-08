# Promptorio Roadmap

This document records goals, decisions and risks. Individual tasks, discussion and status live in their respective issue tracker, such as GitHub or Superflix. Update this plan when goals or decisions change; do not duplicate issue checklists here. The GitHub links below point to issues created from the original plan and group related work; they are not an additional status tracker.

## Goal

Deliver a demoable factory loop for a 2-3 person team: Miner -> Smelter -> Assembler -> Collector, controlled by player-written chip prompts, with a visible success and failure. Keep conveyors deterministic and favor a simple, working game.

## Current Focus

- Demo, onboarding and player goals: [#20](https://github.com/EwanCz/Promptorio/issues/20), [#21](https://github.com/EwanCz/Promptorio/issues/21), [#22](https://github.com/EwanCz/Promptorio/issues/22), [#23](https://github.com/EwanCz/Promptorio/issues/23), [#24](https://github.com/EwanCz/Promptorio/issues/24).
- Release and demo readiness: [#25](https://github.com/EwanCz/Promptorio/issues/25), [#26](https://github.com/EwanCz/Promptorio/issues/26), [#27](https://github.com/EwanCz/Promptorio/issues/27).
- Proposed mechanics for playtesting: Assembler modes [#18](https://github.com/EwanCz/Promptorio/issues/18), mergers and splitters [#19](https://github.com/EwanCz/Promptorio/issues/19). Miner prospecting ([#17](https://github.com/EwanCz/Promptorio/issues/17)) is implemented; see "Miner prospecting" below and `docs/IMPLEMENTATION.md`.
- Later exploration: machine decisions [#28](https://github.com/EwanCz/Promptorio/issues/28), Orchestrator [#29](https://github.com/EwanCz/Promptorio/issues/29), and other prototype conveniences [#30](https://github.com/EwanCz/Promptorio/issues/30).

## Decisions

- **LLM:** provider-agnostic adapter with Anthropic, OpenAI and offline mock providers. Real providers and relay URLs have only been tested with scripted responses; see [#27](https://github.com/EwanCz/Promptorio/issues/27).
- **Secrets:** players configure keys in Settings; editor runs may use an ignored `.env`. Saved settings take precedence. Never export or commit `.env` or keys.
- **Chips:** each machine may have multiple independent chips, each with one prompt, timeout, cooldown and in-flight slot. Only a timer or manual request triggers a chip; state changes do not.
- **Simulation:** a fixed 10 Hz physics-driven clock catches up elapsed time and excludes paused time.
- **Economy:** start with 100 money. Miner costs 20, Smelter 30, Assembler 40 and Conveyor 2. The central Collector is free and fixed. Charge only after valid placement; player removal refunds half, rounded down; explosions do not refund.
- **Logistics:** ordinary conveyors use deterministic logic. AI on conveyors and logistics nodes is post-MVP.
- **Miner prospecting:** `start_prospecting` pauses mining for 8s, then mines at 2x the pace for 20s before resuming on its own; refused mid-cycle (restart or resource switch). Starting numbers to retune from playtesting (`Miner.PROSPECT_TICKS`, `BOOST_TICKS`, `BOOST_RATE`); no change recorded yet.

## Risks

- Demo latency or rate limits: use the mock provider for development, chip cooldowns and a small fast model. A key-free player experience is tracked separately in [#24](https://github.com/EwanCz/Promptorio/issues/24).
- Malformed LLM output: whitelist and validate tool calls; failures leave machines on their last settings.
- Scene merge conflicts: coordinate ownership of scenes, especially the base Machine scene.

## References

- [Project context and agent instructions](CONTEXT.md): architecture, rules and test workflow.
- [UI specification](UI.md): layouts and visual feedback.
- [Implementation reference](IMPLEMENTATION.md): historical details, resource catalog and AI tool inventory; confirm current behavior in code.
