extends "res://tests/test_case.gd"
## Assembler production modes: normal (the recipe unchanged) and fast (extra inputs, shorter time).

const SCENES: Dictionary = {
	"assembler": "res://scenes/machines/assembler.tscn",
	"collector": "res://scenes/machines/collector.tscn",
}

var _game: Node
var _bus: Node
var _nodes: Array[Node] = []


func before_each() -> void:
	_game = autoload("GameState")
	_bus = autoload("EventBus")


func after_each() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()


func _put(type: String, cell: Vector2i, facing: Vector2i = Vector2i.RIGHT) -> Machine:
	var machine: Machine = (load(SCENES[type]) as PackedScene).instantiate() as Machine
	machine.cell = cell
	machine.facing = facing
	tree.root.add_child(machine)
	_game.register_machine(machine, cell)
	_nodes.append(machine)
	return machine


func _ticks(count: int) -> void:
	for i: int in count:
		_bus.tick_fired.emit(i)


func test_set_mode_tool_reads_and_writes_the_mode() -> void:
	var assembler: Assembler = _put("assembler", Vector2i(0, 0)) as Assembler
	check_eq(assembler.mode, Assembler.MODE_NORMAL, "normal by default")
	check_eq(assembler.get_state()["mode"], Assembler.MODE_NORMAL, "state shows it")
	check(assembler.apply_tool_call("set_mode", {"mode": Assembler.MODE_FAST}), "tool accepted")
	check_eq(assembler.mode, Assembler.MODE_FAST, "mode switched")
	check_eq(assembler.get_state()["mode"], Assembler.MODE_FAST, "state shows fast")
	check(not assembler.apply_tool_call("set_mode", {"mode": "ludicrous"}), "an unknown mode is refused")
	check_eq(assembler.mode, Assembler.MODE_FAST, "refused calls change nothing")


func test_fast_mode_scales_every_input_of_a_multi_input_recipe() -> void:
	var assembler: Assembler = _put("assembler", Vector2i(0, 0)) as Assembler
	assembler.apply_tool_call("set_product", {"item": "circuit"})
	check_eq(assembler.get_effective_inputs(), {"silver_bar": 1, "redstone": 2}, "normal mode: the recipe unchanged")
	assembler.apply_tool_call("set_mode", {"mode": Assembler.MODE_FAST})
	check_eq(assembler.get_effective_inputs(), {"silver_bar": 2, "redstone": 4}, "fast mode: both inputs doubled")
	check_eq(assembler.get_state()["needs"], {"silver_bar": 2, "redstone": 4}, "state shows the scaled recipe")


func test_fast_mode_waits_for_its_extra_inputs_instead_of_falling_back_to_normal() -> void:
	var assembler: Assembler = _put("assembler", Vector2i(0, 0))
	var collector: Machine = _put("collector", Vector2i(1, 0))
	assembler.apply_tool_call("set_mode", {"mode": Assembler.MODE_FAST})
	assembler.receive("ingot")
	assembler.receive("ingot")
	_ticks(60)
	check_eq(collector.sold, 0, "two ingots would be enough for a normal craft, but fast mode needs four")
	check_eq((assembler as Assembler).progress, 0, "nothing starts: it waits")
	assembler.receive("ingot")
	assembler.receive("ingot")
	_ticks(60)
	check(collector.sold >= 1, "once the extra ingots arrive, the fast craft runs")


func test_fast_mode_is_faster_and_costs_more_than_normal() -> void:
	var normal: Assembler = _put("assembler", Vector2i(0, 0)) as Assembler
	var fast: Assembler = _put("assembler", Vector2i(4, 0)) as Assembler
	fast.apply_tool_call("set_mode", {"mode": Assembler.MODE_FAST})
	for i: int in 2:
		normal.receive("ingot")
	for i: int in 4:
		fast.receive("ingot")
	_ticks(1)
	check_eq(normal.progress, normal.get_product().ticks, "normal: the recipe's own time")
	check_eq(fast.progress, normal.get_product().ticks / Assembler.FAST_TIME_DIVISOR, "fast: the recipe time divided by the factor")
	check_eq(normal.stock.get("ingot", 0), 0, "normal consumed its 2 ingots")
	check_eq(fast.stock.get("ingot", 0), 0, "fast consumed its 4 ingots")


func test_mode_change_mid_craft_locks_the_running_craft_the_next_one_follows_the_new_mode() -> void:
	var assembler: Assembler = _put("assembler", Vector2i(0, 0)) as Assembler
	var collector: Machine = _put("collector", Vector2i(1, 0))
	assembler.receive("ingot")
	assembler.receive("ingot")
	_ticks(1)
	check_eq(assembler.progress, 30, "a normal craft is under way (30 ticks, just started)")
	assembler.apply_tool_call("set_mode", {"mode": Assembler.MODE_FAST})
	check_eq(assembler.progress, 30, "switching mode mid-craft does not change its already-chosen duration")
	_ticks(40)
	check_eq(collector.sold, 1, "the normal craft finished and was sold at the cost it started with")
	assembler.receive("ingot")
	assembler.receive("ingot")
	_ticks(5)
	check_eq(collector.sold, 1, "two ingots: not enough for the now-active fast mode (needs four), so it waits")
	check_eq(assembler.progress, 0, "no craft started")
	assembler.receive("ingot")
	assembler.receive("ingot")
	_ticks(1)
	check_eq(assembler.progress, 15, "the next craft follows fast mode: half the recipe time")


