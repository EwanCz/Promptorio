class_name FactoryView
extends SubViewportContainer
## Drop target for dragging a building from the Build page, or a chip from the Chip Registry page, onto the
## map. at_position (Control-local to this node) is converted into a world position through the active
## camera's canvas_transform, so a drop lands on the right cell at any zoom or pan. Reuses GridMap2D's hover
## rectangle for live feedback while the drag is over it (see set_hover_check/set_hovered_cell).

@export var grid: GridMap2D
@export var placement: Placement
@export var viewport: SubViewport

## True while a drag of ours is overriding the grid's hover highlight (set in _can_drop_data, cleared once
## Viewport.gui_is_dragging() goes false, however the drag ended: dropped here, dropped elsewhere, or
## cancelled). Polling avoids depending on exactly which controls a DRAG_END notification reaches.
var _overriding_hover: bool = false


func _process(_delta: float) -> void:
	if _overriding_hover and not get_viewport().gui_is_dragging():
		_overriding_hover = false
		grid.clear_hover_check()
		grid.set_placement_type(placement.selected)


## True while the point is over a cell this drag could land on: a free, affordable, in-bounds cell for a
## machine, or a cell with a machine on it for a chip. Godot calls this continuously while dragging over us.
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var cell: Vector2i = _cell_at(at_position)
	if not GameState.is_in_grid(cell):
		grid.set_hovered_cell(Vector2i(-1, -1))
		return false
	if data.has("machine_type"):
		grid.clear_hover_check()
		grid.set_placement_type(data["machine_type"])
		grid.set_hovered_cell(cell)
		_overriding_hover = true
		return true
	if data.has("chip_id"):
		grid.set_hover_check(func(c: Vector2i) -> bool: return GameState.get_machine_at(c) != null)
		grid.set_hovered_cell(cell)
		_overriding_hover = true
		return true
	return false


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var cell: Vector2i = _cell_at(at_position)
	if data.has("machine_type"):
		if placement.try_place(data["machine_type"], cell) == null:
			grid.flash_refused(cell)
	elif data.has("chip_id"):
		_attach_chip(cell, int(data["chip_id"]))


func _attach_chip(cell: Vector2i, chip_id: int) -> void:
	var machine: Machine = GameState.get_machine_at(cell) as Machine
	if machine == null:
		grid.flash_refused(cell)
		return
	if machine.attach_chip(chip_id) == null:
		machine.indicator.show_result("failed")
		return
	machine.indicator.show_result("applied")


## World position of `at_position` (local to this control) through the viewport's own camera, then the
## grid cell under it ((-1, -1) outside the map).
func _cell_at(at_position: Vector2) -> Vector2i:
	if size.x <= 0.0 or size.y <= 0.0:
		return Vector2i(-1, -1)
	var viewport_pos: Vector2 = at_position * (Vector2(viewport.size) / size)
	var world_pos: Vector2 = viewport.canvas_transform.affine_inverse() * viewport_pos
	return grid.get_hovered_cell(world_pos)
