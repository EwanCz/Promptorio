class_name GridMap2D
extends TileMapLayer
## Ground tiles, minesites, hover highlight and cell clicks. Placement rules stay in GameState.
## The ground biomes and the minesites are both drawn at random every time the map is built
## (see generate_biomes and generate_minesites).

signal cell_hovered(cell: Vector2i)
signal cell_clicked(cell: Vector2i)

## A ground biome: the clustered terrain the map is built from before minesites are cut into it.
enum Biome { DIRT, ROCK, GRASS }

const SOURCE_ID: int = 0
const BIOME_TILE: Dictionary = {Biome.DIRT: Vector2i(0, 0), Biome.ROCK: Vector2i(1, 0), Biome.GRASS: Vector2i(2, 0)}
## The straight biome/grass edge tile for a non-grass biome (grass tile has none: it never borders itself).
const EDGE_TILE: Dictionary = {Biome.DIRT: Vector2i(0, 1), Biome.ROCK: Vector2i(1, 1)}
## Edge tiles are drawn grass-above by default; this orients them toward whichever side the grass neighbor is on.
const EDGE_ALT_FOR_DIRECTION: Dictionary = {
	Vector2i.UP: 0,
	Vector2i.DOWN: TileSetAtlasSource.TRANSFORM_FLIP_V,
	Vector2i.LEFT: TileSetAtlasSource.TRANSFORM_TRANSPOSE,
	Vector2i.RIGHT: TileSetAtlasSource.TRANSFORM_TRANSPOSE | TileSetAtlasSource.TRANSFORM_FLIP_H,
}
const MINESITE_TILE: Vector2i = Vector2i(2, 1)
## Random count of Voronoi-style biome seed points per map: fewer means larger, simpler patches.
const BIOME_SEEDS_MIN: int = 7
const BIOME_SEEDS_MAX: int = 12
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
## The ground tile (atlas coords + alternative/transform id) under every cell, so a cell that
## stops being a minesite gets its own back.
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


## One Voronoi-style seed per clustered patch: biome_rng picks their count, position and type, then
## every cell takes the biome of its nearest seed. A handful of seeds scattered over a GRID_SIZE map
## naturally yields a few large, contiguous, differently-shaped patches per biome, not a checkerboard.
func generate_biomes(biome_rng: RandomNumberGenerator) -> Dictionary:
	var biome_types: Array[Biome] = [Biome.DIRT, Biome.ROCK, Biome.GRASS]
	var seeds: Array[Dictionary] = []
	for i: int in biome_rng.randi_range(BIOME_SEEDS_MIN, BIOME_SEEDS_MAX):
		var pos: Vector2i = Vector2i(biome_rng.randi_range(0, GameState.GRID_SIZE.x - 1), biome_rng.randi_range(0, GameState.GRID_SIZE.y - 1))
		seeds.append({"pos": pos, "biome": biome_types[biome_rng.randi() % biome_types.size()]})
	for biome: Biome in biome_types:
		if not seeds.any(func(s: Dictionary) -> bool: return s["biome"] == biome):
			seeds[biome_rng.randi() % seeds.size()]["biome"] = biome
	var biomes: Dictionary = {}
	for x: int in GameState.GRID_SIZE.x:
		for y: int in GameState.GRID_SIZE.y:
			var cell: Vector2i = Vector2i(x, y)
			var nearest: Dictionary = seeds[0]
			var nearest_dist: int = _squared_distance(cell, seeds[0]["pos"])
			for seed_point: Dictionary in seeds:
				var dist: int = _squared_distance(cell, seed_point["pos"])
				if dist < nearest_dist:
					nearest = seed_point
					nearest_dist = dist
			biomes[cell] = nearest["biome"]
	return biomes


func _squared_distance(a: Vector2i, b: Vector2i) -> int:
	var delta: Vector2i = a - b
	return delta.x * delta.x + delta.y * delta.y


## The atlas coords + transform for one ground cell: its plain biome tile, unless a grass neighbor
## calls for the biome/grass edge tile oriented toward that neighbor.
func _ground_tile(cell: Vector2i, biomes: Dictionary) -> Dictionary:
	var biome: Biome = biomes[cell]
	if EDGE_TILE.has(biome):
		for direction: Vector2i in NEIGHBORS:
			if biomes.get(cell + direction, biome) == Biome.GRASS:
				return {"coords": EDGE_TILE[biome], "alt": EDGE_ALT_FOR_DIRECTION[direction]}
	return {"coords": BIOME_TILE[biome], "alt": 0}


func _build_ground() -> void:
	var biome_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	biome_rng.randomize()
	var biomes: Dictionary = generate_biomes(biome_rng)
	for x: int in GameState.GRID_SIZE.x:
		for y: int in GameState.GRID_SIZE.y:
			var cell: Vector2i = Vector2i(x, y)
			var tile: Dictionary = _ground_tile(cell, biomes)
			_ground[cell] = tile
			set_cell(cell, SOURCE_ID, tile["coords"], tile["alt"])
	var site_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	site_rng.randomize()
	set_minesites(layout_override.duplicate() if not layout_override.is_empty() else generate_minesites(site_rng))


## Makes these cells the map's minesites (a loaded save puts its own back). The previous ones turn back into ground.
func set_minesites(cells: Array[Vector2i]) -> void:
	for cell: Vector2i in minesites:
		set_cell(cell, SOURCE_ID, _ground[cell]["coords"], _ground[cell]["alt"])
	minesites = cells.duplicate()
	for cell: Vector2i in minesites:
		set_cell(cell, SOURCE_ID, MINESITE_TILE)


func _set_hovered(cell: Vector2i) -> void:
	if cell == hovered_cell:
		return
	hovered_cell = cell
	queue_redraw()
	cell_hovered.emit(cell)
