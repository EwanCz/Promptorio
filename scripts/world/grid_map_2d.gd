class_name GridMap2D
extends TileMapLayer
## Ground tiles, minesites, hover highlight and cell clicks. Placement rules stay in GameState.
## The ground biomes and the minesites are both drawn at random every time the map is built (see
## _generate_ground and generate_minesites), so no two games start on the same layout.

signal cell_hovered(cell: Vector2i)
signal cell_clicked(cell: Vector2i)

const SOURCE_ID: int = 0
const DIRT_TILE: Vector2i = Vector2i(0, 0)
const ROCK_TILE: Vector2i = Vector2i(1, 0)
const GRASS_TILE: Vector2i = Vector2i(2, 0)
const DIRT_GRASS_EDGE: Vector2i = Vector2i(0, 1)
const ROCK_GRASS_EDGE: Vector2i = Vector2i(1, 1)
const MINESITE_TILE: Vector2i = Vector2i(2, 1)
const BIOME_TILES: Array[Vector2i] = [DIRT_TILE, ROCK_TILE, GRASS_TILE]
## One cluster grows from each seed cell (every other cell joins its nearest seed), so the ground reads
## as contiguous dirt/rock/grass patches instead of a single tile repeated everywhere.
const BIOME_SEED_COUNT: int = 16
## Checked in this order for the one neighbor (if any) a non-grass cell blends into; a cell between two
## foreign biomes (a corner) just gets whichever of these is checked first, not a dedicated corner tile.
const EDGE_DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.RIGHT, Vector2i.LEFT]
## Orients the "grass above, other biome below" edge art so the grass side faces each direction.
const EDGE_TRANSFORMS: Dictionary = {
	Vector2i.UP: 0,
	Vector2i.DOWN: TileSetAtlasSource.TRANSFORM_FLIP_V,
	Vector2i.RIGHT: TileSetAtlasSource.TRANSFORM_TRANSPOSE | TileSetAtlasSource.TRANSFORM_FLIP_H,
	Vector2i.LEFT: TileSetAtlasSource.TRANSFORM_TRANSPOSE,
}
const MINESITE_GROUPS: int = 4
const GROUP_SIZE: int = 3
## The first group lies entirely within this many cells of the collector (in both directions).
const COLLECTOR_REACH: int = 10
## No minesite is closer than this many cells to the collector (in either direction): the collector's surroundings stay free.
const COLLECTOR_CLEARANCE: int = 5
## Tries to fit one group before giving up on it (a group fits at once on a map this empty).
const GROUP_ATTEMPTS: int = 200
const NEIGHBORS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const HOVER_OK: Color = Color(0.2, 1.0, 0.3, 0.35)
const HOVER_BLOCKED: Color = Color(1.0, 0.2, 0.2, 0.35)
const REFUSE_FLASH_COLOR: Color = Color(1.0, 0.2, 0.2, 0.6)
const REFUSE_FLASH_SECONDS: float = 0.25

## Replaces the random minesites when it is not empty. The test runner sets it so layouts are repeatable.
static var layout_override: Array[Vector2i] = []

## Every minesite of the current map. The first GROUP_SIZE cells are the group near the collector.
var minesites: Array[Vector2i] = []
## The ground tile under every cell ({"atlas": Vector2i, "alt": int}), so a cell that stops being a
## minesite gets its own back.
var _ground: Dictionary = {}
var hovered_cell: Vector2i = Vector2i(-1, -1)
## The machine type being placed ("" for none): the highlight follows its rules.
var placement_type: String = ""
## Overrides can_place() for the hover highlight while set (a chip drag targets machines, not free cells).
## Takes a cell, returns whether it is a valid drop target. Cleared by clear_hover_check().
var _hover_check: Callable = Callable()
var _flash_cell: Vector2i = Vector2i(-1, -1)
@onready var _flash_timer: Timer = Timer.new()


func _ready() -> void:
	var tile_pixels: int = tile_set.tile_size.x
	scale = Vector2.ONE * float(GameState.CELL_SIZE) / float(tile_pixels)
	_flash_timer.one_shot = true
	_flash_timer.timeout.connect(_clear_flash)
	add_child(_flash_timer)
	_build_ground()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_set_hovered(get_hovered_cell(get_global_mouse_position()))
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed and GameState.is_in_grid(hovered_cell):
			cell_clicked.emit(hovered_cell)


func _draw() -> void:
	var tile_size: Vector2 = Vector2(tile_set.tile_size)
	if GameState.is_in_grid(hovered_cell):
		draw_rect(Rect2(Vector2(hovered_cell) * tile_size, tile_size), hover_color())
	if GameState.is_in_grid(_flash_cell):
		draw_rect(Rect2(Vector2(_flash_cell) * tile_size, tile_size), REFUSE_FLASH_COLOR)


