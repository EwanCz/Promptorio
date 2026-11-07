extends "res://tests/test_case.gd"

var _camera: Camera2D
var _saved_size: Vector2i


func before_each() -> void:
	_saved_size = tree.root.size
	tree.root.size = Vector2i(1152, 648)
	_camera = load("res://scripts/world/camera.gd").new()
	tree.root.add_child(_camera)


func after_each() -> void:
	_camera.queue_free()
	tree.root.size = _saved_size


func _grid_size() -> Vector2:
	return Vector2(autoload("GameState").GRID_SIZE * autoload("GameState").CELL_SIZE)


func _visible_world_size() -> Vector2:
	return _camera.get_viewport_rect().size / _camera.zoom.x


func test_position_clamped_to_grid() -> void:
	var view: Vector2 = Vector2(1000, 600)
	var grid: Vector2 = Vector2(autoload("GameState").GRID_SIZE * autoload("GameState").CELL_SIZE)
	check_eq(_camera.get_clamped_position(Vector2(-500, -500), view), Vector2.ZERO, "clamped at top-left")
	check_eq(_camera.get_clamped_position(grid, view), grid - view, "clamped at bottom-right")
	check_eq(_camera.get_clamped_position(Vector2(100, 100), view), Vector2(100, 100), "inside is untouched")


func test_view_larger_than_grid_is_centered() -> void:
	var grid: Vector2 = Vector2(autoload("GameState").GRID_SIZE * autoload("GameState").CELL_SIZE)
	var view: Vector2 = grid * 2.0
	check_eq(_camera.get_clamped_position(Vector2(50, 50), view), -grid / 2.0, "centered when the view exceeds the grid")


func test_zoom_is_clamped() -> void:
	_camera.zoom_at(100.0, Vector2.ZERO)
	check(is_equal_approx(_camera.zoom.x, _camera.ZOOM_MAX), "zoom capped at max")
	_camera.zoom_at(0.0001, Vector2.ZERO)
	check(is_equal_approx(_camera.zoom.x, _camera.ZOOM_MIN), "zoom floored at min")


func test_starts_with_the_whole_grid_in_view() -> void:
	var visible: Vector2 = _visible_world_size()
	check(visible.x >= _grid_size().x - 0.01 and visible.y >= _grid_size().y - 0.01, "the view covers the grid on both axes")
	check(is_equal_approx(visible.x, _grid_size().x) or is_equal_approx(visible.y, _grid_size().y), "and no more than needed: one axis is filled exactly")
	var top_left: Vector2 = _camera.position
	check(top_left.x <= 0.01 and top_left.y <= 0.01, "the view starts at or before the grid corner")
	check(top_left.x + visible.x >= _grid_size().x - 0.01 and top_left.y + visible.y >= _grid_size().y - 0.01, "and reaches or passes the opposite corner")


func test_fit_works_in_a_view_too_small_for_the_usual_minimum_zoom() -> void:
	# The root window is stretched to at least the design size, so use a plain SubViewport like the game does.
	var holder: SubViewport = SubViewport.new()
	holder.size = Vector2i(300, 200)
	tree.root.add_child(holder)
	var camera: Camera2D = load("res://scripts/world/camera.gd").new()
	holder.add_child(camera)
	var visible: Vector2 = holder.get_visible_rect().size / camera.zoom.x
	check(camera.zoom.x < camera.ZOOM_MIN, "the fit zooms out past the usual floor")
	check(visible.x >= _grid_size().x - 0.01 and visible.y >= _grid_size().y - 0.01, "the whole grid is still in view")
	var fitted: float = camera.zoom.x
	camera.zoom_at(0.0001, Vector2.ZERO)
	check(is_equal_approx(camera.zoom.x, fitted), "zooming out never jumps back in past the fit")
	holder.free()


func test_keeps_fitting_when_resized_until_the_player_moves_the_view() -> void:
	tree.root.size = Vector2i(800, 800)
	await tree.process_frame
	check(_visible_world_size().x >= _grid_size().x - 0.01, "a resize refits the grid")
	check(is_equal_approx(_visible_world_size().x, _grid_size().x), "to the new width")
	_camera.zoom_at(1.5, Vector2.ZERO)
	var zoom: float = _camera.zoom.x
	tree.root.size = Vector2i(1152, 648)
	await tree.process_frame
	check_eq(_camera.zoom.x, zoom, "after the player zooms, a resize keeps the zoom")
