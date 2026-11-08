class_name PredefinedBehaviors
extends RefCounted
## Fixed, player-facing table of canned machine behaviors: no prompt, no LLM call, ever. A behavior is a
## small set of tool calls reapplied on its own fixed timer, through Machine.apply_tool_call (the same
## whitelist/validate/clamp path a chip's decision goes through), so it is not a trusted shortcut around it.
##
## This is not a chip (ChipRessource: a player-written prompt an LLMProvider interprets) and not the
## MockProvider (scripts/llm/providers/mock_provider.gd: an offline stand-in that still answers ANY chip's
## prompt the same deterministic way, for dev/test). A predefined behavior has no prompt at all, is never
## sent to LLMManager, and needs no API key or network: a key-free player can pick one from a small fixed
## list instead of writing a chip prompt. Keep this table small and literal — a new general-purpose
## scripting system is explicitly out of scope (GR2-6).

## One behavior: {id, name, description, interval_ticks, optional initial_delay_ticks, steps}.
## After the initial delay (defaulting to the interval), each interval applies the next step.
static var _table: Dictionary = {}


## Every predefined behavior offered for a machine type, in table order. Empty array for a type with none.
static func for_machine_type(machine_type: String) -> Array:
	_ensure_table()
	return _table.get(machine_type, [])


## Empty dictionary for an unknown machine type or behavior id.
static func get_behavior(machine_type: String, behavior_id: int) -> Dictionary:
	for behavior: Dictionary in for_machine_type(machine_type):
		if int(behavior.get("id", 0)) == behavior_id:
			return behavior
	return {}


static func _ensure_table() -> void:
	if not _table.is_empty():
		return
	_table = {
		"miner": [
			{
				"id": 1,
				"name": "Prospector",
				"description": "Canned, no AI: starts a prospecting boost on a fixed timer, as soon as the previous cycle ends.",
				"interval_ticks": Miner.PROSPECT_TICKS + Miner.BOOST_TICKS + 10,
				"steps": [{"tool": "start_prospecting", "args": {}}],
			},
			{
				"id": 2,
				"name": "Fast Pace",
				"description": "Canned, no AI: keeps mining at its fastest possible pace for the current resource.",
				"interval_ticks": 150,
				"steps": [{"tool": "set_mine_ticks", "args": {"ticks": 1}}],
			},
		],
		"smelter": [
			{
				"id": 1,
				"name": "Cool Runner",
				"description": "Canned, no AI: keeps cooling on for slower, cooler crafts.",
				"interval_ticks": 150,
				"initial_delay_ticks": 1,
				"steps": [{"tool": "set_cooling", "args": {"on": true}}],
			},
			{
				"id": 2,
				"name": "Overheat Risk",
				"description": "Canned, no AI: keeps cooling off. Fast crafts, but it can overheat and explode.",
				"interval_ticks": 150,
				"initial_delay_ticks": 1,
				"steps": [{"tool": "set_cooling", "args": {"on": false}}],
			},
		],
	}
