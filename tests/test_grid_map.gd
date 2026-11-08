extends "res://tests/test_case.gd"

var _main: Node
var _grid: Node


func before_each() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	_grid = _main.get_node("Game/FactoryView/SubViewport/World/GridMap2D")


func after_each() -> void:
	_main.free()


func test_every_cell_has_a_tile() -> void:
	_grid._build_ground()
	var size: Vector2i = autoload("GameState").GRID_SIZE
	var missing: int = 0
	for x: int in size.x:
		for y: int in size.y:
			if _grid.get_cell_source_id(Vector2i(x, y)) == -1:
				missing += 1
	check_eq(missing, 0, "every grid cell has a ground tile")
	check_eq(_grid.get_cell_source_id(size), -1, "no tile outside the grid")


func test_ground_has_multiple_contiguous_biomes() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42
	var ground: Dictionary = _grid._generate_ground(rng)
	var biomes: Dictionary = {}
	for cell: Vector2i in ground:
		biomes[ground[cell]["atlas"]] = true
	check(biomes.size() >= 2, "more than one ground tile is used, not a single tile repeated everywhere: %s" % [biomes.keys()])
	# Clustering: a pure-biome cell shares its biome with most of its neighbors most of the time,
	# which random per-cell noise (one of 3 types independently per cell) would not produce.
	var same_biome: int = 0
	var checked: int = 0
	for cell: Vector2i in ground:
		var biome: Vector2i = ground[cell]["atlas"]
		if biome != GridMap2D.DIRT_TILE and biome != GridMap2D.ROCK_TILE and biome != GridMap2D.GRASS_TILE:
			continue
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var neighbor: Variant = ground.get(cell + direction)
			if neighbor == null:
				continue
			checked += 1
			if neighbor["atlas"] == biome:
				same_biome += 1
	check(float(same_biome) / float(checked) > 0.6, "most neighbors of a biome cell share its biome (contiguous clusters): %d/%d" % [same_biome, checked])


func test_every_biome_appears_across_seeded_maps() -> void:
	var missing: Array[int] = []
	for seed_value: int in 100:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = seed_value
		var ground: Dictionary = _grid._generate_ground(rng)
		var found: Dictionary = {}
		for cell: Vector2i in ground:
			var tile: Vector2i = ground[cell]["atlas"]
			if tile == GridMap2D.ROCK_DIRT_EDGE:
				tile = GridMap2D.ROCK_TILE
			elif tile == GridMap2D.GRASS_DIRT_EDGE:
				tile = GridMap2D.GRASS_TILE
			found[tile] = true
		if not (found.has(GridMap2D.DIRT_TILE) and found.has(GridMap2D.ROCK_TILE) and found.has(GridMap2D.GRASS_TILE)):
			missing.append(seed_value)
	check_eq(missing, [], "every seeded map contains all three biomes")


func test_ground_biomes_are_randomized_per_build() -> void:
	_grid._build_ground()
	var first: Dictionary = _grid._ground.duplicate(true)
	_grid._build_ground()
	var second: Dictionary = _grid._ground.duplicate(true)
	var differs: bool = false
	for cell: Vector2i in first:
		if first[cell]["atlas"] != second[cell]["atlas"] or first[cell]["alt"] != second[cell]["alt"]:
			differs = true
			break
	check(differs, "building the map again draws a different ground layout")


func test_minesite_restores_its_ground_tile_including_edge_art() -> void:
	_grid._build_ground()
	var edge_cell: Vector2i = Vector2i.ZERO
	_grid._ground[edge_cell] = {"atlas": GridMap2D.ROCK_DIRT_EDGE, "alt": TileSetAtlasSource.TRANSFORM_FLIP_V}
	var before: Dictionary = _grid._ground[edge_cell].duplicate()
	var with_edge_cell: Array[Vector2i] = _grid.minesites.duplicate()
	with_edge_cell.append(edge_cell)
	_grid.set_minesites(with_edge_cell)
	check(_grid.is_minesite(edge_cell), "the cell became a minesite")
	var without_edge_cell: Array[Vector2i] = []
	for c: Vector2i in _grid.minesites:
		if c != edge_cell:
			without_edge_cell.append(c)
	_grid.set_minesites(without_edge_cell)
	check_eq(_grid.get_cell_atlas_coords(edge_cell), before["atlas"], "its edge art is restored")
	check_eq(_grid.get_cell_alternative_tile(edge_cell), before["alt"], "with the same orientation")


