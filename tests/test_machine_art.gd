extends "res://tests/test_case.gd"
## Machine and conveyor sprites: art per scene, front/back by facing, belt flips and a seamless scroll loop.

const SCENES: Dictionary = {
	"miner": "res://scenes/machines/miner.tscn",
	"smelter": "res://scenes/machines/smelter.tscn",
	"assembler": "res://scenes/machines/assembler.tscn",
	"collector": "res://scenes/machines/collector.tscn",
	"conveyor": "res://scenes/machines/conveyor.tscn",
}
const FACINGS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]

var _nodes: Array[Node] = []


func after_each() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()


func _spawn(type: String, facing: Vector2i = Vector2i.RIGHT) -> Machine:
	var machine: Machine = (load(SCENES[type]) as PackedScene).instantiate() as Machine
	machine.facing = facing
	tree.root.add_child(machine)
	_nodes.append(machine)
	return machine


func _sprite(machine: Machine) -> Sprite2D:
	return machine.get_node("Sprite2D") as Sprite2D


func _belt(machine: Machine) -> Sprite2D:
	return machine.get_node("Belt") as Sprite2D


func _tick(number: int) -> void:
	autoload("EventBus").tick_fired.emit(number)


func test_every_machine_scene_has_art_one_cell_wide() -> void:
	for type: String in SCENES:
		var sprite: Sprite2D = _sprite(_spawn(type))
		check(sprite.texture != null, "%s has a texture" % type)
		check_eq(sprite.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "%s keeps its pixels sharp" % type)
		var size: Vector2 = (sprite.region_rect.size if sprite.region_enabled else sprite.texture.get_size()) * sprite.scale
		check_eq(size, Vector2(autoload("GameState").CELL_SIZE, autoload("GameState").CELL_SIZE), "%s covers exactly one cell" % type)



func test_craft_machines_show_their_back_only_when_facing_up() -> void:
	for type: String in ["smelter", "assembler"]:
		var machine: Machine = _spawn(type)
		check(machine.back_texture != null and machine.back_texture != machine.front_texture, "%s has distinct back art" % type)
		for facing: Vector2i in FACINGS:
			machine.facing = facing
			var expected: Texture2D = machine.back_texture if facing == Vector2i.UP else machine.front_texture
			check(_sprite(machine).texture == expected, "%s facing %s" % [type, facing])


func _cell_rect(machine: Machine) -> Rect2:
	var sprite: Sprite2D = _sprite(machine)
	var size: Vector2 = sprite.texture.get_size()
	var corners: Array[Vector2] = [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]
	var rect: Rect2 = Rect2(sprite.transform * corners[0], Vector2.ZERO)
	for corner: Vector2 in corners:
		rect = rect.expand(sprite.transform * corner)
	return rect


func test_craft_machines_turn_the_front_on_the_sides_and_keep_it_over_their_cell() -> void:
	var cell: float = float(autoload("GameState").CELL_SIZE)
	for type: String in ["smelter", "assembler"]:
		var machine: Machine = _spawn(type)
		var turns: Dictionary = {Vector2i.DOWN: 0.0, Vector2i.UP: 0.0, Vector2i.RIGHT: -PI / 2.0, Vector2i.LEFT: PI / 2.0}
		for facing: Vector2i in turns:
			machine.facing = facing
			check(is_equal_approx(_sprite(machine).rotation, turns[facing]), "%s facing %s: rotation" % [type, facing])
			check(_cell_rect(machine).is_equal_approx(Rect2(0, 0, cell, cell)), "%s facing %s: still covers exactly its cell" % [type, facing])
		machine.facing = Vector2i.UP
		check(_sprite(machine).texture == machine.back_texture, "%s: up still shows the back, upright" % type)


func test_other_machines_stay_upright_in_every_facing() -> void:
	for type: String in ["miner", "collector", "conveyor"]:
		var machine: Machine = _spawn(type)
		for facing: Vector2i in FACINGS:
			machine.facing = facing
			check_eq(_sprite(machine).rotation, 0.0, "%s facing %s is not rotated" % [type, facing])


func test_rotating_cycles_the_art() -> void:
	var machine: Machine = _spawn("smelter")
	var seen: Array[Texture2D] = []
	for i: int in 4:
		machine.rotate_facing()
		seen.append(_sprite(machine).texture)
	check(seen[0] == machine.front_texture and seen[1] == machine.front_texture, "down and left show the front")
	check(seen[2] == machine.back_texture, "a full turn passes through up, which shows the back")
	check(seen[3] == machine.front_texture, "and ends on the front again (facing right)")


func test_art_follows_a_facing_set_before_the_machine_enters_the_tree() -> void:
	var machine: Machine = _spawn("assembler", Vector2i.UP)
	check(_sprite(machine).texture == machine.back_texture, "placement-style spawn facing up shows the back")


func test_machines_with_one_view_keep_it_in_every_facing() -> void:
	for type: String in ["miner", "collector"]:
		var machine: Machine = _spawn(type)
		for facing: Vector2i in FACINGS:
			machine.facing = facing
			check(_sprite(machine).texture == machine.front_texture, "%s facing %s" % [type, facing])


