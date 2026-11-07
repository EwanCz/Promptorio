extends "res://tests/test_case.gd"

const MINER: String = "res://scenes/machines/miner.tscn"
const SMELTER: String = "res://scenes/machines/smelter.tscn"
const ASSEMBLER: String = "res://scenes/machines/assembler.tscn"

var _machine: Machine
var _res: ChipRessource
var _saved_provider: String = ""
var _saved_cooldown: float = 5.0
var _reason: String = ""


func before_each() -> void:
	var settings: Node = autoload("Settings")
	_saved_provider = settings.provider
	_saved_cooldown = settings.chip_cooldown
	settings.provider = "mock"
	settings.chip_cooldown = 0.0
	_reason = ""
	_res = autoload("ChipRegistry").add("trigger_test", "Keep it running")


func after_each() -> void:
	var settings: Node = autoload("Settings")
	settings.provider = _saved_provider
	settings.chip_cooldown = _saved_cooldown
	if _machine != null:
		_machine.free()
		_machine = null
	autoload("ChipRegistry").remove(_res.id)


func _spawn(path: String) -> ChipComponent:
	_machine = (load(path) as PackedScene).instantiate() as Machine
	tree.root.add_child(_machine)
	var chip: ChipComponent = _machine.attach_chip(_res.id, 100000)
	chip.decision_applied.connect(_on_applied)
	return chip


func _on_applied(reason: String, _applied: int) -> void:
	_reason = reason


func _tick(count: int) -> void:
	for i: int in count:
		autoload("EventBus").tick_fired.emit(i)


func _finish(chip: ChipComponent) -> void:
	await wait_until(func() -> bool: return not chip.pending)


func test_event_fires_when_it_appears() -> void:
	var chip: ChipComponent = _spawn(MINER)
	_tick(5)
	check(not chip.pending, "nothing happening, no request")
	_tick((_machine as Miner).mine_ticks + 2)
	check(chip.pending, "output full wakes the chip")
	await _finish(chip)
	check_eq(_reason, "event:output_full", "reason names the event")


func test_event_held_over_does_not_refire() -> void:
	var chip: ChipComponent = _spawn(MINER)
	_tick((_machine as Miner).mine_ticks + 2)
	await _finish(chip)
	_tick(10)
	check(not chip.pending, "same event is not raised again every tick")


func test_event_already_true_at_attach_does_not_fire() -> void:
	var chip: ChipComponent = _spawn(ASSEMBLER)
	check("input_empty" in _machine.get_events(), "an empty assembler has the input_empty event")
	_tick(5)
	check(not chip.pending, "starting state is not a new event")


func test_error_event_when_machine_not_normal() -> void:
	var chip: ChipComponent = _spawn(MINER)
	_tick(1)
	_machine.status = Machine.Status.DOWN
	_tick(1)
	check(chip.pending, "leaving normal wakes the chip")
	await _finish(chip)
	check_eq(_reason, "event:error", "reason is error")


func test_threshold_fires_on_crossing_only() -> void:
	var chip: ChipComponent = _spawn(SMELTER)
	chip.set_threshold("temperature", 60.0)
	_tick(1)
	check(not chip.pending, "below the threshold")
	(_machine as Smelter).temperature = 90.0
	_tick(1)
	check(chip.pending, "crossing the threshold wakes the chip")
	await _finish(chip)
	check_eq(_reason, "threshold:temperature", "reason names the value")
	_reason = ""
	_tick(1)
	check(not chip.pending, "still above, no new request")
	(_machine as Smelter).temperature = 30.0
	_tick(1)
	(_machine as Smelter).temperature = 90.0
	_tick(1)
	check(chip.pending, "crossing again fires again")
	await _finish(chip)


func test_threshold_off_by_default_and_ignores_non_numbers() -> void:
	var chip: ChipComponent = _spawn(SMELTER)
	(_machine as Smelter).temperature = 90.0
	_tick(1)
	check(not chip.pending, "no threshold set, nothing fires")
	chip.set_threshold("status", 0.0)
	_tick(2)
	check(not chip.pending, "a text value never crosses a threshold")
	chip.set_threshold("missing", 0.0)
	_tick(2)
	check(not chip.pending, "an unknown key never fires")


func test_manual_trigger_uses_cooldown() -> void:
	var chip: ChipComponent = _spawn(MINER)
	autoload("Settings").chip_cooldown = 60.0
	check(chip.call_llm("manual"), "manual request sent")
	await _finish(chip)
	check_eq(_reason, "manual", "reason is manual")
	check(not chip.call_llm("manual"), "manual request obeys the cooldown")
