class_name GridMap2D
extends TileMapLayer
## Ground tiles, minesites, hover highlight and cell clicks. Placement rules stay in GameState.

signal cell_hovered(cell: Vector2i)
signal cell_clicked(cell: Vector2i)

const SOURCE_ID: int = 0
const GROUND_TILES: Array[Vector2i] = [Vector2i(0, 0), Vector2i(2, 0)]
const MOSSY_TILES: Array[Vector2i] = [Vector2i(3, 0), Vector2i(0, 1), Vector2i(1, 1)]
const MINESITE_TILE: Vector2i = Vector2i(1, 0)
const MOSSY_CHANCE: float = 0.12
const MINESITES: Array[Vector2i] = [
	Vector2i(4, 4), Vector2i(5, 4), Vector2i(4, 5),
	Vector2i(26, 4), Vector2i(27, 4), Vector2i(27, 5),
	Vector2i(4, 15), Vector2i(5, 15), Vector2i(5, 14),
	Vector2i(26, 15), Vector2i(27, 15), Vector2i(26, 14),
]
const MAP_SEED: int = 1337
const HOVER_OK: Color = Color(0.2, 1.0, 0.3, 0.35)
const HOVER_BLOCKED: Color = Color(1.0, 0.2, 0.2, 0.35)

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


func _build_ground() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = MAP_SEED
	for x: int in GameState.GRID_SIZE.x:
		for y: int in GameState.GRID_SIZE.y:
			var pool: Array[Vector2i] = MOSSY_TILES if rng.randf() < MOSSY_CHANCE else GROUND_TILES
			set_cell(Vector2i(x, y), SOURCE_ID, pool[rng.randi() % pool.size()])
	for cell: Vector2i in MINESITES:
		set_cell(cell, SOURCE_ID, MINESITE_TILE)


func _set_hovered(cell: Vector2i) -> void:
	if cell == hovered_cell:
		return
	hovered_cell = cell
	queue_redraw()
	cell_hovered.emit(cell)
