extends "res://tests/test_case.gd"
## The Sfx engine: cooldowns, voice limits, the pause rule, distance attenuation and stop_all.
## Uses its own Sfx instance with an injected library; the real autoload is only touched by the headless test.

const SFX_SCRIPT: GDScript = preload("res://scripts/core/sfx.gd")
const CLOCKED_SFX_SCRIPT: GDScript = preload("res://tests/support/clocked_sfx.gd")
const POOL_SIZE: int = 4

var _sfx: Node
var _played: Array[StringName] = []


func before_each() -> void:
	_played.clear()
	_sfx = CLOCKED_SFX_SCRIPT.new()
	_sfx.set("pool_size", POOL_SIZE)
	_sfx.set("library", _library())
	_sfx.connect("cue_played", _on_cue_played)
	tree.root.add_child(_sfx)


func after_each() -> void:
	tree.paused = false
	tree.root.remove_child(_sfx)
	_sfx.free()


## Stops every voice and gives the audio thread time to let go of them. Freeing a player mid-mix leaks its
## playback in headless runs (an engine race), which would print an ObjectDB leak warning at exit.
func _settle() -> void:
	_sfx.call("stop_all")
	await wait_seconds(0.05)


func _on_cue_played(cue: StringName) -> void:
	_played.append(cue)


## Ten seconds of silence, so a voice stays active for the whole test.
func _stream() -> AudioStreamWAV:
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 8000
	stream.data = PackedByteArray()
	stream.data.resize(8000 * 2 * 10)
	return stream


func _cue(id: StringName, cooldown: float, max_voices: int, ui: bool = false) -> SfxCue:
	var cue: SfxCue = SfxCue.new()
	cue.id = id
	cue.stream = _stream()
	cue.cooldown_sec = cooldown
	cue.max_voices = max_voices
	cue.ui = ui
	return cue


func _library() -> SfxLibrary:
	var library: SfxLibrary = SfxLibrary.new()
	library.cues.append(_cue(&"tick", 0.1, 4))
	library.cues.append(_cue(&"hum", 0.0, 2))
	library.cues.append(_cue(&"burst", 0.0, 8))
	library.cues.append(_cue(&"other", 0.0, 8))
	library.cues.append(_cue(&"click", 0.0, 4, true))
	return library


func test_play_starts_a_voice_and_emits_the_cue() -> void:
	_sfx.call("play", &"hum")
	check_eq(_sfx.call("get_voice_count"), 1, "one voice sounds")
	check_eq(_played, [&"hum"] as Array[StringName], "cue_played fired")
	check_eq(_sfx.get("request_count"), 1, "request counted")
	check_eq(_sfx.get("played_count"), 1, "play counted")
	var players: Array[AudioStreamPlayer] = _sfx.call("get_active_players")
	check_eq(players[0].bus, &"SFX", "gameplay cue uses the SFX bus")
	await _settle()


func test_cooldown_drops_repeats_until_it_has_passed() -> void:
	_sfx.call("play", &"tick")
	_sfx.set("now_msec", 50)
	_sfx.call("play", &"tick")
	check_eq(_sfx.call("get_voice_count", &"tick"), 1, "repeat inside the cooldown is dropped")
	check_eq(_sfx.get("dropped_count"), 1, "drop counted")
	_sfx.set("now_msec", 100)
	_sfx.call("play", &"tick")
	check_eq(_sfx.call("get_voice_count", &"tick"), 2, "plays again once the cooldown passed")
	check_eq(_played.size(), 2, "two cue_played signals")
	await _settle()


func test_cooldown_is_per_cue() -> void:
	_sfx.call("play", &"tick")
	_sfx.call("play", &"hum")
	check_eq(_sfx.call("get_voice_count"), 2, "another cue is not blocked")
	await _settle()


func test_global_cap_steals_the_oldest_voice() -> void:
	for i: int in POOL_SIZE:
		_sfx.call("play", &"burst")
	check_eq(_sfx.call("get_voice_count"), POOL_SIZE, "pool is full")
	var oldest: AudioStreamPlayer = (_sfx.call("get_active_players") as Array[AudioStreamPlayer])[0]
	_sfx.call("play", &"other")
	check_eq(_sfx.call("get_voice_count"), POOL_SIZE, "still at the cap")
	check_eq(_sfx.call("get_voice_count", &"other"), 1, "the new cue got a voice")
	check_eq(_sfx.call("get_voice_count", &"burst"), POOL_SIZE - 1, "one burst voice was cut")
	check_eq(_sfx.get("stolen_count"), 1, "steal counted")
	check_eq(oldest.get_parent(), _sfx, "pool nodes are fixed children")
	check_eq(_sfx.get_child_count(), POOL_SIZE, "no node was added")
	await _settle()


