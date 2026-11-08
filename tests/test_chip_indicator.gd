extends "res://tests/test_case.gd"
## The icon above a machine: spinner while any chip waits, then the result of the last one.

var _machine: Machine
var _chips: Array[ChipRessource] = []
var _comps: Array[ChipComponent] = []
var _saved_provider: String = ""
var _saved_cooldown: float = 5.0


func before_each() -> void:
	var settings: Node = autoload("Settings")
	_saved_provider = settings.provider
	_saved_cooldown = settings.chip_cooldown
	settings.provider = "mock"
	settings.chip_cooldown = 0.0
	_machine = Machine.new()
	tree.root.add_child(_machine)
	for chip_name: String in ["indicator_a", "indicator_b"]:
		var chip: ChipRessource = autoload("ChipRegistry").add(chip_name, "Keep running")
		_chips.append(chip)
		_comps.append(_machine.attach_chip(chip.id, 600))


func after_each() -> void:
	var settings: Node = autoload("Settings")
	settings.provider = _saved_provider
	settings.chip_cooldown = _saved_cooldown
	_machine.free()
	for chip: ChipRessource in _chips:
		autoload("ChipRegistry").remove(chip.id)
	_chips.clear()
	_comps.clear()


## Answers chip `index` as the LLM would: pending ends, then the decision arrives.
func _answer(index: int, calls: Array[Dictionary]) -> void:
	autoload("LLMManager").decision_received.emit(_comps[index].get_instance_id(), calls)


func _call(tool_name: String, on: bool) -> Array[Dictionary]:
	var calls: Array[Dictionary] = [{"name": tool_name, "args": {"on": on}}]
	return calls


func _start(index: int) -> void:
	_comps[index].pending = true
	_comps[index].activity_changed.emit("checking")


func test_a_new_machine_shows_nothing() -> void:
	check(_machine.indicator != null and not _machine.indicator.visible, "hidden")
	check_eq(_machine.indicator.state, "", "no state")


func test_the_indicator_sits_above_the_machine_and_scales_with_the_art() -> void:
	var indicator: ChipIndicator = _machine.indicator
	check(indicator.position.y < 0.0, "above the machine's own cell")
	check_eq(indicator.position.x, _cell_size() / 2.0, "centered over it")
	_start(0)
	check_eq(indicator.scale, Vector2(Icons.SCALE, Icons.SCALE), "pixel scale")
	check_eq(indicator.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "crisp pixels")


func _cell_size() -> float:
	return float(autoload("GameState").CELL_SIZE)


func test_pending_shows_the_spinner_and_it_animates() -> void:
	var asked: Array[String] = []
	var on_activity: Callable = func(outcome: String) -> void: asked.append(outcome)
	_comps[0].activity_changed.connect(on_activity)
	check(_comps[0].call_llm("manual"), "request sent")
	_comps[0].activity_changed.disconnect(on_activity)
	check_eq(asked, ["checking"] as Array[String], "the chip announces the request")
	check_eq(_machine.indicator.state, "checking", "spinner while waiting")
	check(_machine.indicator.visible, "visible")
	var before: PackedByteArray = _machine.indicator.texture.get_image().get_data()
	await wait_until(func() -> bool: return _machine.indicator.state != "checking" or _machine.indicator.texture.get_image().get_data() != before, 2.0)
	if _machine.indicator.state == "checking":
		check(_machine.indicator.texture.get_image().get_data() != before, "the frames change over time")
	await wait_until(func() -> bool: return not _comps[0].pending)


func test_an_applied_action_shows_its_icon_then_hides() -> void:
	_machine.indicator.result_seconds = 0.05
	_start(0)
	_answer(0, _call("set_enabled", false))
	check_eq(_machine.indicator.state, "applied", "applied icon")
	check_eq(_machine.indicator.texture.get_image().get_data(), Icons.icon("applied").get_image().get_data(), "the check mark")
	await wait_until(func() -> bool: return _machine.indicator.state == "", 2.0)
	check(not _machine.indicator.visible, "hidden again after a moment")


func test_no_action_shows_a_distinct_icon() -> void:
	_start(0)
	var none: Array[Dictionary] = []
	_answer(0, none)
	check_eq(_machine.indicator.state, "none", "no action")
	check_eq(_machine.indicator.texture.get_image().get_data(), Icons.icon("none").get_image().get_data(), "the dash")


func test_failures_and_rejected_calls_show_the_failure_icon() -> void:
	_start(0)
	autoload("LLMManager").decision_failed.emit(_comps[0].get_instance_id(), "HTTP 500")
	check_eq(_machine.indicator.state, "failed", "failed request")
	_start(1)
	_answer(1, _call("launch_missiles", true))
	check_eq(_machine.indicator.state, "failed", "a call the machine refused")
	check_eq(_machine.indicator.texture.get_image().get_data(), Icons.icon("failed").get_image().get_data(), "the cross")


func test_results_are_distinct_from_each_other_and_from_the_spinner() -> void:
	var seen: Dictionary = {}
	for outcome: String in ["applied", "none", "failed"]:
		seen[Icons.icon(outcome).get_image().get_data()] = true
	for frame: Texture2D in Icons.spinner_frames():
		seen[frame.get_image().get_data()] = true
	check_eq(seen.size(), 3 + Icons.SPINNER_FRAMES, "all different")


func test_overlapping_requests_keep_the_spinner_until_the_last_one_ends() -> void:
	_start(0)
	_start(1)
	_answer(0, _call("set_enabled", false))
	check_eq(_machine.indicator.state, "checking", "one chip finishing does not hide the other that still runs")
	_answer(1, _call("set_enabled", true))
	check_eq(_machine.indicator.state, "applied", "the last result shows once nothing is pending")


func test_removing_the_last_pending_chip_clears_the_spinner() -> void:
	_start(0)
	check_eq(_machine.indicator.state, "checking", "pending")
	_machine.detach_chip(_chips[0].id)
	check_eq(_machine.indicator.state, "", "nothing left to wait for")