func test_conveyor_art_and_flips_per_direction() -> void:
	var conveyor: Conveyor = _spawn("conveyor") as Conveyor
	var expected: Dictionary = {
		Vector2i.RIGHT: [conveyor.side_texture, false, false],
		Vector2i.LEFT: [conveyor.side_texture, true, false],
		Vector2i.UP: [conveyor.up_texture, false, false],
		Vector2i.DOWN: [conveyor.up_texture, false, true],
	}
	for facing: Vector2i in expected:
		conveyor.facing = facing
		for sprite: Sprite2D in [_sprite(conveyor), _belt(conveyor)]:
			check([sprite.texture, sprite.flip_h, sprite.flip_v] == expected[facing], "%s for %s" % [sprite.name, facing])


func test_conveyor_label_shows_no_direction_arrow() -> void:
	var conveyor: Conveyor = _spawn("conveyor") as Conveyor
	var label: Label = conveyor.get_node("StatusLabel") as Label
	for facing: Vector2i in Conveyor.ARROWS:
		conveyor.facing = facing
		_tick(1)
		for arrow: String in Conveyor.ARROWS.values():
			check(not label.text.contains(arrow), "label has no %s facing %s" % [arrow, facing])
	check_eq(label.text, "", "an empty conveyor shows no label")
	conveyor.receive("coal")
	_tick(2)
	check_eq(label.text, "•", "a held item shows as a dot")


func test_set_direction_tool_redraws_the_belt() -> void:
	var conveyor: Conveyor = _spawn("conveyor") as Conveyor
	check(conveyor.apply_tool_call("set_direction", {"direction": 1}), "set_direction accepted")
	check(_belt(conveyor).flip_v and _belt(conveyor).texture == conveyor.up_texture, "facing down shows the flipped vertical belt")


func test_belt_scroll_loops_after_a_full_period() -> void:
	var conveyor: Conveyor = _spawn("conveyor") as Conveyor
	var steps: int = Conveyor.SCROLL_PERIOD / Conveyor.SCROLL_PER_TICK
	check(Conveyor.SCROLL_PERIOD % Conveyor.SCROLL_PER_TICK == 0, "the step divides the period, so the loop has no jump")
	check(Conveyor.SCROLL_PER_TICK * 2 < Conveyor.SCROLL_PERIOD, "a step stays under half a period, so the direction is readable")
	for facing: Vector2i in FACINGS:
		conveyor.facing = facing
		_tick(100)
		var start: Rect2 = _belt(conveyor).region_rect
		var poses: Array[Rect2] = [start]
		for i: int in steps - 1:
			_tick(101 + i)
			poses.append(_belt(conveyor).region_rect)
		check_eq(poses.size(), steps, "%s: one pose per step" % facing)
		for i: int in poses.size() - 1:
			check(poses[i] != poses[i + 1], "%s: pose %d moves" % [facing, i])
		_tick(100 + steps)
		check_eq(_belt(conveyor).region_rect, start, "%s: back on the first pose after a full period" % facing)


func test_belt_scrolls_along_the_facing() -> void:
	var conveyor: Conveyor = _spawn("conveyor") as Conveyor
	var step: int = Conveyor.SCROLL_PER_TICK
	conveyor.facing = Vector2i.UP
	_tick(0)
	var up_a: float = _belt(conveyor).region_rect.position.y
	_tick(1)
	check_eq(_belt(conveyor).region_rect.position.y - up_a, float(step), "up samples further down the texture, so the arrows climb")
	conveyor.facing = Vector2i.RIGHT
	_tick(0)
	var right_a: float = _belt(conveyor).region_rect.position.x
	_tick(1)
	check_eq(fposmod(right_a - _belt(conveyor).region_rect.position.x, float(Conveyor.SCROLL_PERIOD)), float(step), "right samples further left, so the arrows move right")


func test_belt_ticks_are_shared_so_neighbours_stay_in_phase() -> void:
	var first: Conveyor = _spawn("conveyor") as Conveyor
	var second: Conveyor = _spawn("conveyor") as Conveyor
	_tick(37)
	check_eq(_sprite(first).region_rect, _sprite(second).region_rect, "two belts on the same tick show the same pose")


func test_belt_surface_sits_on_the_frame_rows_it_covers() -> void:
	var conveyor: Conveyor = _spawn("conveyor") as Conveyor
	conveyor.facing = Vector2i.RIGHT
	check_eq(_belt(conveyor).position, Vector2(0, Conveyor.SURFACE_TOP * 4), "horizontal surface starts below the frame top")
	check_eq(_belt(conveyor).region_rect.size, Vector2(Conveyor.TEXTURE_SIZE, Conveyor.SURFACE_ROWS), "and covers only the surface rows")
	conveyor.facing = Vector2i.UP
	check_eq(_belt(conveyor).position, Vector2.ZERO, "vertical surface covers the whole tile")


func test_belt_textures_repeat_every_scroll_period() -> void:
	var conveyor: Conveyor = _spawn("conveyor") as Conveyor
	var up: Image = conveyor.up_texture.get_image()
	var side: Image = conveyor.side_texture.get_image()
	var period: int = Conveyor.SCROLL_PERIOD
	var up_ok: bool = true
	var side_ok: bool = true
	for a: int in 16:
		for b: int in 16:
			up_ok = up_ok and up.get_pixel(a, b) == up.get_pixel(a, (b + period) % 16)
	for column: int in 16:
		for row: int in range(Conveyor.SURFACE_TOP, Conveyor.SURFACE_TOP + Conveyor.SURFACE_ROWS):
			side_ok = side_ok and side.get_pixel(column, row) == side.get_pixel((column + period) % 16, row)
	check(up_ok, "the vertical belt art repeats every %d rows" % period)
	check(side_ok, "the horizontal belt surface repeats every %d columns" % period)