func test_minesite_art_is_distinct_from_ground_tiles() -> void:
	var atlas: TileSetAtlasSource = _grid.tile_set.get_source(GridMap2D.SOURCE_ID)
	check(atlas.has_tile(GridMap2D.MINESITE_TILE), "minesite art exists in the atlas")
	for ground_tile: Vector2i in GridMap2D.BIOME_TILES:
		check(GridMap2D.MINESITE_TILE != ground_tile, "minesite and %s use different atlas cells" % ground_tile)
	var image: Image = atlas.texture.get_image()
	var origin: Vector2i = GridMap2D.MINESITE_TILE * atlas.texture_region_size
	var opaque: int = 0
	for x: int in atlas.texture_region_size.x:
		for y: int in atlas.texture_region_size.y:
			if image.get_pixel(origin.x + x, origin.y + y).a > 0.0:
				opaque += 1
	check(opaque > 0, "minesite artwork is visible, not an empty atlas cell")


func test_minesites() -> void:
	_grid._build_ground()
	check_eq(_grid.minesites.size(), GridMap2D.MINESITE_GROUPS * GridMap2D.GROUP_SIZE, "every minesite is listed")
	for cell: Vector2i in _grid.minesites:
		check(_grid.is_minesite(cell), "listed cell %s is a minesite" % cell)
	check(not _grid.is_minesite(Vector2i(16, 10)), "map center is not a minesite")
	check(not _grid.is_minesite(Vector2i(10, 8)), "an ordinary cell is not")


func _seeded(seed_value: int) -> Array[Vector2i]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return _grid.generate_minesites(rng)


func _touching(a: Vector2i, b: Vector2i) -> bool:
	return maxi(absi(a.x - b.x), absi(a.y - b.y)) < 2


## What is wrong with a layout (empty when it follows every rule).
func _problems(cells: Array[Vector2i]) -> Array[String]:
	var problems: Array[String] = []
	var size: Vector2i = autoload("GameState").GRID_SIZE
	var center: Vector2i = size / 2
	if cells.size() != GridMap2D.MINESITE_GROUPS * GridMap2D.GROUP_SIZE:
		return ["%d cells" % cells.size()]
	for index: int in cells.size():
		var cell: Vector2i = cells[index]
		if not Rect2i(Vector2i.ZERO, size).has_point(cell):
			problems.append("%s is off the map" % cell)
		if maxi(absi(cell.x - center.x), absi(cell.y - center.y)) < GridMap2D.COLLECTOR_CLEARANCE:
			problems.append("%s is too close to the collector" % cell)
		if cells.find(cell) != index:
			problems.append("%s is listed twice" % cell)
	for group: int in GridMap2D.MINESITE_GROUPS:
		var mine: Array[Vector2i] = cells.slice(group * 3, group * 3 + 3)
		var joined: int = 0
		for cell: Vector2i in mine:
			for other: Vector2i in mine:
				if cell.distance_squared_to(other) == 1:
					joined += 1
		if joined < 4:
			problems.append("group %d is not one piece" % group)
		for other_group: int in range(group + 1, GridMap2D.MINESITE_GROUPS):
			for cell: Vector2i in mine:
				for other: Vector2i in cells.slice(other_group * 3, other_group * 3 + 3):
					if _touching(cell, other):
						problems.append("groups %d and %d touch" % [group, other_group])
	for cell: Vector2i in cells.slice(0, 3):
		if maxi(absi(cell.x - center.x), absi(cell.y - center.y)) > GridMap2D.COLLECTOR_REACH:
			problems.append("%s is too far from the collector" % cell)
	return problems


