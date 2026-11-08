class_name Conveyor
extends Machine
## Plain hardcoded transport: holds one item and hands it to the cell it faces after MOVE_TICKS.
## The frame art stays still and a Belt sprite scrolls the moving surface on top of it. The surface
## repeats every SCROLL_PERIOD pixels, so a full period of ticks puts it back on its first pose with
## no jump. Down and left are the up and right art flipped, which also flips the scroll direction.
const MOVE_TICKS: int = 5
const TEXTURE_SIZE: int = 16
## The item icon rests at the center of the cell.
const ICON_CENTER: Vector2 = Vector2(32, 32)
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

## The item on the belt ("" for none). Its icon is drawn over the conveyor.
var held: String = "":
	set(value):
		held = value
		_update_item_icon()

var _wait: int = 0
## True when the item arrived during the current tick before this conveyor's turn in it: that tick must not
## count, or the item would be one tick ahead on every conveyor that plays after its sender.
var _skip_tick: bool = false
## Where the held item came from, in pixels from this cell's center (zero when it was put here directly).
## The icon glides from there to the center over MOVE_TICKS, so it slides from one machine to the next.
var _slide_from: Vector2 = Vector2.ZERO

@onready var _belt: Sprite2D = get_node_or_null("Belt") as Sprite2D
@onready var _item_icon: Sprite2D = get_node_or_null("ItemIcon") as Sprite2D


func _ready() -> void:
	super._ready()
	_update_item_icon()


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
	_slide_from = Vector2.ZERO
	_skip_tick = false
	held = item
	_wait = 0
	return true


func note_sender(sender_cell: Vector2i, sender_tick: int) -> void:
	_skip_tick = sender_tick != _tick_number
	# What a Smelter or an Assembler makes is put straight on the belt; only an item coming off another belt (or a miner) slides in.
	var from_craft_machine: bool = GameState.get_machine_at(sender_cell) is CraftMachine
	_slide_from = Vector2.ZERO if from_craft_machine else Vector2(sender_cell - cell) * GameState.CELL_SIZE
	_place_item_icon()


func get_action_text() -> String:
	return "Facing %s, %s" % [ARROWS.get(facing, "?"), "holds %s" % held if held != "" else "empty"]


func clear_contents() -> void:
	held = ""
	_wait = 0
	_skip_tick = false
	_slide_from = Vector2.ZERO


func _save_data() -> Dictionary:
	return {"held": held, "wait": _wait}


func _load_data(data: Dictionary) -> void:
	_slide_from = Vector2.ZERO
	held = _read_item(data, "held", ItemCatalog.shared().get_ids())
	_wait = _read_int(data, "wait", 0, 0, MOVE_TICKS)
	_place_item_icon()


func _process(_delta: float) -> void:
	_place_item_icon()


func _on_tick(tick_number: int) -> void:
	super._on_tick(tick_number)
	_scroll(tick_number)
	_place_item_icon()


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
	if _skip_tick:
		_skip_tick = false
	else:
		_wait += 1
	if _wait >= MOVE_TICKS and _push(held):
		held = ""


func honors_enabled() -> bool:
	return false


func _apply(tool_name: String, args: Dictionary) -> bool:
	if tool_name == "set_direction":
		facing = ARROWS.keys()[args["direction"]]
		return true
	return super._apply(tool_name, args)


## Shows the held item's icon, or nothing when the belt is empty (or the item has no icon).
func _update_item_icon() -> void:
	if _item_icon == null:
		return
	var data: ItemData = ItemCatalog.shared().get_item(held)
	_item_icon.texture = null if data == null else data.icon
	_item_icon.visible = _item_icon.texture != null
	_place_item_icon()


## How far the held item is along its way to the center of this cell, 0 to 1: the ticks waited plus the part of
## the current tick already gone. A blocked item (waited MOVE_TICKS) rests at the center.
func get_slide_progress() -> float:
	if _wait >= MOVE_TICKS:
		return 1.0
	return (float(_wait) + GameState.tick_fraction()) / float(MOVE_TICKS)


func _place_item_icon() -> void:
	if _item_icon != null and held != "":
		_item_icon.position = ICON_CENTER + _slide_from * (1.0 - get_slide_progress())
