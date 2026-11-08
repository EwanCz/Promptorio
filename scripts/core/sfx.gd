extends Node
## Sound effects: `Sfx.play(&"cue", world_position)`. A fixed pool of non-positional players, a global voice cap,
## per-cue cooldown and voice limits, and an optional world position that only makes a sound quieter the farther
## it is from the camera. Cues come from an `SfxLibrary`; an unknown cue warns once and is ignored.

## A cue request that was accepted and is now sounding.
signal cue_played(cue: StringName)

const MASTER_BUS: StringName = &"Master"
const SFX_BUS: StringName = &"SFX"
const UI_BUS: StringName = &"UI"
const LIBRARY_PATH: String = "res://data/audio/sfx_library.tres"
## Lowest volume a bus is set to; a linear volume of 0 mutes it instead.
const MIN_DB: float = -80.0
## Up to this many world pixels (on screen) from the camera, a positioned cue is at full volume.
const NEAR_DISTANCE: float = 400.0
## Past this distance a positioned cue is at its quietest.
const FAR_DISTANCE: float = 1600.0
const FAR_ATTENUATION_DB: float = -24.0
const LIMITER_CEILING_DB: float = -0.5
## Stands for "played long ago" when a cue has not played yet.
const NEVER_MSEC: int = -1000000000

## Players in the pool: the most sounds that can play together.
@export var pool_size: int = 16

## Cues to play. Loaded from `LIBRARY_PATH` on startup when it exists and nothing was set before; else empty.
var library: SfxLibrary
## Every `play()` call.
var request_count: int = 0
## Plays that started a voice.
var played_count: int = 0
## Plays dropped by a cooldown, the pause rule or mute.
var dropped_count: int = 0
## Plays that cut an older voice because the cue or the whole pool was full.
var stolen_count: int = 0
## Plays of an unknown cue.
var unknown_count: int = 0
var muted: bool = false

var _voices: Array[Voice] = []
var _last_played_msec: Dictionary = {}
var _warned_cues: Dictionary = {}
var _serial: int = 0
var _listener: Camera2D
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## One player of the pool and what it is playing.
class Voice extends RefCounted:
	var player: AudioStreamPlayer
	var cue: StringName = &""
	## Orders voices by age; a bigger number started later.
	var serial: int = 0

	func is_active() -> bool:
		return player.playing


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_ensure_buses()
	if library == null:
		library = _load_library()
	for i: int in maxi(pool_size, 1):
		var voice: Voice = Voice.new()
		voice.player = AudioStreamPlayer.new()
		voice.player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(voice.player)
		_voices.append(voice)


func _exit_tree() -> void:
	stop_all()


## Volume change for a sound `distance` pixels from the camera: 0 dB when near, falling linearly to
## `FAR_ATTENUATION_DB` when far. Never louder than the cue, never silent.
static func distance_attenuation_db(distance: float) -> float:
	if is_nan(distance) or distance <= NEAR_DISTANCE:
		return 0.0
	var amount: float = clampf((distance - NEAR_DISTANCE) / (FAR_DISTANCE - NEAR_DISTANCE), 0.0, 1.0)
	return FAR_ATTENUATION_DB * amount


## Plays `cue`. With a world `position`, the sound is quieter the farther it is from the listener camera.
func play(cue: StringName, position: Vector2 = Vector2.INF) -> void:
	request_count += 1
	var def: SfxCue = library.find_cue(cue) if library != null else null
	if def == null or def.stream == null:
		_report_unknown(cue)
		return
	if muted or (get_tree().paused and not def.ui):
		dropped_count += 1
		return
	var now: int = _now_msec()
	if now - int(_last_played_msec.get(cue, NEVER_MSEC)) < int(def.cooldown_sec * 1000.0):
		dropped_count += 1
		return
	var voice: Voice = _take_voice(def)
	_last_played_msec[cue] = now
	_serial += 1
	voice.cue = cue
	voice.serial = _serial
	var player: AudioStreamPlayer = voice.player
	player.stream = def.stream
	player.bus = UI_BUS if def.ui else SFX_BUS
	player.volume_db = def.volume_db + _attenuation_for(position)
	player.pitch_scale = 1.0 + _rng.randf_range(-def.pitch_jitter, def.pitch_jitter)
	player.play()
	played_count += 1
	cue_played.emit(cue)