func test_generated_minesites_follow_the_rules() -> void:
	for seed_value: int in 200:
		check_eq(_problems(_seeded(seed_value)), [], "seed %d: 4 groups of 3, apart, none within %d of the collector, one within %d" % [seed_value, GridMap2D.COLLECTOR_CLEARANCE, GridMap2D.COLLECTOR_REACH])


func test_the_layout_check_catches_a_bad_layout() -> void:
	var good: Array[Vector2i] = _seeded(1)
	var touching: Array[Vector2i] = good.duplicate()
	touching[3] = touching[0] + Vector2i(1, 1)
	check(not _problems(touching).is_empty(), "a group touching another is reported")
	var far: Array[Vector2i] = good.duplicate()
	far[0] = Vector2i(0, 0)
	check(not _problems(far).is_empty(), "a first group out of reach is reported")
	check(not _problems(good.slice(0, 9)).is_empty(), "a missing group is reported")
	var center: Vector2i = autoload("GameState").GRID_SIZE / 2
	var on_collector: Array[Vector2i] = good.duplicate()
	on_collector[1] = center
	check(not _problems(on_collector).is_empty(), "a site on the collector is reported")
	var beside: Array[Vector2i] = good.duplicate()
	beside[2] = center + Vector2i(GridMap2D.COLLECTOR_CLEARANCE - 1, -2)
	check(not _problems(beside).is_empty(), "a site closer than the clearance is reported")
	var at_limit: Array[Vector2i] = good.duplicate()
	at_limit[0] = center + Vector2i(GridMap2D.COLLECTOR_CLEARANCE, 0)
	at_limit[1] = at_limit[0] + Vector2i.RIGHT
	at_limit[2] = at_limit[0] + Vector2i.UP
	check_eq(_problems(at_limit).filter(func(text: String) -> bool: return text.contains("close") or text.contains("far")), [], "exactly at the clearance is allowed")


func test_minesites_are_random() -> void:
	var layouts: Dictionary = {}
	for seed_value: int in 20:
		layouts[_seeded(seed_value)] = true
	check(layouts.size() > 15, "different seeds give different layouts")
	check_eq(_seeded(7), _seeded(7), "the same seed gives the same layout")


func test_a_new_map_draws_a_new_layout_unless_one_is_forced() -> void:
	var forced: Array[Vector2i] = GridMap2D.layout_override.duplicate()
	GridMap2D.layout_override = []
	var layouts: Dictionary = {}
	for i: int in 6:
		_grid._build_ground()
		layouts[_grid.minesites.duplicate()] = true
		for cell: Vector2i in _grid.minesites:
			check(_grid.is_minesite(cell), "drawn site %s is painted" % cell)
	GridMap2D.layout_override = forced
	check(layouts.size() > 1, "building the map again draws other sites")
	_grid._build_ground()
	check_eq(_grid.minesites, forced, "a forced layout is used as is")
	check(_grid.is_minesite(forced[0]), "and painted")


func test_hovered_cell_conversion() -> void:
	var game_state: Node = autoload("GameState")
	var cell: Vector2i = Vector2i(5, 7)
	var world: Vector2 = game_state.cell_to_world(cell) + Vector2(3, 3)
	check_eq(_grid.get_hovered_cell(world), cell, "world position maps to its cell")
	check_eq(_grid.get_hovered_cell(Vector2(-10, -10)), Vector2i(-1, -1), "outside the grid is invalid")
	check_eq(_grid.get_hovered_cell(Vector2(game_state.GRID_SIZE * game_state.CELL_SIZE)), Vector2i(-1, -1), "past the far edge is invalid")


## Miner placement rules in the hover highlight. The scene must be in the tree for Placement to be ready.
const MINESITE: Vector2i = Vector2i(4, 4)
const PLAIN: Vector2i = Vector2i(10, 8)

var _saved_money: int = 0


func _enter_tree_with_money() -> Node:
	var game: Node = autoload("GameState")
	_saved_money = game.money
	game.money = 100
	tree.root.add_child(_main)
	return _main.get_node("Game/FactoryView/SubViewport/World/Placement")


