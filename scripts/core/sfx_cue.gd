class_name SfxCue
extends Resource
## One named sound of the game and how it may be played. The table of cues is `SfxLibrary` (data/sfx.tres).

## The name code passes to `Sfx.play()`.
@export var id: StringName = &""
@export var stream: AudioStream
@export_range(-60.0, 12.0, 0.1) var volume_db: float = 0.0
## Random pitch spread: the pitch scale is drawn in 1 +/- pitch_jitter, so repeats do not sound identical.
@export_range(0.0, 0.5, 0.01) var pitch_jitter: float = 0.0
## Minimum seconds between two plays of this cue. Requests inside the window are dropped.
@export_range(0.0, 5.0, 0.01) var cooldown: float = 0.05
## Simultaneous voices of this cue. At the cap the oldest voice of the cue is replaced.
@export_range(1, 16, 1) var max_voices: int = 2
## A UI cue goes to the UI bus and plays while the game is paused. Any other cue is a simulation
## cue: it goes to the SFX bus and is dropped while the game is paused.
@export var ui: bool = false
