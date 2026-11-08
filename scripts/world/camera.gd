class_name FactoryCamera
extends Camera2D
## Wheel zoom around the cursor, middle-drag / arrow keys pan, clamped to the grid. It starts zoomed out
## so the whole grid is visible, and keeps fitting it while the view is resized until the player zooms or pans.

const ZOOM_MIN: float = 0.4
const ZOOM_MAX: float = 2.0
const ZOOM_STEP: float = 1.1
const PAN_SPEED: float = 900.0

var _dragging: bool = false
var _auto_fit: bool = true


func _ready() -> void:
	Sfx.set_listener(self)
	get_viewport().size_changed.connect(_on_viewport_resized)
	fit_to_grid()


func _process(delta: float) -> void:
	var direction: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if direction != Vector2.ZERO:
		pan(direction * PAN_SPEED * delta / zoom.x)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				zoom_at(ZOOM_STEP, get_viewport().get_mouse_position())
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom_at(1.0 / ZOOM_STEP, get_viewport().get_mouse_position())
			MOUSE_BUTTON_MIDDLE:
				_dragging = button.pressed
	elif event is InputEventMouseMotion and _dragging:
		var motion: InputEventMouseMotion = event
		pan(-motion.relative / zoom.x)


## Zooms out just enough for the whole grid to be visible, and centers it.
func fit_to_grid() -> void:
	_auto_fit = true
	zoom = Vector2.ONE * _fit_zoom()
	position = get_clamped_position(position, _view_size())


func pan(world_delta: Vector2) -> void:
	_auto_fit = false
	position = get_clamped_position(position + world_delta, _view_size())


func zoom_at(factor: float, screen_pos: Vector2) -> void:
	_auto_fit = false
	var old_zoom: float = zoom.x
	var new_zoom: float = clampf(old_zoom * factor, minf(ZOOM_MIN, _fit_zoom()), ZOOM_MAX)
	var anchor: Vector2 = position + screen_pos / old_zoom
	zoom = Vector2.ONE * new_zoom
	position = get_clamped_position(anchor - screen_pos / new_zoom, _view_size())


## Keeps the visible area inside the grid; centers it on an axis where the view is larger than the grid.
func get_clamped_position(pos: Vector2, view_world_size: Vector2) -> Vector2:
	var grid_size: Vector2 = Vector2(GameState.GRID_SIZE * GameState.CELL_SIZE)
	var result: Vector2 = pos
	for axis: int in 2:
		var slack: float = grid_size[axis] - view_world_size[axis]
		result[axis] = slack / 2.0 if slack <= 0.0 else clampf(pos[axis], 0.0, slack)
	return result


## Zoom at which the grid exactly fills the view on its tighter axis.
func _fit_zoom() -> float:
	var grid_size: Vector2 = Vector2(GameState.GRID_SIZE * GameState.CELL_SIZE)
	var view: Vector2 = get_viewport_rect().size
	return minf(view.x / grid_size.x, view.y / grid_size.y)


func _on_viewport_resized() -> void:
	if _auto_fit:
		fit_to_grid()


func _view_size() -> Vector2:
	return get_viewport_rect().size / zoom.x
