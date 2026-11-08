class_name ProductionEffect
extends Node2D
## In-world feedback for a machine's production_state(): a few particles rising behind the sprite while
## producing, nothing while idle, and a small badge in the bottom-right corner while blocked. Driven once a
## tick by Machine; never reacts to simulation state on its own. Kept clear of ChipIndicator (above the
## sprite) and Miner's mode sprite (top-right), so it never obscures either.

## "producing", "idle" or "blocked". Kept so set_state() is a no-op when nothing changed.
var state: String = "idle"
var show_blocked_badge: bool = true

var _particles: CPUParticles2D
var _badge: Sprite2D


func _ready() -> void:
	_particles = CPUParticles2D.new()
	_particles.z_index = -1
	_particles.amount = 6
	_particles.lifetime = 0.8
	_particles.position = Vector2(8.0, 2.0)
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_particles.emission_sphere_radius = 6.0
	_particles.direction = Vector2.UP
	_particles.spread = 25.0
	_particles.gravity = Vector2.ZERO
	_particles.initial_velocity_min = 8.0
	_particles.initial_velocity_max = 14.0
	_particles.scale_amount_min = 1.5
	_particles.scale_amount_max = 2.5
	_particles.color = Color(1.0, 0.85, 0.3, 0.8)
	_particles.emitting = false
	add_child(_particles)
	_badge = Sprite2D.new()
	_badge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_badge.scale = Vector2(Icons.SCALE, Icons.SCALE)
	_badge.position = Vector2.ONE * GameState.CELL_SIZE - Vector2.ONE * (Icons.SIZE * Icons.SCALE / 2.0 + 2.0)
	_badge.z_index = 10
	_badge.texture = Icons.icon("blocked")
	_badge.visible = false
	add_child(_badge)


func set_state(new_state: String) -> void:
	if new_state == state:
		return
	state = new_state
	_particles.emitting = state == "producing"
	_badge.visible = state == "blocked" and show_blocked_badge
