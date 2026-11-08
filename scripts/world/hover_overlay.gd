class_name HoverOverlay
extends Node2D
## Draws GridMap2D's hover highlight and refuse-flash. Kept as its own node, placed after Machines in the
## World tree, so a machine's sprite (drawn after GridMap2D) never hides the highlight underneath it.
## GridMap2D owns the hover state; this only mirrors its transform and redraws on redraw_requested.

@export var grid: GridMap2D


func _ready() -> void:
	position = grid.position
	scale = grid.scale
	grid.redraw_requested.connect(queue_redraw)


func _draw() -> void:
	var tile_size: Vector2 = Vector2(grid.tile_set.tile_size)
	if GameState.is_in_grid(grid.hovered_cell):
		draw_rect(Rect2(Vector2(grid.hovered_cell) * tile_size, tile_size), grid.hover_color())
	if GameState.is_in_grid(grid._flash_cell):
		draw_rect(Rect2(Vector2(grid._flash_cell) * tile_size, tile_size), GridMap2D.REFUSE_FLASH_COLOR)
