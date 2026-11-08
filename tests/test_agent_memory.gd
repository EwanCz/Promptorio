extends "res://tests/test_case.gd"
## Orchestrator memory: notes and journal, the limits, snapshot/restore, and how it follows the game
## (new game, save file).

const TEST_DIR: String = "user://test_saves_memory"

var _memory: Node
var _game: Node
var _main: Node
var _placement: Placement
var _saved_dir: String = ""
var _saved_money: int = 0
var _saved_ticks: int = 0


func before_each() -> void:
	_memory = autoload("AgentMemory")
	_game = autoload("GameState")
	_memory.clear()
	_saved_dir = SaveGame.save_dir
	_saved_money = _game.money
	_saved_ticks = _game.tick_count
	SaveGame.save_dir = TEST_DIR


func after_each() -> void:
	if _main != null:
		_main.free()
		_main = null
	_memory.clear()
	SaveGame.save_dir = _saved_dir
	_game.money = _saved_money
	_game.tick_count = _saved_ticks


func _start_game() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	tree.root.add_child(_main)
	_placement = _main.get_node("Game/FactoryView/SubViewport/World/Placement")


func test_notes_are_kept_replaced_and_forgotten() -> void:
	check(_memory.is_empty(), "starts empty")
	check(_memory.remember("smelter_prompt", "mention cooling first"), "a note is stored")
	check_eq(_memory.recall("smelter_prompt"), "mention cooling first", "recalled")
	check(_memory.has_note("smelter_prompt"), "has_note")
	_memory.remember("smelter_prompt", "mention cooling and stock")
	check_eq(_memory.recall("smelter_prompt"), "mention cooling and stock", "a note is replaced")
	check_eq(_memory.recall("other", "none"), "none", "the fallback comes back for an unknown note")
	check(not _memory.forget("other"), "forgetting an unknown note says so")
	check(not _memory.is_empty(), "not empty")
	check(_memory.forget("smelter_prompt"), "a note is forgotten")
	check(_memory.is_empty(), "empty again")


func test_an_empty_text_forgets_the_note() -> void:
	_memory.remember("k", "v")
	check(_memory.remember("k", ""), "an empty text is accepted")
	check(not _memory.has_note("k"), "and forgets the note")


func test_notes_returns_a_copy() -> void:
	_memory.remember("mode", "cool")
	var copy: Dictionary = _memory.notes()
	copy["mode"] = "changed"
	check_eq(_memory.recall("mode"), "cool", "changing the copy changes nothing")


func test_the_journal_keeps_the_latest_events() -> void:
	for index: int in range(AgentMemory.MAX_JOURNAL + 5):
		_memory.log_event("event %d" % index)
	var all: Array[String] = _memory.journal()
	check_eq(all.size(), AgentMemory.MAX_JOURNAL, "the journal is capped")
	check_eq(all[0], "event 5", "the oldest events fell off")
	check_eq(all[all.size() - 1], "event %d" % (AgentMemory.MAX_JOURNAL + 4), "the newest is last")
	check_eq(_memory.journal(2), ["event %d" % (AgentMemory.MAX_JOURNAL + 3), "event %d" % (AgentMemory.MAX_JOURNAL + 4)], "the latest two, oldest first")
	check(not _memory.log_event(""), "an empty event is refused")


func test_limits() -> void:
	check(not _memory.remember("", "v"), "empty key refused")
	check(not _memory.remember("   ", "v"), "blank key refused")
	check(not _memory.remember("k".repeat(AgentMemory.MAX_KEY_LENGTH + 1), "v"), "too long key refused")
	_memory.remember("long", "x".repeat(AgentMemory.MAX_VALUE_LENGTH + 50))
	check_eq(_memory.recall("long").length(), AgentMemory.MAX_VALUE_LENGTH, "a long note is cut, not refused")
	_memory.log_event("y".repeat(AgentMemory.MAX_EVENT_LENGTH + 50))
	check_eq(_memory.journal()[0].length(), AgentMemory.MAX_EVENT_LENGTH, "a long event is cut")
	for index: int in range(AgentMemory.MAX_NOTES - 1):
		_memory.remember("note %d" % index, "v")
	check_eq(_memory.notes().size(), AgentMemory.MAX_NOTES, "the notes are at their limit")
	check(not _memory.remember("one too many", "v"), "a new note past the limit is refused")
	check(_memory.remember("long", "still fine"), "but an existing note can be replaced")


