extends "res://tests/test_case.gd"
## Audio engine (Sfx autoload): cooldown, voice caps, unknown cue, pause rule, distance attenuation, buses.
## Runs on the Dummy audio driver; what was requested is read from `Sfx.played` and `Sfx.stats`.

const SFX_SCRIPT: String = "res://scripts/core/sfx.gd"

var _sfx: Node
var _saved_library: SfxLibrary
var _nodes: Array[Node] = []
var _played: Array[Dictionary] = []


func before_each() -> void:
	_sfx = autoload("Sfx")
	_saved_library = _sfx.library
	_sfx.library = SfxLibrary.new()
	_sfx.stop_all()
	_sfx.reset_stats()
	_sfx.set_listener(null)
	_played.clear()
	_sfx.played.connect(_on_played)


func after_each() -> void:
	_sfx.played.disconnect(_on_played)
	_sfx.stop_all()
	_sfx.set_listener(null)
	_sfx.library = _saved_library
	_sfx.reset_stats()
	tree.paused = false
	for node: Node in _nodes:
		node.free()
	_nodes.clear()


func _on_played(cue: StringName, position: Vector2, volume_db: float, pitch_scale: float) -> void:
	_played.append({"cue": cue, "position": position, "volume_db": volume_db, "pitch": pitch_scale})


## The cooldown reads the real clock (Time.get_ticks_msec), and the engine timer can fire early in a headless run.
func _wait_msec(msec: int) -> void:
	var until: int = Time.get_ticks_msec() + msec
	await wait_until(func() -> bool: return Time.get_ticks_msec() >= until, float(msec) / 1000.0 + 1.0)


## A silent stream long enough to still be playing when a test looks.
func _stream() -> AudioStreamWAV:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 8000
	var data: PackedByteArray = PackedByteArray()
	data.resize(8000 * 5)
	data.fill(0)
	wav.data = data
	return wav


func _add_cue(id: StringName, cooldown: float = 0.0, max_voices: int = 16, ui: bool = false, volume_db: float = 0.0) -> SfxCue:
	var cue: SfxCue = SfxCue.new()
	cue.id = id
	cue.stream = _stream()
	cue.cooldown = cooldown
	cue.max_voices = max_voices
	cue.ui = ui
	cue.volume_db = volume_db
	_sfx.library.cues.append(cue)
	return cue


func test_play_known_cue_plays_once() -> void:
	_add_cue(&"beep")
	check(_sfx.play(&"beep"), "play returns true")
	check_eq(_played.size(), 1, "played emitted once")
	check_eq(_played[0]["cue"], &"beep", "played carries the cue")
	check_eq(_sfx.active_voices(&"beep"), 1, "one voice is playing")
	check_eq(_sfx.stats["played"], 1, "played counter")


func test_unknown_cue_is_ignored() -> void:
	check(not _sfx.play(&"nope"), "unknown cue returns false")
	check(not _sfx.play(&"nope"), "asked again, still ignored")
	check_eq(_sfx.stats["unknown"], 2, "both requests counted as unknown")
	check_eq(_sfx.active_voices(), 0, "nothing plays")
	check_eq(_played.size(), 0, "no played signal")


func test_cue_without_stream_is_ignored() -> void:
	var cue: SfxCue = _add_cue(&"empty")
	cue.stream = null
	check(not _sfx.play(&"empty"), "a cue with no stream is ignored")
	check_eq(_sfx.stats["unknown"], 1, "counted as unknown")


func test_cooldown_drops_fast_repeats() -> void:
	_add_cue(&"tick", 0.2)
	check(_sfx.play(&"tick"), "first request plays")
	check(not _sfx.play(&"tick"), "second request inside the cooldown is dropped")
	check(not _sfx.play(&"tick"), "third too")
	check_eq(_played.size(), 1, "played once")
	check_eq(_sfx.stats["cooldown"], 2, "two requests counted as cooldown")
	await _wait_msec(250)
	check(_sfx.play(&"tick"), "plays again once the cooldown has passed")
	check_eq(_played.size(), 2, "played twice in total")


func test_cooldown_is_per_cue() -> void:
	_add_cue(&"a", 0.5)
	_add_cue(&"b", 0.5)
	check(_sfx.play(&"a"), "a plays")
	check(_sfx.play(&"b"), "b is not blocked by a's cooldown")


func test_cue_voice_cap_replaces_its_oldest() -> void:
	_add_cue(&"hum", 0.0, 2)
	for i: int in 5:
		_sfx.play(&"hum")
		await _wait_msec(3)
	check_eq(_sfx.active_voices(&"hum"), 2, "never more than max_voices of the cue")
	check_eq(_played.size(), 5, "every request still started a sound")


