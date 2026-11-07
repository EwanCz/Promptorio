extends "res://tests/test_case.gd"

const DIR: String = "user://test_logs"
const BLOCKER: String = "user://test_logs_blocker"

var _log: SessionLog
var _nodes: Array[Node] = []
var _saved_key: String = ""


func before_each() -> void:
	_saved_key = autoload("Settings").api_key
	_log = SessionLog.new()
	tree.root.add_child(_log)


func after_each() -> void:
	autoload("Settings").api_key = _saved_key
	_log.free()
	for node: Node in _nodes:
		node.free()
	_nodes.clear()
	for file: String in DirAccess.get_files_at(DIR) if DirAccess.dir_exists_absolute(DIR) else PackedStringArray():
		DirAccess.remove_absolute("%s/%s" % [DIR, file])
	DirAccess.remove_absolute(DIR)
	DirAccess.remove_absolute(BLOCKER)


func _machine(type: String, id: int) -> Machine:
	var machine: Machine = (load("res://scenes/machines/%s.tscn" % type) as PackedScene).instantiate() as Machine
	machine.machine_id = id
	tree.root.add_child(machine)
	_nodes.append(machine)
	return machine


func _lines() -> PackedStringArray:
	return FileAccess.get_file_as_string(_log.path).strip_edges().split("\n")


func test_entries_from_several_machines_are_written_with_their_identity() -> void:
	check(_log.start(DIR), "starts and creates the directory")
	check(_log.path.begins_with(DIR + "/session_") and _log.path.ends_with(".log"), "timestamped file name")
	_machine("miner", 3).log_chip("set_mine_ticks({\"ticks\":10})")
	_machine("smelter", 7).log_chip("set_cooling({\"on\":true})")
	var lines: PackedStringArray = _lines()
	check_eq(lines.size(), 2, "one line per entry, readable back")
	check(lines[0].contains(" | #3 miner | set_mine_ticks("), "first: machine id, type, message")
	check(lines[1].contains(" | #7 smelter | set_cooling("), "second: another machine")
	check(lines[0].split(" | ")[0].contains(Time.get_date_string_from_system()), "each line starts with the time")


func test_entries_are_flushed_while_the_file_is_still_open() -> void:
	_log.start(DIR)
	_machine("miner", 1).log_chip("before a crash")
	check(FileAccess.get_file_as_string(_log.path).contains("before a crash"), "readable without closing the log")


func test_multi_line_messages_stay_on_one_line() -> void:
	_log.start(DIR)
	_machine("miner", 1).log_chip("a\nb")
	check_eq(_lines().size(), 1, "one line")


func test_api_keys_are_masked_and_the_chip_log_limit_is_unchanged() -> void:
	var secret: String = "sk-test-0123456789-abcdefghij"
	autoload("Settings").api_key = secret
	_log.start(DIR)
	var chip_log: ChipLog = (load("res://scenes/ui/popups/chip_log.tscn") as PackedScene).instantiate() as ChipLog
	tree.root.add_child(chip_log)
	_nodes.append(chip_log)
	var machine: Machine = _machine("miner", 2)
	machine.log_chip("decision failed: bad key %s" % secret)
	for i: int in ChipLog.MAX_LINES + 5:
		machine.log_chip("line %d" % i)
	var text: String = FileAccess.get_file_as_string(_log.path)
	check(not text.contains(secret), "the key never reaches the file")
	check(text.contains("bad key [redacted]"), "it is masked instead")
	check_eq(_lines().size(), ChipLog.MAX_LINES + 6, "the file keeps every line")
	check_eq(chip_log.get_lines(machine).size(), ChipLog.MAX_LINES, "the per-machine log is still capped")


func test_nothing_is_written_after_the_log_leaves_the_tree() -> void:
	_log.start(DIR)
	var path: String = _log.path
	tree.root.remove_child(_log)
	_machine("miner", 1).log_chip("after")
	check(not FileAccess.get_file_as_string(path).contains("after"), "disconnected on exit")
	tree.root.add_child(_log)


func test_unwritable_directory_is_reported_not_fatal() -> void:
	FileAccess.open(BLOCKER, FileAccess.WRITE).close()
	check(not _log.start(BLOCKER + "/logs"), "a directory under a plain file cannot be created")
	_machine("miner", 1).log_chip("ignored")
	check_eq(_log.path, "", "no file")
