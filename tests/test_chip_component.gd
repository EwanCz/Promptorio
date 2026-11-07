extends "res://tests/test_case.gd"

var _machine: Machine
var _chip: ChipComponent
var _saved_provider: String = ""
var _saved_cooldown: float = 5.0
var _applied: int = -1


func before_each() -> void:
	var settings: Node = autoload("Settings")
	_saved_provider = settings.provider
	_saved_cooldown = settings.chip_cooldown
	settings.provider = "mock"
	settings.chip_cooldown = 0.0
	_applied = -1
	_machine = Machine.new()
	_chip = ChipComponent.new()
	_machine.add_child(_chip)
	tree.root.add_child(_machine)
	_chip.add_prompt("production", "Keep running", 60.0)
	_chip.decision_applied.connect(_on_applied)


func after_each() -> void:
	var settings: Node = autoload("Settings")
	settings.provider = _saved_provider
	settings.chip_cooldown = _saved_cooldown
	_chip.decision_applied.disconnect(_on_applied)
	_machine.free()


func _on_applied(_reason: String, applied: int) -> void:
	_applied = applied


func test_request_round_trip() -> void:
	check(_chip.request_decision("manual"), "request sent")
	check(_chip.pending, "pending while in flight")
	await wait_until(func() -> bool: return not _chip.pending)
	check(not _chip.pending, "pending cleared")
	check(_applied >= 0, "decision applied")


func test_second_request_ignored_while_pending() -> void:
	_chip.request_decision("manual")
	check(not _chip.request_decision("manual"), "ignored while pending")
	await wait_until(func() -> bool: return not _chip.pending)


func test_cooldown_blocks_request() -> void:
	autoload("Settings").chip_cooldown = 60.0
	check(_chip.request_decision("manual"), "first request passes")
	await wait_until(func() -> bool: return not _chip.pending)
	check(not _chip.request_decision("manual"), "second blocked by cooldown")


func test_no_prompt_no_request() -> void:
	_chip.remove_prompt("production")
	check(not _chip.request_decision("manual"), "nothing to ask without a prompt")


func test_prompt_timeout_fires_request() -> void:
	_chip.add_prompt("fast", "Be quick", 1.0)
	for i: int in _tick_rate():
		autoload("EventBus").tick_fired.emit(i)
	check(_chip.pending, "timer triggered a request")
	await wait_until(func() -> bool: return not _chip.pending)


func test_machine_freed_while_pending_is_safe() -> void:
	_chip.request_decision("manual")
	_chip.decision_applied.disconnect(_on_applied)
	_machine.free()
	await wait_seconds(2.0)
	_machine = Machine.new()
	_chip = ChipComponent.new()
	_machine.add_child(_chip)
	_chip.decision_applied.connect(_on_applied)
	check(true, "no crash after freeing a pending machine")


func _tick_rate() -> int:
	return autoload("GameState").TICK_RATE
