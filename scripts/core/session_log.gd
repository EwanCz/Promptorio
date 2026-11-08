class_name SessionLog
extends Node
## Writes every machine log line (EventBus.chip_log_added) to a timestamped text file for debugging:
## `time | #id type | message`, flushed per line so a crash keeps what happened. Only the machine's log
## message is written, and any configured API key is masked.

const DIR: String = "user://logs"

var path: String = ""

var _file: FileAccess = null


## Opens a new `session_<date>_<time>.log` in `dir` (created if missing). False, with a warning, if it cannot.
func start(dir: String = DIR) -> bool:
	var made: Error = DirAccess.make_dir_recursive_absolute(dir)
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var target: String = "%s/session_%s.log" % [dir, stamp]
	_file = FileAccess.open(target, FileAccess.WRITE) if made == OK else null
	if _file == null:
		push_warning("Session log disabled: cannot write to %s" % dir)
		return false
	path = target
	if not EventBus.chip_log_added.is_connected(_on_log):
		EventBus.chip_log_added.connect(_on_log)
	return true


func _exit_tree() -> void:
	if EventBus.chip_log_added.is_connected(_on_log):
		EventBus.chip_log_added.disconnect(_on_log)
	_file = null


func _on_log(machine: Node, message: String) -> void:
	if _file == null:
		return
	var who: String = "?"
	if machine is Machine:
		who = "#%d %s" % [machine.machine_id, machine.machine_type]
	_file.store_line("%s | %s | %s" % [Time.get_datetime_string_from_system(), who, _clean(message)])
	_file.flush()


## One line, configured keys masked.
func _clean(message: String) -> String:
	for provider: String in Settings.MODELS:
		var key: String = Settings.get_api_key(provider)
		if key != "":
			message = message.replace(key, "[redacted]")
	return message.replace("\r", " ").replace("\n", " ")
