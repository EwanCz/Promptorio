extends "res://tests/test_case.gd"

var _camera: Camera2D


func before_each() -> void:
	_camera = load("res://scripts/world/camera.gd").new()
	(Engine.get_main_loop() as SceneTree).root.add_child(_camera)


func after_each() -> void:
	_camera.queue_free()


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
