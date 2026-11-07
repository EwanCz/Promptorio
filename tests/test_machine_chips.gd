extends "res://tests/test_case.gd"

var _machine: Machine
var _chip: ChipRessource
var _comp: ChipComponent
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
	_chip = _new_chip("production", "Keep running")
	_machine = Machine.new()
	tree.root.add_child(_machine)
	_comp = _machine.attach_chip(_chip.id, 600)
	_machine.chip_decision_applied.connect(_on_applied)


func after_each() -> void:
	var settings: Node = autoload("Settings")
	settings.provider = _saved_provider
	settings.chip_cooldown = _saved_cooldown
	_machine.chip_decision_applied.disconnect(_on_applied)
	_machine.free()
	autoload("ChipRegistry").remove(_chip.id)


func _new_chip(chip_name: String, message: String) -> ChipRessource:
	return autoload("ChipRegistry").add(chip_name, message)


func _on_applied(_chip_id: int, _reason: String, applied: int) -> void:
	_applied = applied


func _tick(count: int) -> void:
	for i: int in count:
		autoload("EventBus").tick_fired.emit(i)


func _idle(id: int) -> bool:
	return not _machine.get_chip(id).pending


func test_request_round_trip() -> void:
	check(_machine.get_chip(_chip.id).call_llm("manual"), "request sent")
	check(_machine.get_chip(_chip.id).pending, "pending while in flight")
	await wait_until(func() -> bool: return _idle(_chip.id))
	check(_idle(_chip.id), "pending cleared")
	check(_applied >= 0, "decision applied")


func test_second_request_ignored_while_pending() -> void:
	_machine.get_chip(_chip.id).call_llm("manual")
	check(not _machine.get_chip(_chip.id).call_llm("manual"), "ignored while pending")
	await wait_until(func() -> bool: return _idle(_chip.id))


func test_cooldown_blocks_request() -> void:
	autoload("Settings").chip_cooldown = 60.0
	check(_machine.get_chip(_chip.id).call_llm("manual"), "first request passes")
	await wait_until(func() -> bool: return _idle(_chip.id))
	check(not _machine.get_chip(_chip.id).call_llm("manual"), "second blocked by cooldown")


func test_no_prompt_no_request() -> void:
	_chip.prompt = ""
	check(not _machine.get_chip(_chip.id).call_llm("manual"), "nothing to ask without a prompt")


func test_timeout_in_ticks_fires_exactly() -> void:
	_machine.get_chip(_chip.id).set_timeout(5)
	_tick(4)
	check(not _machine.get_chip(_chip.id).pending, "not fired one tick early")
	_tick(1)
	check(_machine.get_chip(_chip.id).pending, "fired on the timeout tick")
	await wait_until(func() -> bool: return _idle(_chip.id))


func test_machine_freed_while_pending_is_safe() -> void:
	var llm: Node = autoload("LLMManager")
	check(_machine.get_chip(_chip.id).call_llm("manual"), "request sent")
	_machine.free()
	await wait_until(func() -> bool: return llm._in_flight == 0, 3.0)
	check_eq(llm._in_flight, 0, "LLMManager released the slot")
	_machine = Machine.new()
	_machine.chip_decision_applied.connect(_on_applied)


func test_chips_on_one_machine_are_independent() -> void:
	var second: ChipRessource = _new_chip("maintenance", "Keep it cool")
	_machine.attach_chip(second.id, 600)
	check(_machine.get_chip(_chip.id).call_llm("manual"), "first chip sends")
	check(_machine.get_chip(second.id).call_llm("manual"), "second chip sends while first is pending")
	check(_comp.pending and _machine.get_chip(second.id).pending, "both in flight")
	await wait_until(func() -> bool: return _idle(_chip.id) and _idle(second.id))
	check(_idle(_chip.id) and _idle(second.id), "both finished")
	autoload("ChipRegistry").remove(second.id)


func test_chip_timers_do_not_share_progress() -> void:
	var second: ChipRessource = _new_chip("maintenance", "Keep it cool")
	_machine.attach_chip(second.id, 600)
	_machine.get_chip(_chip.id).set_timeout(3)
	_tick(3)
	check(_machine.get_chip(_chip.id).pending, "short-timeout chip fired")
	check(not _machine.get_chip(second.id).pending, "long-timeout chip did not fire")
	await wait_until(func() -> bool: return _idle(_chip.id))
	autoload("ChipRegistry").remove(second.id)


func test_attach_detach_and_timeout() -> void:
	check_eq(_machine.chips, [_comp], "attached")
	check_eq(_comp.get_parent(), _machine, "component is a child of the machine")
	check_eq(_comp.timeout, 600, "timeout in ticks")
	check(_machine.attach_chip(_chip.id) == null, "same chip not attached twice")
	check(_machine.attach_chip(9999) == null, "unknown chip id refused")
	_machine.detach_chip(_chip.id)
	check_eq(_machine.chips.size(), 0, "detached")
	check(_machine.get_chip(_chip.id) == null, "no component once detached")