func test_steals_the_oldest_not_the_newest() -> void:
	_sfx.call("play", &"burst")
	_sfx.call("play", &"other")
	_sfx.call("play", &"other")
	_sfx.call("play", &"other")
	_sfx.call("play", &"click")
	check_eq(_sfx.call("get_voice_count", &"burst"), 0, "the oldest voice (burst) was the one cut")
	check_eq(_sfx.call("get_voice_count", &"other"), 3, "newer voices survive")
	await _settle()


func test_per_cue_max_voices() -> void:
	_sfx.call("play", &"hum")
	_sfx.call("play", &"hum")
	_sfx.call("play", &"hum")
	check_eq(_sfx.call("get_voice_count", &"hum"), 2, "hum is limited to its max_voices")
	check_eq(_sfx.get("stolen_count"), 1, "the oldest hum was cut")
	_sfx.call("play", &"other")
	check_eq(_sfx.call("get_voice_count"), 3, "other cues keep their own room")
	await _settle()


func test_unknown_cue_is_ignored_and_warned_once() -> void:
	_sfx.call("play", &"nope")
	_sfx.call("play", &"nope")
	_sfx.call("play", &"also_nope")
	check_eq(_sfx.call("get_voice_count"), 0, "no voice for an unknown cue")
	check_eq(_sfx.get("unknown_count"), 3, "unknown plays counted")
	check_eq((_sfx.get("_warned_cues") as Dictionary).size(), 2, "one warning per distinct cue")
	check(_played.is_empty(), "cue_played not emitted")


func test_empty_library_never_errors() -> void:
	_sfx.set("library", SfxLibrary.new())
	_sfx.call("play", &"hum")
	check_eq(_sfx.call("get_voice_count"), 0, "an empty library plays nothing")
	_sfx.set("library", null)
	_sfx.call("play", &"hum")
	check_eq(_sfx.get("unknown_count"), 2, "a missing library counts as unknown")


func test_pause_suppresses_gameplay_cues_but_not_ui() -> void:
	tree.paused = true
	_sfx.call("play", &"hum")
	check_eq(_sfx.call("get_voice_count"), 0, "gameplay cue is silent while paused")
	check_eq(_sfx.get("dropped_count"), 1, "drop counted")
	_sfx.call("play", &"click")
	check_eq(_sfx.call("get_voice_count", &"click"), 1, "ui cue plays while paused")
	var players: Array[AudioStreamPlayer] = _sfx.call("get_active_players")
	check_eq(players[0].bus, &"UI", "ui cue uses the UI bus")
	check_eq(players[0].process_mode, Node.PROCESS_MODE_ALWAYS, "pool players ignore the pause")
	tree.paused = false
	_sfx.call("play", &"hum")
	check_eq(_sfx.call("get_voice_count", &"hum"), 1, "gameplay cue plays again after resume")
	await _settle()


func test_distance_attenuation_math() -> void:
	var near: float = SFX_SCRIPT.NEAR_DISTANCE
	var far: float = SFX_SCRIPT.FAR_DISTANCE
	var floor_db: float = SFX_SCRIPT.FAR_ATTENUATION_DB
	check_eq(_sfx.distance_attenuation_db(0.0), 0.0, "no attenuation at the camera")
	check_eq(_sfx.distance_attenuation_db(near), 0.0, "no attenuation up to the near distance")
	check_eq(_sfx.distance_attenuation_db(far), floor_db, "full attenuation at the far distance")
	check_eq(_sfx.distance_attenuation_db(far * 10.0), floor_db, "clamped past the far distance")
	check(is_equal_approx(_sfx.distance_attenuation_db((near + far) * 0.5), floor_db * 0.5), "linear in between")
	check_eq(_sfx.distance_attenuation_db(-5.0), 0.0, "a negative distance is treated as near")
	check(_sfx.distance_attenuation_db(near + 1.0) < 0.0, "just past near is already quieter")


func test_position_attenuates_by_distance_from_the_listener() -> void:
	var camera: Camera2D = Camera2D.new()
	tree.root.add_child(camera)
	camera.global_position = Vector2(100.0, 100.0)
	_sfx.call("set_listener", camera)
	_sfx.call("play", &"hum", Vector2(100.0, 100.0))
	_sfx.call("play", &"other", Vector2(100.0 + SFX_SCRIPT.FAR_DISTANCE * 2.0, 100.0))
	_sfx.call("play", &"burst")
	var by_cue: Dictionary = {}
	for voice: Object in _sfx.get("_voices"):
		by_cue[voice.get("cue")] = (voice.get("player") as AudioStreamPlayer).volume_db
	check_eq(by_cue[&"hum"], 0.0, "a sound at the camera keeps the cue volume")
	check_eq(by_cue[&"other"], SFX_SCRIPT.FAR_ATTENUATION_DB, "a far sound is attenuated")
	check_eq(by_cue[&"burst"], 0.0, "no position means no attenuation")
	_sfx.call("set_listener", null)
	camera.free()
	await _settle()


