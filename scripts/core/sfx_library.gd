class_name SfxLibrary
extends Resource
## The cues `Sfx` can play, saved as `data/audio/sfx_library.tres`.

@export var cues: Array[SfxCue] = []


## The cue named `id`, or null when the library has none.
func find_cue(id: StringName) -> SfxCue:
	for cue: SfxCue in cues:
		if cue != null and cue.id == id:
			return cue
	return null
