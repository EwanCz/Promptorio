extends Node
## Audio engine (autoload `Sfx`). Code asks for a sound by name, `Sfx.play(&"cue", world_position)`, and never
## owns players, buses or limits. Cues come from `SfxLibrary` (data/sfx.tres). A fixed pool of
## AudioStreamPlayers plays them, so 50 machines asking at once never become 50 sounds: a cue has a cooldown
## and a voice cap, and the pool has a global cap that steals a voice when full.
##
## Rules: an unknown cue is ignored with one warning; a simulation cue is dropped while the game is paused and a
## UI cue still plays; a position only lowers the volume with the distance from the listening camera (no 2D
## positional nodes); the simulation voices stop when the scene changes (UI voices finish, so a button click
## is not cut by the scene it opens). Nothing here needs an audio device: with the Dummy driver the same
## rules run, and tests read `played` and `stats`.

## A sound actually started. `position` is Vector2.INF for a sound without a place.
signal played(cue: StringName, position: Vector2, volume_db: float, pitch_scale: float)

const BUS_SFX: StringName = &"SFX"
const BUS_UI: StringName = &"UI"
const BUS_MASTER: StringName = &"Master"
const POOL_SIZE: int = 16
## Screen-space distance (world distance x camera zoom, in pixels) with no attenuation, and the one past which
## a sound is silent and is not played at all.
const FULL_VOLUME_RADIUS: float = 500.0
const SILENT_RADIUS: float = 1800.0
const SILENT_DB: float = -60.0
const LIMITER_CEILING_DB: float = -0.5

## The cue table. Tests swap it for their own and put it back.
var library: SfxLibrary
## Counters by outcome: requested, played, unknown, cooldown, paused, too_far, stolen, dropped.
var stats: Dictionary = {}

var _voices: Array[Voice] = []
var _last_play_msec: Dictionary = {}
var _warned: Dictionary = {}
var _listener: Camera2D
var _scene: Node
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## One player of the pool and what it is playing.
class Voice extends RefCounted:
	var player: AudioStreamPlayer
	var cue: StringName = &""
	var ui: bool = false
	var volume_db: float = 0.0
	var started_msec: int = 0

	func is_busy() -> bool:
		return cue != &"" and player.playing


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	library = load(SfxLibrary.PATH) as SfxLibrary
	setup_buses()
	apply_volumes()
	for i: int in POOL_SIZE:
		var voice: Voice = Voice.new()
		voice.player = AudioStreamPlayer.new()
		voice.player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(voice.player)
		_voices.append(voice)
	reset_stats()
	_scene = get_tree().current_scene


func _process(_delta: float) -> void:
	var current: Node = get_tree().current_scene
	if current != _scene:
		_scene = current
		stop_all(false)


## Plays a cue once. `position` is a world position: a far one is quieter, a very far one is not played.
## `pitch_scale` multiplies the cue's jittered pitch (1.0 keeps it). Returns true when a sound started.
func play(cue_id: StringName, position: Vector2 = Vector2.INF, pitch_scale: float = 1.0) -> bool:
	_count("requested")
	var cue: SfxCue = library.get_cue(cue_id) if library != null else null
	if cue == null or cue.stream == null:
		_warn_unknown(cue_id)
		_count("unknown")
		return false
	if not cue.ui and get_tree().paused:
		_count("paused")
		return false
	var now: int = Time.get_ticks_msec()
	if _last_play_msec.has(cue_id) and now - int(_last_play_msec[cue_id]) < int(cue.cooldown * 1000.0):
		_count("cooldown")
		return false
	var volume_db: float = cue.volume_db
	if position.is_finite():
		volume_db += distance_attenuation_db(_screen_distance(position))
	if volume_db <= SILENT_DB:
		_count("too_far")
		return false
	var voice: Voice = _acquire_voice(cue, volume_db)
	if voice == null:
		_count("dropped")
		return false
	var pitch: float = maxf(pitch_scale, 0.01) * (1.0 + _rng.randf_range(-cue.pitch_jitter, cue.pitch_jitter))
	voice.cue = cue_id
	voice.ui = cue.ui
	voice.volume_db = volume_db
	voice.started_msec = now
	voice.player.stream = cue.stream
	voice.player.bus = BUS_UI if cue.ui else BUS_SFX
	voice.player.volume_db = volume_db
	voice.player.pitch_scale = pitch
	voice.player.play()
	_last_play_msec[cue_id] = now
	_count("played")
	played.emit(cue_id, position, volume_db, pitch)
	return true


