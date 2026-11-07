class_name Conveyor
extends Machine
## Plain hardcoded transport: holds one item and hands it to the cell it faces after MOVE_TICKS.
## The frame art stays still and a Belt sprite scrolls the moving surface on top of it. The surface
## repeats every SCROLL_PERIOD pixels, so a full period of ticks puts it back on its first pose with
## no jump. Down and left are the up and right art flipped, which also flips the scroll direction.
const MOVE_TICKS: int = 5
const TEXTURE_SIZE: int = 16
## The horizontal art only repeats on the surface rows (its rivets do not), so only those scroll.
const SURFACE_TOP: int = 2
const SURFACE_ROWS: int = 8
## Pixels after which the belt art repeats itself.
const SCROLL_PERIOD: int = 8
## Pixels the belt moves each tick. It stays under half the period so the motion reads as one direction.
const SCROLL_PER_TICK: int = 2
const ARROWS: Dictionary = {
	Vector2i.RIGHT: "→", Vector2i.DOWN: "↓", Vector2i.LEFT: "←", Vector2i.UP: "↑",
}

## Belt art for a vertical conveyor (arrows up) and for a horizontal one (arrows right).
@export var up_texture: Texture2D
@export var side_texture: Texture2D

var held: String = ""

var _wait: int = 0

@onready var _belt: Sprite2D = get_node_or_null("Belt") as Sprite2D


func get_state() -> Dictionary:
	return super.get_state().merged({"direction": ARROWS.keys().find(facing), "holding": held != ""})


func _own_tool_schemas() -> Array:
	return [{
		"name": "set_direction",
		"description": "Turn the conveyor: 0 right, 1 down, 2 left, 3 up.",
		"input_schema": {"type": "object", "properties": {
			"direction": {"type": "integer", "minimum": 0, "maximum": ARROWS.size() - 1},
		}},
	}]


func receive(item: String) -> bool:
	if held != "" or status == Status.DOWN:
		return false
	held = item
	_wait = 0
	return true


func get_action_text() -> String:
	return "Facing %s, %s" % [ARROWS.get(facing, "?"), "holds %s" % held if held != "" else "empty"]


func clear_contents() -> void:
	held = ""
	_wait = 0


func _on_tick(tick_number: int) -> void:
	super._on_tick(tick_number)
	_scroll(tick_number)


func _update_sprite() -> void:
	if _sprite == null or _belt == null or up_texture == null or side_texture == null:
		return
	var horizontal: bool = facing.y == 0
	for sprite: Sprite2D in [_sprite, _belt]:
		sprite.texture = side_texture if horizontal else up_texture
		sprite.flip_h = facing == Vector2i.LEFT
		sprite.flip_v = facing == Vector2i.DOWN
	_belt.position = Vector2(0, SURFACE_TOP * _belt.scale.y) if horizontal else Vector2.ZERO
	_scroll(GameState.tick_count)


## Shifts the region of the repeating surface that the Belt sprite shows. The art points up (or
## right), so up samples further down the texture and right samples further left; the flips do the rest.
func _scroll(tick_number: int) -> void:
	if _belt == null:
		return
	var shift: int = (tick_number * SCROLL_PER_TICK) % SCROLL_PERIOD
	if facing.y == 0:
		_belt.region_rect = Rect2(Vector2((SCROLL_PERIOD - shift) % SCROLL_PERIOD, SURFACE_TOP), Vector2(TEXTURE_SIZE, SURFACE_ROWS))
	else:
		_belt.region_rect = Rect2(Vector2(0, shift), Vector2(TEXTURE_SIZE, TEXTURE_SIZE))


func _tick() -> void:
	if held == "":
		return
	_wait += 1
	if _wait >= MOVE_TICKS and _push(held):
		held = ""


func _apply(tool_name: String, args: Dictionary) -> void:
	if tool_name == "set_direction":
		facing = ARROWS.keys()[args["direction"]]
		return
	super._apply(tool_name, args)


func _status_text() -> String:
	return "•" if held != "" else ""
