extends "res://scripts/core/sfx_events.gd"
## Test double: an SfxEvents whose clock is set by hand, so hold-offs need no waiting.

var now_msec: int = 0


func _now_msec() -> int:
	return now_msec