## Stops every voice and lets go of its stream. With `include_ui` false the UI voices finish on their own.
func stop_all(include_ui: bool = true) -> void:
	for voice: Voice in _voices:
		if voice.cue != &"" and (include_ui or not voice.ui):
			voice.player.stop()
			voice.player.stream = null
			voice.cue = &""


## Voices playing now (all, or the ones of one cue).
func active_voices(cue_id: StringName = &"") -> int:
	var count: int = 0
	for voice: Voice in _voices:
		if voice.is_busy() and (cue_id == &"" or voice.cue == cue_id):
			count += 1
	return count


## The camera whose centre and zoom position sounds. `FactoryCamera` registers itself; none: no attenuation.
func set_listener(camera: Camera2D) -> void:
	_listener = camera


func reset_stats() -> void:
	stats = {"requested": 0, "played": 0, "unknown": 0, "cooldown": 0, "paused": 0, "too_far": 0, "stolen": 0, "dropped": 0}
	_last_play_msec.clear()
	_warned.clear()


func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(BUS_MASTER), Settings.volume_to_db(Settings.master_volume))
	AudioServer.set_bus_mute(AudioServer.get_bus_index(BUS_MASTER), Settings.muted)
	var effects: int = AudioServer.get_bus_index(BUS_SFX)
	if effects >= 0:
		AudioServer.set_bus_volume_db(effects, Settings.volume_to_db(Settings.sfx_volume))


## Gain in dB for a screen-space distance: 0 inside FULL_VOLUME_RADIUS, then a linear fade of the amplitude to
## silence (SILENT_DB) at SILENT_RADIUS.
static func distance_attenuation_db(distance: float) -> float:
	if distance <= FULL_VOLUME_RADIUS:
		return 0.0
	if distance >= SILENT_RADIUS:
		return SILENT_DB
	var fade: float = (distance - FULL_VOLUME_RADIUS) / (SILENT_RADIUS - FULL_VOLUME_RADIUS)
	return maxf(linear_to_db(1.0 - fade), SILENT_DB)


## Creates the SFX and UI buses under Master and a limiter on Master, once. Done in code so
## default_bus_layout.tres is never hand-edited.
static func setup_buses() -> void:
	for bus_name: StringName in [BUS_SFX, BUS_UI]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var index: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, BUS_MASTER)
	var master: int = AudioServer.get_bus_index(BUS_MASTER)
	for i: int in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter:
			return
	var limiter: AudioEffectHardLimiter = AudioEffectHardLimiter.new()
	limiter.ceiling_db = LIMITER_CEILING_DB
	AudioServer.add_bus_effect(master, limiter)


## A free voice; else, when the cue is at its own cap, its oldest voice; else the quietest voice (the
## oldest among equals) if the new sound is not quieter. Null drops the new sound.
func _acquire_voice(cue: SfxCue, volume_db: float) -> Voice:
	var same_cue: Array[Voice] = []
	var free: Voice = null
	for voice: Voice in _voices:
		if voice.is_busy():
			if voice.cue == cue.id:
				same_cue.append(voice)
		elif free == null:
			free = voice
	if same_cue.size() >= cue.max_voices:
		return _steal(_oldest(same_cue))
	if free != null:
		return free
	var victim: Voice = null
	for voice: Voice in _voices:
		if victim == null or voice.volume_db < victim.volume_db \
				or (voice.volume_db == victim.volume_db and voice.started_msec < victim.started_msec):
			victim = voice
	if victim.volume_db > volume_db:
		return null
	return _steal(victim)


func _steal(voice: Voice) -> Voice:
	voice.player.stop()
	voice.cue = &""
	_count("stolen")
	return voice


func _oldest(voices: Array[Voice]) -> Voice:
	var oldest: Voice = voices[0]
	for voice: Voice in voices:
		if voice.started_msec < oldest.started_msec:
			oldest = voice
	return oldest


## Distance from the listening camera in screen pixels (world distance x zoom). 0 without a camera.
func _screen_distance(position: Vector2) -> float:
	if not is_instance_valid(_listener):
		return 0.0
	return position.distance_to(_listener.global_position) * _listener.zoom.x


func _warn_unknown(cue_id: StringName) -> void:
	if _warned.has(cue_id):
		return
	_warned[cue_id] = true
	push_warning("Sfx: unknown cue '%s' (or it has no stream), ignored" % cue_id)


func _count(key: String) -> void:
	stats[key] = int(stats[key]) + 1
