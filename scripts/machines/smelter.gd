class_name Smelter
extends CraftMachine
## Smelts ore into ingots. Working heats it up, idling cools it, and set_cooling cools it faster.
## Above OVERHEAT_AT it is OVERHEATING; at EXPLODE_AT it explodes and stays DOWN (fail state).

const AMBIENT: float = 20.0
const HEAT_PER_TICK: float = 0.6
const COOL_PER_TICK: float = 0.3
const COOLING_EXTRA_PER_TICK: float = 0.7
const OVERHEAT_AT: float = 100.0
const SAFE_AT: float = 80.0
const EXPLODE_AT: float = 150.0

var temperature: float = AMBIENT
var cooling: bool = false


func _own_tool_schemas() -> Array:
	return [{
		"name": "set_cooling",
		"description": "Turn the cooling on or off. Cooling lowers the temperature faster but is needed while working.",
		"input_schema": {"type": "object", "properties": {"on": {"type": "boolean"}}},
	}]


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
	if temperature >= EXPLODE_AT:
		_explode()
	elif temperature >= OVERHEAT_AT:
		status = Status.OVERHEATING
	elif status == Status.OVERHEATING and temperature <= SAFE_AT:
		status = Status.NORMAL


func _status_text() -> String:
	return "BOOM" if status == Status.DOWN else "%s %d°" % [machine_type, roundi(temperature)]


func _explode() -> void:
	status = Status.DOWN
	clear_contents()
	log_chip("exploded at %d°" % roundi(temperature))
	EventBus.machine_exploded.emit(self)
