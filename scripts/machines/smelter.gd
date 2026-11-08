class_name Smelter
extends CraftMachine
## Smelts ore into ingots. Working heats it up and idling cools it. Cooling is a trade-off. Cooling off runs
## flat out: crafts take 1/UNCOOLED_SPEEDUP of the recipe time, and it heats up while working. Cooling on
## takes COOLED_CRAFT_FACTOR times the recipe time and the smelter cools even while working. The factor
## applies to the next craft.
## Above OVERHEAT_AT it is OVERHEATING; at EXPLODE_AT it explodes (fail state): it goes DOWN, flashes and
## fades out, then is destroyed and frees its cell. The art turns redder as it heats up.

const AMBIENT: float = 20.0
const HEAT_PER_TICK: float = 0.6
const COOL_PER_TICK: float = 0.3
## Idle only: cooling on adds this to COOL_PER_TICK (-0.6 in all).
const COOLING_EXTRA_PER_TICK: float = 0.3
## Net change per tick while working with cooling on: the temperature falls.
const COOLED_WORK_PER_TICK: float = -0.2
const COOLED_CRAFT_FACTOR: int = 2
## Cooling off: crafts are this many times faster than the recipe time.
const UNCOOLED_SPEEDUP: int = 2
const OVERHEAT_AT: float = 100.0
const SAFE_AT: float = 80.0
const EXPLODE_AT: float = 150.0
## The art starts to redden at TINT_FROM and is fully HOT_COLOR at EXPLODE_AT.
const TINT_FROM: float = 60.0
const HOT_COLOR: Color = Color(1.0, 0.15, 0.1)
## The art trembles only from SHAKE_FROM (the overheating line) up to SHAKE_MAX_PIXELS at EXPLODE_AT, and
## almost imperceptibly until about 120 degrees (cubic growth).
const SHAKE_FROM: float = 100.0
const SHAKE_MAX_PIXELS: float = 4.0
const SHAKE_HZ: float = 25.0
const EXPLOSION_SECONDS: float = 0.6
const FLASH_COLOR: Color = Color(3.0, 2.2, 0.8)

var temperature: float = AMBIENT
var cooling: bool = false
## True while the smelter is stopped by set_emergency_stop(on=true). Any set_enabled call clears it, so a
## pause from another chip is never mistaken for the emergency stop.
var emergency_stop: bool = false

var _shake_time: float = 0.0


## How far the art may move at this temperature, in pixels: 0 up to SHAKE_FROM, then growing smoothly
## and slowly at first (cubic: about 0.26 px at 120, 1.4 px at 135) to SHAKE_MAX_PIXELS at EXPLODE_AT.
static func shake_amplitude(heat: float) -> float:
	var fraction: float = clampf(inverse_lerp(SHAKE_FROM, EXPLODE_AT, heat), 0.0, 1.0)
	return SHAKE_MAX_PIXELS * fraction * fraction * fraction


func _process(delta: float) -> void:
	_shake_time += delta
	_set_shake(shake_offset(_shake_time))


## The art's offset at `time`: a quick wobble of the current amplitude, none once the smelter is down
## (the explosion plays on the art's own position).
func shake_offset(time: float) -> Vector2:
	var amplitude: float = 0.0 if status == Status.DOWN else shake_amplitude(temperature)
	if amplitude <= 0.0:
		return Vector2.ZERO
	var phase: float = time * SHAKE_HZ * TAU
	return Vector2(sin(phase), cos(phase * 0.83 + 1.3)) * amplitude


func _set_shake(offset: Vector2) -> void:
	if offset != _sprite_offset:
		_sprite_offset = offset
		_place_sprite()


func _own_tool_schemas() -> Array:
	return [{
		"name": "set_cooling",
		"description": "Turn cooling on or off. While on, the smelter cools even while working but crafts take about four times as long as with cooling off (rounding can affect the ratio); duration is chosen when a craft starts. Cooling also speeds recovery while idle.",
		"input_schema": {"type": "object", "properties": {"on": {"type": "boolean"}}},
	}, {
		"name": "set_emergency_stop",
		"description": "on=true: stop this smelter and mark it as an emergency stop (emergency_stop in the state). on=false: resume it only if it is still in that emergency stop; a pause set by anything else (set_enabled) stays in effect.",
		"input_schema": {"type": "object", "properties": {"on": {"type": "boolean"}}},
	}] + super._own_tool_schemas()


func get_state() -> Dictionary:
	return super.get_state().merged({"temperature": roundi(temperature), "cooling": cooling, "emergency_stop": emergency_stop})


## An exploding smelter is already lost, so a save leaves it out.
func is_saveable() -> bool:
	return temperature < EXPLODE_AT


func _save_data() -> Dictionary:
	return super._save_data().merged({"temperature": temperature, "cooling": cooling, "emergency_stop": emergency_stop})


func _load_data(data: Dictionary) -> void:
	super._load_data(data)
	temperature = _read_float(data, "temperature", AMBIENT, AMBIENT, EXPLODE_AT - 1.0)
	cooling = data.get("cooling") == true
	emergency_stop = data.get("emergency_stop") == true and not enabled
	_update_heat_tint()


func _apply(tool_name: String, args: Dictionary) -> bool:
	if tool_name == "set_cooling":
		cooling = args["on"]
		return true
	if tool_name == "set_emergency_stop":
		if args["on"]:
			enabled = false
			emergency_stop = true
		elif emergency_stop:
			enabled = true
			emergency_stop = false
		return true
	if tool_name == "set_enabled":
		emergency_stop = false
	return super._apply(tool_name, args)


func _tick() -> void:
	var working: bool = is_working()
	super._tick()
	var change: float = -COOL_PER_TICK - (COOLING_EXTRA_PER_TICK if cooling else 0.0)
	if working:
		change = COOLED_WORK_PER_TICK if cooling else HEAT_PER_TICK
	temperature = maxf(AMBIENT, temperature + change)
	_update_heat_tint()
	if temperature >= EXPLODE_AT:
		_explode()
	elif temperature >= OVERHEAT_AT:
		status = Status.OVERHEATING
	elif status == Status.OVERHEATING and temperature <= SAFE_AT:
		status = Status.NORMAL


func _craft_ticks() -> int:
	if cooling:
		return super._craft_ticks() * COOLED_CRAFT_FACTOR
	return maxi(1, super._craft_ticks() / UNCOOLED_SPEEDUP)


func _max_saved_progress(item: String) -> int:
	return super._max_saved_progress(item) * COOLED_CRAFT_FACTOR


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
	_set_shake(Vector2.ZERO)
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
