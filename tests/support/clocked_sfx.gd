extends "res://scripts/core/sfx.gd"
## Test double: an Sfx whose clock is set by hand, so cooldowns need no waiting.

var now_msec: int = 0


func _now_msec() -> int:
	return now_msec