func test_context_is_compact() -> void:
	check_eq(_memory.context(), {}, "nothing to say when it remembers nothing")
	_memory.remember("mode", "cool")
	check_eq(_memory.context(), {"notes": {"mode": "cool"}}, "notes only")
	for index: int in range(8):
		_memory.log_event("e%d" % index)
	var context: Dictionary = _memory.context(3)
	check_eq(context["journal"], ["e5", "e6", "e7"], "the latest events")
	check_eq(context["notes"], {"mode": "cool"}, "with the notes")


func test_snapshot_and_restore_round_trip_through_json() -> void:
	_memory.remember("goal", "make circuits")
	_memory.log_event("assigned chip 2 to smelter 4")
	var text: String = JSON.stringify(_memory.snapshot())
	_memory.clear()
	check_eq(_memory.restore(JSON.parse_string(text)), "", "a snapshot that went through JSON is accepted")
	check_eq(_memory.recall("goal"), "make circuits", "notes restored")
	check_eq(_memory.journal(), ["assigned chip 2 to smelter 4"], "journal restored")
	check_eq(JSON.stringify(_memory.snapshot()), text, "identical afterwards")
	var snapshot: Dictionary = _memory.snapshot()
	snapshot["notes"]["goal"] = "changed"
	check_eq(_memory.recall("goal"), "make circuits", "a snapshot is a copy")


func test_bad_memory_is_refused_and_changes_nothing() -> void:
	_memory.remember("k", "v")
	var cases: Dictionary = {
		"not a dictionary": [],
		"notes not a dictionary": {"notes": []},
		"note not text": {"notes": {"k": 5}},
		"note too long": {"notes": {"k": "x".repeat(AgentMemory.MAX_VALUE_LENGTH + 1)}},
		"empty note name": {"notes": {"": "v"}},
		"note name not text": {"notes": {1: "v"}},
		"too many notes": {"notes": range(AgentMemory.MAX_NOTES + 1).reduce(func(acc: Dictionary, i: int) -> Dictionary: acc["k%d" % i] = "v"; return acc, {})},
		"journal not a list": {"journal": {}},
		"event not text": {"journal": [1]},
		"event too long": {"journal": ["x".repeat(AgentMemory.MAX_EVENT_LENGTH + 1)]},
		"journal too long": {"journal": range(AgentMemory.MAX_JOURNAL + 1).map(func(i: int) -> String: return "e")},
	}
	for label: String in cases:
		check(_memory.restore(cases[label]) != "", "refused: " + label)
		check_eq(_memory.recall("k"), "v", "memory untouched after: " + label)
	check_eq(_memory.restore({}), "", "an empty memory is valid")
	check(_memory.is_empty(), "and replaces the old one")


func test_a_new_game_wipes_the_memory() -> void:
	_memory.remember("goal", "make circuits")
	_memory.log_event("started")
	_game.reset()
	check(_memory.is_empty(), "GameState.reset clears the Orchestrator memory")
	_game.money = _saved_money


func test_the_memory_is_part_of_the_save() -> void:
	_start_game()
	_memory.remember("goal", "make circuits")
	_memory.log_event("planned a line")
	var save: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.snapshot(_placement)))
	check(save.has("memory"), "the save holds the memory")
	_memory.clear()
	_memory.remember("stale", "from another game")
	check_eq(SaveGame.restore(_placement, save), "", "the save is restored")
	check_eq(_memory.recall("goal"), "make circuits", "the notes come back")
	check_eq(_memory.journal(), ["planned a line"], "so does the journal")
	check(not _memory.has_note("stale"), "the memory of the other game is replaced")


func test_a_save_without_memory_leaves_a_blank_memory() -> void:
	_start_game()
	var save: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.snapshot(_placement)))
	save.erase("memory")
	_memory.remember("goal", "make circuits")
	check_eq(SaveGame.restore(_placement, save), "", "an older save is accepted")
	check(_memory.is_empty(), "with a blank memory")


func test_a_save_with_a_bad_memory_is_refused() -> void:
	_start_game()
	var save: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.snapshot(_placement)))
	save["memory"] = {"notes": {"k": 5}}
	_memory.remember("goal", "make circuits")
	check(SaveGame.restore(_placement, save) != "", "refused")
	check(SaveGame.validate(null, save) != "", "refused from the main menu too")
	check_eq(_memory.recall("goal"), "make circuits", "the memory is untouched")