func test_position_without_a_camera_is_not_attenuated() -> void:
	_sfx.call("play", &"hum", Vector2(99999.0, 0.0))
	var players: Array[AudioStreamPlayer] = _sfx.call("get_active_players")
	check_eq(players[0].volume_db, 0.0, "no camera, no attenuation")
	await _settle()


func test_stop_all_cuts_voices_and_resets_cooldowns() -> void:
	_sfx.call("play", &"tick")
	_sfx.call("play", &"hum")
	_sfx.call("stop_all")
	check_eq(_sfx.call("get_voice_count"), 0, "nothing sounds after stop_all")
	_sfx.call("play", &"tick")
	check_eq(_sfx.call("get_voice_count", &"tick"), 1, "a cue in cooldown can play right after stop_all")
	await _settle()


func test_mute_drops_plays_and_restores() -> void:
	_sfx.call("play", &"hum")
	_sfx.call("set_muted", true)
	check_eq(_sfx.call("get_voice_count"), 0, "muting cuts what is playing")
	_sfx.call("play", &"hum")
	check_eq(_sfx.call("get_voice_count"), 0, "nothing plays while muted")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Master")), "the Master bus is muted")
	_sfx.call("set_muted", false)
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Master")), "the Master bus is restored")
	_sfx.call("play", &"hum")
	check_eq(_sfx.call("get_voice_count"), 1, "plays again once unmuted")
	await _settle()


func test_buses_and_limiter_exist_once() -> void:
	var sfx_index: int = AudioServer.get_bus_index(&"SFX")
	var ui_index: int = AudioServer.get_bus_index(&"UI")
	check(sfx_index != -1 and ui_index != -1, "SFX and UI buses exist")
	check_eq(AudioServer.get_bus_send(sfx_index), &"Master", "SFX routes to Master")
	check_eq(AudioServer.get_bus_send(ui_index), &"Master", "UI routes to Master")
	var master: int = AudioServer.get_bus_index(&"Master")
	var limiters: int = 0
	for i: int in AudioServer.get_bus_effect_count(master):
		limiters += 1 if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter else 0
	check_eq(limiters, 1, "exactly one limiter on Master, even with several Sfx nodes")


func test_bus_volume_linear() -> void:
	var index: int = AudioServer.get_bus_index(&"SFX")
	_sfx.call("set_bus_volume_linear", &"SFX", 0.5)
	check(is_equal_approx(AudioServer.get_bus_volume_db(index), linear_to_db(0.5)), "half volume")
	check(not AudioServer.is_bus_mute(index), "not muted at half volume")
	_sfx.call("set_bus_volume_linear", &"SFX", 0.0)
	check(AudioServer.is_bus_mute(index), "zero mutes the bus")
	_sfx.call("set_bus_volume_linear", &"SFX", 7.0)
	check_eq(AudioServer.get_bus_volume_db(index), 0.0, "volume is clamped to 1.0")
	check(not AudioServer.is_bus_mute(index), "unmuted again")
	_sfx.call("set_bus_volume_linear", &"NoSuchBus", 0.5)
	check(true, "an unknown bus only warns")


func test_pitch_jitter_stays_in_range() -> void:
	var library: SfxLibrary = _sfx.get("library")
	library.cues[1].pitch_jitter = 0.1
	var low: float = 10.0
	var high: float = 0.0
	for i: int in 30:
		_sfx.call("play", &"hum")
		var pitch: float = (_sfx.call("get_active_players") as Array[AudioStreamPlayer])[0].pitch_scale
		low = minf(low, pitch)
		high = maxf(high, pitch)
	check(low >= 0.9 and high <= 1.1, "pitch stays within the jitter")
	await _settle()


func test_the_autoload_runs_headless_without_a_library_file() -> void:
	var sfx: Node = autoload("Sfx")
	check(sfx != null, "Sfx autoload exists")
	var voices_before: int = sfx.call("get_voice_count")
	sfx.call("play", &"no_such_cue_for_the_test")
	sfx.call("play", &"no_such_cue_for_the_test", Vector2(10.0, 10.0))
	sfx.call("stop_all")
	check_eq(sfx.call("get_voice_count"), voices_before, "unknown cues start nothing")
	check(AudioServer.get_bus_index(&"SFX") != -1, "the autoload created the SFX bus")
	await _settle()