func test_mode_and_in_progress_craft_persist_through_save_load() -> void:
	var assembler: Assembler = _put("assembler", Vector2i(0, 0)) as Assembler
	assembler.apply_tool_call("set_mode", {"mode": Assembler.MODE_FAST})
	for i: int in 4:
		assembler.receive("ingot")
	_ticks(2)
	check_eq(assembler.progress, 14, "a fast craft one tick into its 15-tick run")
	var data: Dictionary = assembler.to_dict()
	var fresh: Assembler = _put("assembler", Vector2i(8, 8)) as Assembler
	fresh.load_dict(data)
	check_eq(fresh.mode, Assembler.MODE_FAST, "mode persisted")
	check_eq(fresh.get_state()["mode"], Assembler.MODE_FAST, "state after load shows it")
	check_eq(fresh.progress, 14, "the in-progress craft survived with its remaining ticks")
	check_eq(fresh.stock.get("ingot", 0), 0, "the spent ingots are not restored twice")
	check_eq((fresh.get_node("Sprite2D") as Sprite2D).modulate, Assembler.FAST_TINT, "the loaded fast mode re-applies the tint")
	var collector: Machine = _put("collector", Vector2i(9, 8))
	_ticks(20)
	check(collector.sold >= 1, "the resumed craft still finishes and delivers")


func test_fast_mode_tints_the_sprite_as_in_world_feedback() -> void:
	var assembler: Assembler = _put("assembler", Vector2i(0, 0)) as Assembler
	var sprite: Sprite2D = assembler.get_node("Sprite2D") as Sprite2D
	check_eq(sprite.modulate, Color.WHITE, "normal mode keeps the art's own colours")
	assembler.apply_tool_call("set_mode", {"mode": Assembler.MODE_FAST})
	check_eq(sprite.modulate, Assembler.FAST_TINT, "fast mode tints the sprite")
	assembler.apply_tool_call("set_mode", {"mode": Assembler.MODE_NORMAL})
	check_eq(sprite.modulate, Color.WHITE, "switching back to normal clears the tint")


## Entries of a details-panel row, as (icon kind, text, hover) so a test can read what the player sees.
func _entries(row: Node) -> Array[Array]:
	var found: Array[Array] = []
	for cell: Node in row.get_children():
		var picture: TextureRect = cell.get_child(0) as TextureRect
		var number: String = "" if cell.get_child_count() < 2 else (cell.get_child(1) as Label).text
		found.append([picture.texture, number, picture.tooltip_text])
	return found


func _hints(row: Node) -> Array[String]:
	var hints: Array[String] = []
	for entry: Array in _entries(row):
		hints.append(entry[2])
	return hints


func test_tooltip_shows_the_mode_icon_and_the_real_recipe_quantities() -> void:
	var tooltip: MachineTooltip = (load("res://scenes/ui/popups/machine_tooltip.tscn") as PackedScene).instantiate() as MachineTooltip
	tree.root.add_child(tooltip)
	_nodes.append(tooltip)
	var assembler: Assembler = _put("assembler", Vector2i(0, 0)) as Assembler
	assembler.apply_tool_call("set_product", {"item": "circuit"})
	_bus.machine_selected.emit(assembler)
	var op: Node = tooltip.get_node("%OpRow")
	check_eq(_hints(op), ["Normal mode", "Needs Silver Bar", "Needs Redstone", "Makes", "Makes Circuit"] as Array[String], "normal mode icon, then the recipe with its real quantities")
	var normal_counts: Array = _entries(op)
	check_eq([normal_counts[1][1], normal_counts[2][1]], ["", "x2"], "normal: 1 silver bar (no count shown) + 2 redstone")
	assembler.apply_tool_call("set_mode", {"mode": Assembler.MODE_FAST})
	_bus.tick_fired.emit(0)
	check_eq(_hints(op), ["Fast mode: extra inputs, shorter time", "Needs Silver Bar", "Needs Redstone", "Makes", "Makes Circuit"] as Array[String], "fast mode icon swaps in")
	var fast_counts: Array = _entries(op)
	check_eq([fast_counts[1][1], fast_counts[2][1]], ["x2", "x4"], "fast mode doubles both inputs (1->2 silver bar, 2->4 redstone)")


func test_set_mode_tool_schema_describes_the_tradeoff() -> void:
	var assembler: Assembler = _put("assembler", Vector2i(0, 0)) as Assembler
	var description: String = ""
	for schema: Dictionary in assembler.get_tool_schemas():
		if schema["name"] == "set_mode":
			description = schema["description"]
	check(description.contains("normal") and description.contains("fast"), "names both modes")
	check(description.contains(str(Assembler.FAST_INPUT_MULTIPLIER)), "states the input multiplier")
	check(description.contains("waits") or description.contains("wait"), "states that it waits rather than falling back")
