class_name ProductionIndicator
extends Sprite2D
## Small badge at the corner of a producing machine's cell: green play while it is producing, red dash
## while its output is stalled (blocked), grey pause otherwise (switched off, or nothing to do right now).
## Separate from ChipIndicator (the outcome of the last chip call, above the machine): this one is always
## visible and reflects Machine.get_production_state(), refreshed every tick by Machine._on_tick().

const ICONS: Dictionary = {
	Machine.ProductionState.PRODUCING: "state_normal",
	Machine.ProductionState.STALLED: "blocked",
	Machine.ProductionState.IDLE: "state_paused",
}

var state: Machine.ProductionState = Machine.ProductionState.IDLE
## Items per minute as of the last refresh(), for anything that wants the number (the machine tooltip).
var rate: float = 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scale = Vector2(Icons.SCALE, Icons.SCALE)
	z_index = 10
	texture = Icons.icon(ICONS[state])


## The texture only changes when the state itself changes, so this is cheap to call every tick.
func refresh(new_state: Machine.ProductionState, new_rate: float) -> void:
	rate = new_rate
	if new_state == state:
		return
	state = new_state
	texture = Icons.icon(ICONS[state])
