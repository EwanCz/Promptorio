extends Node
## Autoload. The memory of the Orchestrator: what it keeps between two decisions to get more precise over
## time (which chip suited which request, what a prompt change did, what the player asked for). Plain data
## in RAM, saved inside the save file (SaveGame "memory") and cleared with a new game (GameState.reset), so it
## belongs to the factory it manages. Chips have no memory of their own.
##
## Two stores:
## - notes: a few named texts it overwrites at will (remember / recall / forget), e.g. one lesson per topic;
## - journal: the latest events it logged, oldest dropped first (log_event / journal).
## Everything is bounded (MAX_* below), so a chatty model cannot grow a save without limit. Texts the LLM
## writes are cut to fit; the store never trusts what it is given.
## shortcut: no SQL. Godot has no built-in database and SQLite needs a native GDExtension per platform;
## a few KB of notes do not justify it. Keep the API below if a real database is wanted later.

const MAX_NOTES: int = 32
const MAX_JOURNAL: int = 50
const MAX_KEY_LENGTH: int = 40
const MAX_VALUE_LENGTH: int = 1000
const MAX_EVENT_LENGTH: int = 300

var _notes: Dictionary = {}
var _journal: Array[String] = []


## Stores or replaces a note. An empty text forgets it. The text is cut to MAX_VALUE_LENGTH. False (nothing
## stored) for an empty or too long key, or when a new note would pass MAX_NOTES.
func remember(key: String, value: String) -> bool:
	if not _valid_key(key):
		return false
	if value == "":
		return forget(key)
	if not _notes.has(key) and _notes.size() >= MAX_NOTES:
		return false
	_notes[key] = value.left(MAX_VALUE_LENGTH)
	return true


## The note, or `fallback` when there is none.
func recall(key: String, fallback: String = "") -> String:
	return str(_notes.get(key, fallback))


func has_note(key: String) -> bool:
	return _notes.has(key)


## True if the note existed.
func forget(key: String) -> bool:
	return _notes.erase(key)


## A copy of every note (key -> text).
func notes() -> Dictionary:
	return _notes.duplicate()


## Appends an event (cut to MAX_EVENT_LENGTH); the oldest ones fall off past MAX_JOURNAL. False for an empty text.
func log_event(text: String) -> bool:
	if text == "":
		return false
	_journal.append(text.left(MAX_EVENT_LENGTH))
	while _journal.size() > MAX_JOURNAL:
		_journal.pop_front()
	return true


## The latest `count` events, oldest first (all of them when count is not positive).
func journal(count: int = 0) -> Array[String]:
	var start: int = 0 if count <= 0 else maxi(_journal.size() - count, 0)
	var events: Array[String] = []
	events.assign(_journal.slice(start))
	return events


## What to hand the Orchestrator in its state: {"notes": {...}, "journal": [latest `journal_count` events]},
## leaving out what is empty (so an empty Dictionary when it remembers nothing).
func context(journal_count: int = 10) -> Dictionary:
	var result: Dictionary = {}
	if not _notes.is_empty():
		result["notes"] = notes()
	if not _journal.is_empty():
		result["journal"] = journal(journal_count)
	return result


func is_empty() -> bool:
	return _notes.is_empty() and _journal.is_empty()


## Forgets everything (a new game).
func clear() -> void:
	_notes.clear()
	_journal.clear()


## The whole memory as JSON-ready plain data, for the save file.
func snapshot() -> Dictionary:
	return {"notes": _notes.duplicate(), "journal": _journal.duplicate()}


## "" if the document is a memory snapshot within every limit, else a one-line reason. Nothing is touched.
## Both parts are optional.
static func validate(data: Variant) -> String:
	if typeof(data) != TYPE_DICTIONARY:
		return "The save has an invalid orchestrator memory."
	var notes_value: Variant = (data as Dictionary).get("notes", {})
	var journal_value: Variant = (data as Dictionary).get("journal", [])
	if typeof(notes_value) != TYPE_DICTIONARY or (notes_value as Dictionary).size() > MAX_NOTES:
		return "The save has an invalid list of orchestrator notes."
	for key: Variant in notes_value:
		if typeof(key) != TYPE_STRING or not _valid_key(key):
			return "The save has an orchestrator note with an invalid name."
		if typeof(notes_value[key]) != TYPE_STRING or str(notes_value[key]).length() > MAX_VALUE_LENGTH:
			return "The save has an invalid orchestrator note."
	if typeof(journal_value) != TYPE_ARRAY or (journal_value as Array).size() > MAX_JOURNAL:
		return "The save has an invalid orchestrator journal."
	for event: Variant in journal_value:
		if typeof(event) != TYPE_STRING or str(event).length() > MAX_EVENT_LENGTH:
			return "The save has an invalid orchestrator journal."
	return ""


## Replaces the whole memory with a snapshot. Returns "" on success, else why it was refused (the memory is
## then left as it was). An empty document is a valid, empty memory.
func restore(data: Variant) -> String:
	var error: String = validate(data)
	if error != "":
		return error
	clear()
	_notes = ((data as Dictionary).get("notes", {}) as Dictionary).duplicate()
	_journal.assign((data as Dictionary).get("journal", []))
	return ""


static func _valid_key(key: String) -> bool:
	return key.strip_edges() != "" and key.length() <= MAX_KEY_LENGTH