func test_global_voice_cap_never_grows() -> void:
	var total: int = _sfx.POOL_SIZE + 10
	for i: int in total:
		_add_cue(StringName("c%d" % i))
	for i: int in total:
		_sfx.play(StringName("c%d" % i))
	check_eq(_sfx.active_voices(), _sfx.POOL_SIZE, "voices stay at the pool size")
	check_eq(_sfx.stats["stolen"], 10, "each extra sound stole a voice")


func test_full_pool_steals_the_quietest_and_drops_a_quieter_sound() -> void:
	for i: int in _sfx.POOL_SIZE:
		_add_cue(StringName("v%d" % i), 0.0, 16, false, -10.0 - float(i))
	for i: int in _sfx.POOL_SIZE:
		_sfx.play(StringName("v%d" % i))
	_add_cue(&"loud", 0.0, 16, false, 0.0)
	_add_cue(&"faint", 0.0, 16, false, -40.0)
	check(_sfx.play(&"loud"), "a louder sound gets a voice")
	check_eq(_sfx.active_voices(&"v%d" % (_sfx.POOL_SIZE - 1)), 0, "it took the quietest voice")
	check_eq(_sfx.active_voices(&"v0"), 1, "the loudest voice survived")
	check(not _sfx.play(&"faint"), "a sound quieter than every voice is dropped")
	check_eq(_sfx.stats["dropped"], 1, "counted as dropped")
	check_eq(_sfx.active_voices(), _sfx.POOL_SIZE, "still capped")


func test_pause_blocks_gameplay_cues_but_not_ui() -> void:
	_add_cue(&"clack")
	_add_cue(&"click", 0.0, 2, true)
	tree.paused = true
	check(not _sfx.play(&"clack"), "a gameplay cue does not play while paused")
	check_eq(_sfx.stats["paused"], 1, "counted as paused")
	check(_sfx.play(&"click"), "a UI cue plays while paused")
	check_eq(_sfx.active_voices(&"click"), 1, "the UI voice is playing")
	tree.paused = false
	check(_sfx.play(&"clack"), "the gameplay cue plays again once resumed")


func test_stop_all_can_spare_ui_voices() -> void:
	_add_cue(&"clack")
	_add_cue(&"click", 0.0, 2, true)
	_sfx.play(&"clack")
	_sfx.play(&"click")
	_sfx.stop_all(false)
	check_eq(_sfx.active_voices(&"clack"), 0, "the gameplay voice stopped")
	check_eq(_sfx.active_voices(&"click"), 1, "the UI voice finishes")
	_sfx.stop_all()
	check_eq(_sfx.active_voices(), 0, "stop_all() stops everything")
	check(_sfx.play(&"clack"), "a stopped cue can play right away")


func test_attenuation_math() -> void:
	var script: GDScript = load(SFX_SCRIPT)
	var full: float = script.get("FULL_VOLUME_RADIUS")
	var silent: float = script.get("SILENT_RADIUS")
	check_eq(script.call("distance_attenuation_db", 0.0), 0.0, "no attenuation at the camera")
	check_eq(script.call("distance_attenuation_db", full), 0.0, "none up to the full radius")
	check_eq(script.call("distance_attenuation_db", silent), script.get("SILENT_DB"), "silent at the far radius")
	check_eq(script.call("distance_attenuation_db", silent * 3.0), script.get("SILENT_DB"), "and beyond")
	var halfway: float = script.call("distance_attenuation_db", (full + silent) * 0.5)
	check(absf(halfway - linear_to_db(0.5)) < 0.001, "halfway through the fade the amplitude is one half")
	check(script.call("distance_attenuation_db", full + 100.0) > halfway, "closer is louder")


func test_position_attenuates_by_distance_from_the_camera() -> void:
	_add_cue(&"far", 0.0)
	var camera: Camera2D = Camera2D.new()
	tree.root.add_child(camera)
	_nodes.append(camera)
	camera.global_position = Vector2(100.0, 100.0)
	_sfx.set_listener(camera)
	_sfx.play(&"far", Vector2(100.0, 100.0))
	check_eq(_played[0]["volume_db"], 0.0, "a sound at the camera is at full volume")
	var script: GDScript = load(SFX_SCRIPT)
	var distance: float = (script.get("FULL_VOLUME_RADIUS") as float) + 300.0
	_sfx.play(&"far", Vector2(100.0 + distance, 100.0))
	check_eq(_played[1]["volume_db"], script.call("distance_attenuation_db", distance), "volume follows the distance")
	camera.zoom = Vector2(0.5, 0.5)
	_sfx.play(&"far", Vector2(100.0 + distance, 100.0))
	check_eq(_played[2]["volume_db"], 0.0, "zoomed out, the same world distance is closer on screen")
	check(not _sfx.play(&"far", Vector2(100.0 + 100000.0, 100.0)), "a sound far off screen is not played")
	check_eq(_sfx.stats["too_far"], 1, "counted as too far")
	_sfx.play(&"far")
	check_eq(_played[3]["volume_db"], 0.0, "a sound without a position is never attenuated")
	check(not (_played[3]["position"] as Vector2).is_finite(), "and reports no position")


