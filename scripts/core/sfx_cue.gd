class_name SfxCue
extends Resource
## One named sound effect: the stream and how `Sfx` may play it.

## Name passed to `Sfx.play()`.
@export var id: StringName = &""
@export var stream: AudioStream
@export_range(-40.0, 12.0, 0.1, "suffix:dB") var volume_db: float = 0.0
## Random pitch spread: the pitch scale is 1.0 plus or minus this much (0.05 is about +-5%).
@export_range(0.0, 0.5, 0.01) var pitch_jitter: float = 0.0
## Minimum time between two plays of this cue. Requests inside it are dropped.
@export_range(0.0, 5.0, 0.01, "suffix:s") var cooldown_sec: float = 0.0
## Most copies of this cue sounding at once. A new play beyond it cuts the oldest copy.
@export_range(1, 16) var max_voices: int = 4
## Plays on the UI bus and keeps sounding while the game is paused. Gameplay cues are dropped while paused.
@export var ui: bool = false
