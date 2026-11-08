class_name GridMap2D
extends TileMapLayer
## Ground tiles, minesites, hover highlight and cell clicks. Placement rules stay in GameState.
## The minesites are drawn at random every time the map is built (see generate_minesites).

signal cell_hovered(cell: Vector2i)
signal cell_clicked(cell: Vector2i)

const SOURCE_ID: int = 0
const GROUND_TILES: Array[Vector2i] = [Vector2i(0, 0), Vector2i(2, 0)]
const MOSSY_TILES: Array[Vector2i] = [Vector2i(3, 0), Vector2i(0, 1), Vector2i(1, 1)]
const MINESITE_TILE: Vector2i = Vector2i(1, 0)
const MOSSY_CHANCE: float = 0.12
const MINESITE_GROUPS: int = 4
const GROUP_SIZE: int = 3
## The first group lies entirely within this many cells of the collector (in both directions).
const COLLECTOR_REACH: int = 10
## No minesite is closer than this many cells to the collector (in either direction): the collector's surroundings stay free.
const COLLECTOR_CLEARANCE: int = 5
## Tries to fit one group before giving up on it (a group fits at once on a map this empty).
const GROUP_ATTEMPTS: int = 200
const NEIGHBORS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const MAP_SEED: int = 1337
const HOVER_OK: Color = Color(0.2, 1.0, 0.3, 0.35)
const HOVER_BLOCKED: Color = Color(1.0, 0.2, 0.2, 0.35)

## Replaces the random minesites when it is not empty. The test runner sets it so layouts are repeatable.
static var layout_override: Array[Vector2i] = []

## Every minesite of the current map. The first GROUP_SIZE cells are the group near the collector.
var minesites: Array[Vector2i] = []
var hovered_cell: Vector2i = Vector2i(-1, -1)
## The machine type being placed ("" for none): the highlight follows its rules.
var placement_type: String = ""


func _ready() -> void:
	var tile_pixels: int = tile_set.tile_size.x
	scale = Vector2.ONE * float(GameState.CELL_SIZE) / float(tile_pixels)
	_build_ground()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_set_hovered(get_hovered_cell(get_global_mouse_position()))
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed and GameState.is_in_grid(hovered_cell):
			cell_clicked.emit(hovered_cell)


func _draw() -> void:
	if not GameState.is_in_grid(hovered_cell):
		return
	var tile_size: Vector2 = Vector2(tile_set.tile_size)
	draw_rect(Rect2(Vector2(hovered_cell) * tile_size, tile_size), hover_color())


## The placement rule for a machine type: a free cell inside the grid, and miners only on minesites.
func can_place(type: String, cell: Vector2i) -> bool:
	return GameState.can_place(cell) and (type != "miner" or is_minesite(cell))


func set_placement_type(type: String) -> void:
	placement_type = type
	queue_redraw()


func hover_color() -> Color:
	return HOVER_OK if can_place(placement_type, hovered_cell) else HOVER_BLOCKED


func get_hovered_cell(world_pos: Vector2) -> Vector2i:
	var cell: Vector2i = GameState.world_to_cell(world_pos)
	if GameState.is_in_grid(cell):
		return cell
	return Vector2i(-1, -1)


func is_minesite(cell: Vector2i) -> bool:
	return get_cell_source_id(cell) == SOURCE_ID and get_cell_atlas_coords(cell) == MINESITE_TILE


## MINESITE_GROUPS groups of GROUP_SIZE touching cells, no two groups touching, none closer than
## COLLECTOR_CLEARANCE cells to the collector. The first group is within COLLECTOR_REACH cells of it,
## so a miner spot is always near, but never right next to it.
func generate_minesites(rng: RandomNumberGenerator) -> Array[Vector2i]:
	var grid_area: Rect2i = Rect2i(Vector2i.ZERO, GameState.GRID_SIZE)
	var reach: Vector2i = Vector2i.ONE * COLLECTOR_REACH
	var near_area: Rect2i = Rect2i(_collector_cell() - reach, reach * 2 + Vector2i.ONE).intersection(grid_area)
	var cells: Array[Vector2i] = []
	for index: int in MINESITE_GROUPS:
		cells.append_array(_random_group(rng, near_area if index == 0 else grid_area, cells))
	return cells


func _collector_cell() -> Vector2i:
	return GameState.GRID_SIZE / 2


## GROUP_SIZE touching cells inside `area`, clear of `taken` and of the collector's surroundings. Empty if none was found.
func _random_group(rng: RandomNumberGenerator, area: Rect2i, taken: Array[Vector2i]) -> Array[Vector2i]:
	for attempt: int in GROUP_ATTEMPTS:
		var group: Array[Vector2i] = [area.position + Vector2i(rng.randi_range(0, area.size.x - 1), rng.randi_range(0, area.size.y - 1))]
		while group.size() < GROUP_SIZE:
			var next: Vector2i = group[rng.randi() % group.size()] + NEIGHBORS[rng.randi() % NEIGHBORS.size()]
			if area.has_point(next) and not group.has(next):
				group.append(next)
		if _group_fits(group, taken):
			return group
	return []


func _group_fits(group: Array[Vector2i], taken: Array[Vector2i]) -> bool:
	for cell: Vector2i in group:
		if _distance(cell, _collector_cell()) < COLLECTOR_CLEARANCE:
			return false
		for other: Vector2i in taken:
			if _distance(cell, other) < 2:
				return false
	return true


## Cells to walk to get from one to the other, diagonals counting as one step.
func _distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _build_ground() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = MAP_SEED
	for x: int in GameState.GRID_SIZE.x:
		for y: int in GameState.GRID_SIZE.y:
			var pool: Array[Vector2i] = MOSSY_TILES if rng.randf() < MOSSY_CHANCE else GROUND_TILES
			set_cell(Vector2i(x, y), SOURCE_ID, pool[rng.randi() % pool.size()])
	var site_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	site_rng.randomize()
	minesites = layout_override.duplicate() if not layout_override.is_empty() else generate_minesites(site_rng)
	for cell: Vector2i in minesites:
		set_cell(cell, SOURCE_ID, MINESITE_TILE)


func _set_hovered(cell: Vector2i) -> void:
	if cell == hovered_cell:
		return
	hovered_cell = cell
	queue_redraw()
	cell_hovered.emit(cell)