## The placement rule for a machine type: a free cell inside the grid, and miners only on minesites.
func can_place(type: String, cell: Vector2i) -> bool:
	return GameState.can_place(cell) and (type != "miner" or is_minesite(cell))


func set_placement_type(type: String) -> void:
	placement_type = type
	queue_redraw()


## Drives the hover highlight from outside (a drag over the map, which has no mouse motion event of its
## own to trigger it through _unhandled_input).
func set_hovered_cell(cell: Vector2i) -> void:
	_set_hovered(cell)


## While set, `check` decides the hover highlight color instead of can_place(placement_type, cell): used
## while dragging a chip, which targets a machine, not a free cell.
func set_hover_check(check: Callable) -> void:
	_hover_check = check
	queue_redraw()


func clear_hover_check() -> void:
	_hover_check = Callable()
	queue_redraw()


## A brief red flash on a cell where a drop was refused, so the refusal reads where the player was looking.
func flash_refused(cell: Vector2i) -> void:
	_flash_cell = cell
	queue_redraw()
	_flash_timer.start(REFUSE_FLASH_SECONDS)


func _clear_flash() -> void:
	_flash_cell = Vector2i(-1, -1)
	queue_redraw()


func hover_color() -> Color:
	var ok: bool = _hover_check.call(hovered_cell) if _hover_check.is_valid() else can_place(placement_type, hovered_cell)
	return HOVER_OK if ok else HOVER_BLOCKED


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
	rng.randomize()
	_ground = _generate_ground(rng)
	for cell: Vector2i in _ground:
		var tile: Dictionary = _ground[cell]
		set_cell(cell, SOURCE_ID, tile["atlas"], tile["alt"])
	var site_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	site_rng.randomize()
	set_minesites(layout_override.duplicate() if not layout_override.is_empty() else generate_minesites(site_rng))


## One biome cluster per seed cell (a random dirt/rock/grass cell), every other cell joining whichever
## seed is nearest: a cheap stand-in for proper noise that still gives contiguous patches. A second pass
## turns a dirt or rock cell touching grass into the matching edge tile, oriented toward the grass side.
func _generate_ground(rng: RandomNumberGenerator) -> Dictionary:
	var seeds: Array = []
	for i: int in BIOME_SEED_COUNT:
		seeds.append({
			"cell": Vector2i(rng.randi_range(0, GameState.GRID_SIZE.x - 1), rng.randi_range(0, GameState.GRID_SIZE.y - 1)),
			"biome": BIOME_TILES[rng.randi() % BIOME_TILES.size()],
		})
	var ground: Dictionary = {}
	for x: int in GameState.GRID_SIZE.x:
		for y: int in GameState.GRID_SIZE.y:
			var cell: Vector2i = Vector2i(x, y)
			ground[cell] = {"atlas": _nearest_biome(cell, seeds), "alt": 0}
	for cell: Vector2i in ground.keys():
		var biome: Vector2i = ground[cell]["atlas"]
		if biome == GRASS_TILE:
			continue
		var edge: Vector2i = DIRT_GRASS_EDGE if biome == DIRT_TILE else ROCK_GRASS_EDGE
		for direction: Vector2i in EDGE_DIRECTIONS:
			var neighbor: Variant = ground.get(cell + direction)
			if neighbor != null and neighbor["atlas"] == GRASS_TILE:
				ground[cell] = {"atlas": edge, "alt": EDGE_TRANSFORMS[direction]}
				break
	return ground


func _nearest_biome(cell: Vector2i, seeds: Array) -> Vector2i:
	var best_biome: Vector2i = seeds[0]["biome"]
	var best_dist: int = -1
	for entry: Dictionary in seeds:
		var dist: int = (cell - (entry["cell"] as Vector2i)).length_squared()
		if best_dist == -1 or dist < best_dist:
			best_dist = dist
			best_biome = entry["biome"]
	return best_biome


## Makes these cells the map's minesites (a loaded save puts its own back). The previous ones turn back into ground.
func set_minesites(cells: Array[Vector2i]) -> void:
	for cell: Vector2i in minesites:
		var tile: Dictionary = _ground[cell]
		set_cell(cell, SOURCE_ID, tile["atlas"], tile["alt"])
	minesites = cells.duplicate()
	for cell: Vector2i in minesites:
		set_cell(cell, SOURCE_ID, MINESITE_TILE)


func _set_hovered(cell: Vector2i) -> void:
	if cell == hovered_cell:
		return
	hovered_cell = cell
	queue_redraw()
	cell_hovered.emit(cell)