func test_position_without_a_camera_plays_at_full_volume() -> void:
	_add_cue(&"far")
	_sfx.play(&"far", Vector2(99999.0, 99999.0))
	check_eq(_played[0]["volume_db"], 0.0, "no listener, no attenuation")


func test_pitch_jitter_stays_in_range() -> void:
	var cue: SfxCue = _add_cue(&"jit")
	cue.pitch_jitter = 0.1
	for i: int in 20:
		_sfx.play(&"jit")
		_sfx.stop_all()
	var in_range: bool = true
	var varied: bool = false
	for entry: Dictionary in _played:
		var pitch: float = entry["pitch"]
		in_range = in_range and pitch >= 0.9 and pitch <= 1.1
		varied = varied or not is_equal_approx(pitch, 1.0)
	check_eq(_played.size(), 20, "all plays happened")
	check(in_range, "pitch stays within 1 +/- jitter")
	check(varied, "pitch varies")


func test_pitch_scale_multiplies_the_pitch() -> void:
	_add_cue(&"plain")
	var jittery: SfxCue = _add_cue(&"wobble")
	jittery.pitch_jitter = 0.1
	_sfx.play(&"plain", Vector2.INF, 1.5)
	check_eq(_played[0]["pitch"], 1.5, "a cue without jitter plays at the requested scale")
	_sfx.play(&"plain")
	check_eq(_played[1]["pitch"], 1.0, "the scale defaults to 1")
	var in_range: bool = true
	for i: int in 20:
		_sfx.play(&"wobble", Vector2.INF, 2.0)
		var pitch: float = _played[_played.size() - 1]["pitch"]
		in_range = in_range and pitch >= 2.0 * 0.9 and pitch <= 2.0 * 1.1
		_sfx.stop_all()
	check(in_range, "with jitter the scale multiplies the jittered pitch")
	_sfx.play(&"plain", Vector2.INF, 0.0)
	check(float(_played[_played.size() - 1]["pitch"]) > 0.0, "a zero scale is kept playable")


func test_buses_and_limiter() -> void:
	var master: int = AudioServer.get_bus_index(&"Master")
	for bus_name: StringName in [&"SFX", &"UI"]:
		var index: int = AudioServer.get_bus_index(bus_name)
		check(index != -1, "bus %s exists" % bus_name)
		check_eq(AudioServer.get_bus_send(index), &"Master", "bus %s sends to Master" % bus_name)
	var count_before: int = AudioServer.bus_count
	var limiters: int = 0
	var effects_before: int = AudioServer.get_bus_effect_count(master)
	_sfx.setup_buses()
	check_eq(AudioServer.bus_count, count_before, "setting up again adds no bus")
	check_eq(AudioServer.get_bus_effect_count(master), effects_before, "nor a second limiter")
	for i: int in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter:
			limiters += 1
	check_eq(limiters, 1, "Master has one limiter")


func test_cue_goes_to_its_bus() -> void:
	_add_cue(&"clack")
	_add_cue(&"click", 0.0, 2, true)
	_sfx.play(&"clack")
	_sfx.play(&"click")
	var buses: Dictionary = {}
	for child: Node in _sfx.get_children():
		var player: AudioStreamPlayer = child as AudioStreamPlayer
		if player != null and player.playing:
			buses[player.bus] = int(buses.get(player.bus, 0)) + 1
	check_eq(buses.get(&"SFX", 0), 1, "gameplay cue on the SFX bus")
	check_eq(buses.get(&"UI", 0), 1, "UI cue on the UI bus")


func test_shipped_library_loads() -> void:
	var library: SfxLibrary = load(SfxLibrary.PATH) as SfxLibrary
	check(library != null, "data/sfx.tres is an SfxLibrary")
	check(library.get_cue(&"missing") == null, "get_cue of an unknown id is null")


## Last on purpose: stopped playbacks are only released on the audio thread's next mix, so give it time to
## drop the test streams before the process exits (otherwise "ObjectDB instances were leaked" is printed).
func test_zz_stopped_voices_release_their_streams() -> void:
	_add_cue(&"rel")
	_sfx.play(&"rel")
	_sfx.stop_all()
	_sfx.library = SfxLibrary.new()
	await _wait_msec(300)
	check_eq(_sfx.active_voices(), 0, "no voice is left playing")
