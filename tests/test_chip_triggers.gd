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
	if _machine != null:
		_machine.free()
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


var _started: int = 0


func _on_started(_id: int) -> void:
	_started += 1


func test_machine_events_never_wake_a_chip() -> void:
	var bus: Node = autoload("EventBus")
	_started = 0
	bus.llm_request_started.connect(_on_started)
	var chip: ChipComponent = _spawn(MINER)
	var miner: Miner = _machine as Miner
	var before: Array = [miner.enabled, miner.mine_ticks]
	_tick(miner.mine_ticks + 2)
	check("output_full" in miner.get_events(), "the miner really is blocked (the event exists)")
	check(not chip.pending, "output full does not wake the chip")
	miner.status = Machine.Status.DOWN
	_tick(3)
	check("error" in miner.get_events() and not chip.pending, "a machine error does not wake it either")
	check_eq([miner.enabled, miner.mine_ticks], before, "no machine setting changed")
	var assembler: ChipComponent = _spawn(ASSEMBLER)
	_tick(3)
	check("input_empty" in _machine.get_events() and not assembler.pending, "nor does an empty input")
	bus.llm_request_started.disconnect(_on_started)
	check_eq(_started, 0, "the LLM was never called")
	check_eq(_reason, "", "no decision was ever asked for")


func test_timer_trigger_still_fires() -> void:
	var chip: ChipComponent = _spawn(MINER)
	chip.set_timeout(5)
	_tick(4)
	check(not chip.pending, "not before the timeout")
	_tick(1)
	check(chip.pending, "the timer wakes the chip")
	await _finish(chip)
	check_eq(_reason, "timer", "reason is timer")


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