func _color_at(cell: Vector2i) -> Color:
	_grid.hovered_cell = cell
	return _grid.hover_color()


func test_highlight_with_nothing_selected_is_the_plain_rule() -> void:
	var placement: Node = _enter_tree_with_money()
	check_eq(_color_at(PLAIN), _grid.HOVER_OK, "free ordinary cell is valid")
	check_eq(_color_at(MINESITE), _grid.HOVER_OK, "free minesite is valid")
	check_eq(_color_at(Vector2i(16, 10)), _grid.HOVER_BLOCKED, "occupied cell (collector) is blocked")
	autoload("GameState").money = _saved_money
	check(placement != null, "placement exists")


func test_miner_highlight_requires_a_minesite() -> void:
	var placement: Node = _enter_tree_with_money()
	placement.select("miner")
	check_eq(_color_at(PLAIN), _grid.HOVER_BLOCKED, "ordinary free cell looks invalid for a miner")
	check_eq(_color_at(MINESITE), _grid.HOVER_OK, "free minesite looks valid for a miner")
	check_eq(_color_at(Vector2i(16, 10)), _grid.HOVER_BLOCKED, "occupied cell stays blocked")
	placement.place("smelter", MINESITE)
	check_eq(_color_at(MINESITE), _grid.HOVER_BLOCKED, "an occupied minesite is blocked")
	autoload("GameState").money = _saved_money


func test_other_machines_may_use_minesites_and_ordinary_cells() -> void:
	var placement: Node = _enter_tree_with_money()
	for type: String in ["smelter", "assembler", "conveyor"]:
		placement.select(type)
		check_eq(_color_at(PLAIN), _grid.HOVER_OK, "%s: ordinary cell valid" % type)
		check_eq(_color_at(MINESITE), _grid.HOVER_OK, "%s: minesite valid" % type)
	autoload("GameState").money = _saved_money


func test_highlight_follows_the_selection() -> void:
	var placement: Node = _enter_tree_with_money()
	placement.select("miner")
	check_eq(_color_at(PLAIN), _grid.HOVER_BLOCKED, "miner selected")
	placement.select("")
	check_eq(_color_at(PLAIN), _grid.HOVER_OK, "cancel returns to the plain rule")
	placement.select("miner")
	autoload("GameState").money = 0
	placement.select("miner")
	check_eq(_grid.placement_type, "", "an unaffordable selection clears the highlight rule")
	autoload("GameState").money = _saved_money


func test_highlight_and_placement_agree() -> void:
	var placement: Node = _enter_tree_with_money()
	for cell: Vector2i in [PLAIN, MINESITE, Vector2i(16, 10)]:
		check_eq(_grid.can_place("miner", cell), placement.place("miner", cell) != null, "miner at %s" % cell)
	autoload("GameState").money = _saved_money


## set_hover_check lets a drag target something other than a free cell (a chip drag targets a machine).
func test_hover_check_overrides_the_default_rule() -> void:
	_grid.hovered_cell = PLAIN
	check_eq(_grid.hover_color(), _grid.HOVER_OK, "the default rule: a free cell, nothing selected")
	_grid.set_hover_check(func(_c: Vector2i) -> bool: return false)
	check_eq(_grid.hover_color(), _grid.HOVER_BLOCKED, "the override replaces it")
	_grid.clear_hover_check()
	check_eq(_grid.hover_color(), _grid.HOVER_OK, "clearing restores the default rule")


func test_set_hovered_cell_updates_the_same_state_as_real_mouse_motion() -> void:
	_grid.set_hovered_cell(PLAIN)
	check_eq(_grid.hovered_cell, PLAIN, "a drag drives the same hovered_cell mouse motion would")


func test_flash_refused_shows_then_clears_itself() -> void:
	tree.root.add_child(_main)
	_grid.flash_refused(PLAIN)
	check_eq(_grid._flash_cell, PLAIN, "the flash marks the refused cell")
	await wait_seconds(GridMap2D.REFUSE_FLASH_SECONDS + 0.05)
	check_eq(_grid._flash_cell, Vector2i(-1, -1), "and clears itself shortly after")
