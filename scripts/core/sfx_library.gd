class_name SfxLibrary
extends Resource
## Every cue of the game, shipped in data/sfx.tres. `Sfx` reads it.

const PATH: String = "res://data/sfx.tres"

@export var cues: Array[SfxCue] = []

var _index: Dictionary = {}
var _indexed_count: int = -1


## Null for an unknown id.
func get_cue(id: StringName) -> SfxCue:
	if _indexed_count != cues.size():
		_index.clear()
		for cue: SfxCue in cues:
			_index[cue.id] = cue
		_indexed_count = cues.size()
	return _index.get(id) as SfxCue