## Cuts every sound that is playing and forgets the cooldowns. Call it when the scene changes.
func stop_all() -> void:
	for voice: Voice in _voices:
		voice.player.stop()
		voice.cue = &""
	_last_played_msec.clear()


## The camera whose position sounds are measured from. Without one, the viewport's current camera is used.
func set_listener(camera: Camera2D) -> void:
	_listener = camera


## Sets a bus (`SFX_BUS`, `UI_BUS` or `MASTER_BUS`) to a 0..1 linear volume; 0 mutes it.
func set_bus_volume_linear(bus: StringName, volume: float) -> void:
	var index: int = AudioServer.get_bus_index(bus)
	if index == -1:
		push_warning("Sfx: unknown audio bus '%s'" % bus)
		return
	var linear: float = clampf(volume, 0.0, 1.0)
	AudioServer.set_bus_mute(index, linear <= 0.0)
	AudioServer.set_bus_volume_db(index, maxf(linear_to_db(linear), MIN_DB))


## Mutes or restores all sound. While muted, `play()` does nothing.
func set_muted(mute: bool) -> void:
	muted = mute
	AudioServer.set_bus_mute(AudioServer.get_bus_index(MASTER_BUS), mute)
	if mute:
		stop_all()


## How many voices are sounding `cue`, or any cue when `cue` is empty.
func get_voice_count(cue: StringName = &"") -> int:
	var count: int = 0
	for voice: Voice in _voices:
		if voice.is_active() and (cue == &"" or voice.cue == cue):
			count += 1
	return count


## The pool players that are sounding right now.
func get_active_players() -> Array[AudioStreamPlayer]:
	var players: Array[AudioStreamPlayer] = []
	for voice: Voice in _voices:
		if voice.is_active():
			players.append(voice.player)
	return players


## Milliseconds clock for cooldowns. Tests override it.
func _now_msec() -> int:
	return Time.get_ticks_msec()


func _load_library() -> SfxLibrary:
	if ResourceLoader.exists(LIBRARY_PATH):
		var loaded: SfxLibrary = load(LIBRARY_PATH) as SfxLibrary
		if loaded != null:
			return loaded
		push_warning("Sfx: %s is not an SfxLibrary" % LIBRARY_PATH)
	return SfxLibrary.new()


func _ensure_buses() -> void:
	for bus: StringName in [SFX_BUS, UI_BUS]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var index: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, MASTER_BUS)
	var master: int = AudioServer.get_bus_index(MASTER_BUS)
	for effect_index: int in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, effect_index) is AudioEffectHardLimiter:
			return
	var limiter: AudioEffectHardLimiter = AudioEffectHardLimiter.new()
	limiter.ceiling_db = LIMITER_CEILING_DB
	AudioServer.add_bus_effect(master, limiter)


## A free voice, else the oldest voice of this cue if the cue is full, else the oldest voice overall.
func _take_voice(def: SfxCue) -> Voice:
	var oldest: Voice = null
	var oldest_of_cue: Voice = null
	var cue_voices: int = 0
	for voice: Voice in _voices:
		if not voice.is_active():
			continue
		if oldest == null or voice.serial < oldest.serial:
			oldest = voice
		if voice.cue == def.id:
			cue_voices += 1
			if oldest_of_cue == null or voice.serial < oldest_of_cue.serial:
				oldest_of_cue = voice
	if cue_voices >= maxi(def.max_voices, 1):
		stolen_count += 1
		oldest_of_cue.player.stop()
		return oldest_of_cue
	for voice: Voice in _voices:
		if not voice.is_active():
			return voice
	stolen_count += 1
	oldest.player.stop()
	return oldest


func _attenuation_for(position: Vector2) -> float:
	if not position.is_finite():
		return 0.0
	var camera: Camera2D = _listener if is_instance_valid(_listener) else get_viewport().get_camera_2d()
	if camera == null:
		return 0.0
	var distance: float = position.distance_to(camera.get_screen_center_position()) * camera.zoom.x
	return distance_attenuation_db(distance)


func _report_unknown(cue: StringName) -> void:
	unknown_count += 1
	if not _warned_cues.has(cue):
		_warned_cues[cue] = true
		push_warning("Sfx: unknown or empty cue '%s'" % cue)
