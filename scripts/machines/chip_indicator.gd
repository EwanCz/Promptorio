class_name ChipIndicator
extends Sprite2D
## Small icon above a machine showing what its chips are doing: a spinner while any chip waits for
## an answer, then briefly the result of the last one (applied, none, failed). Driven by Machine.

const FRAME_SECONDS: float = 0.1

## How long a result icon stays, in seconds.
var result_seconds: float = 1.5
## "" (hidden), "checking", "applied", "none" or "failed".
var state: String = ""

var _time: float = 0.0
var _frames: Array[Texture2D] = []
var _timer: Timer


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scale = Vector2(Icons.SCALE, Icons.SCALE)
	z_index = 10
	_frames = Icons.spinner_frames()
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(clear)
	add_child(_timer)
	clear()


func _process(delta: float) -> void:
	_time += delta
	texture = _frames[int(_time / FRAME_SECONDS) % _frames.size()]


func show_pending() -> void:
	state = "checking"
	_timer.stop()
	texture = _frames[0]
	visible = true
	set_process(true)


## `outcome` is "applied", "none" or "failed".
func show_result(outcome: String) -> void:
	state = outcome
	texture = Icons.icon(outcome)
	visible = true
	set_process(false)
	_timer.start(result_seconds)


func clear() -> void:
	state = ""
	visible = false
	set_process(false)
	if _timer != null:
		_timer.stop()
