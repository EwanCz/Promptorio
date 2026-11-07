class_name Smelter
extends CraftMachine
## Smelts ore into ingots. Working heats it up, idling cools it, and set_cooling cools it faster.
## Above OVERHEAT_AT it is OVERHEATING; at EXPLODE_AT it explodes (fail state): it goes DOWN, flashes and
## fades out, then is destroyed and frees its cell. The art turns redder as it heats up.

const AMBIENT: float = 20.0
const HEAT_PER_TICK: float = 0.6
const COOL_PER_TICK: float = 0.3
const COOLING_EXTRA_PER_TICK: float = 0.3
const OVERHEAT_AT: float = 100.0
const SAFE_AT: float = 80.0
const EXPLODE_AT: float = 150.0
## The art starts to redden at TINT_FROM and is fully HOT_COLOR at EXPLODE_AT.
const TINT_FROM: float = 60.0
const HOT_COLOR: Color = Color(1.0, 0.15, 0.1)
const EXPLOSION_SECONDS: float = 0.6
const FLASH_COLOR: Color = Color(3.0, 2.2, 0.8)

var temperature: float = AMBIENT
var cooling: bool = false


func _own_tool_schemas() -> Array:
	return [{
		"name": "set_cooling",
		"description": "Turn the cooling on or off. Cooling only slows the heating while working (it cannot keep a working smelter stable), and speeds up the cooldown while idle.",
		"input_schema": {"type": "object", "properties": {"on": {"type": "boolean"}}},
	}] + super._own_tool_schemas()


func get_state() -> Dictionary:
	return super.get_state().merged({"temperature": roundi(temperature), "cooling": cooling})


func get_action_text() -> String:
	return "%s\nTemperature: %d°, cooling %s" % [super.get_action_text(), roundi(temperature), "on" if cooling else "off"]


func _apply(tool_name: String, args: Dictionary) -> void:
	if tool_name == "set_cooling":
		cooling = args["on"]
		return
	super._apply(tool_name, args)


func _tick() -> void:
	var working: bool = is_working()
	super._tick()
	var change: float = HEAT_PER_TICK if working else -COOL_PER_TICK
	if cooling:
		change -= COOLING_EXTRA_PER_TICK
	temperature = maxf(AMBIENT, temperature + change)
	_update_heat_tint()
	if temperature >= EXPLODE_AT:
		_explode()
	elif temperature >= OVERHEAT_AT:
		status = Status.OVERHEATING
	elif status == Status.OVERHEATING and temperature <= SAFE_AT:
		status = Status.NORMAL


func _status_text() -> String:
	return "BOOM" if status == Status.DOWN else "%d°" % roundi(temperature)


## White while cool, then redder and redder up to HOT_COLOR at the explosion temperature.
func _update_heat_tint() -> void:
	if _sprite != null:
		_sprite.modulate = Color.WHITE.lerp(HOT_COLOR, clampf(inverse_lerp(TINT_FROM, EXPLODE_AT, temperature), 0.0, 1.0))


func _explode() -> void:
	status = Status.DOWN
	clear_contents()
	log_chip("exploded at %d°" % roundi(temperature))
	EventBus.machine_exploded.emit(self)
	_play_explosion()


## Flash, then fade out with a burst of sparks, and destroy the smelter when it is over. Not in the tree
## (so nothing to play): destroyed at once.
func _play_explosion() -> void:
	if _sprite == null or not is_inside_tree():
		destroy()
		return
	var sparks: CPUParticles2D = CPUParticles2D.new()
	sparks.position = _sprite.texture.get_size() * _sprite.scale / 2.0 if _sprite.texture != null else Vector2.ZERO
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = 24
	sparks.lifetime = EXPLOSION_SECONDS
	sparks.spread = 180.0
	sparks.initial_velocity_min = 80.0
	sparks.initial_velocity_max = 220.0
	sparks.gravity = Vector2.ZERO
	sparks.scale_amount_min = 3.0
	sparks.scale_amount_max = 6.0
	sparks.color = Color(1.0, 0.5, 0.1)
	add_child(sparks)
	sparks.emitting = true
	var tween: Tween = create_tween()
	tween.tween_property(_sprite, "modulate", FLASH_COLOR, EXPLOSION_SECONDS * 0.2)
	tween.tween_property(_sprite, "modulate", Color(HOT_COLOR, 0.0), EXPLOSION_SECONDS * 0.8)
	tween.finished.connect(destroy)
