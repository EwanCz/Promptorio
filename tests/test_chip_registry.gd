extends "res://tests/test_case.gd"

var _registry: Node
var _ids: Array[int] = []


func before_each() -> void:
	_registry = autoload("ChipRegistry")
	_ids.clear()


func after_each() -> void:
	for id: int in _ids:
		_registry.remove(id)


func _add(chip_name: String, prompt: String = "p", desc: String = "") -> ChipRessource:
	var chip: ChipRessource = _registry.add(chip_name, prompt, desc)
	if chip != null:
		_ids.append(chip.id)
	return chip


func test_add_stores_fields_and_assigns_unique_ids() -> void:
	var first: ChipRessource = _add("reg_a", "prompt a", "desc a")
	var second: ChipRessource = _add("reg_b")
	check(first != null and second != null, "chips created")
	check_eq([first.name, first.prompt, first.description], ["reg_a", "prompt a", "desc a"], "fields stored")
	check_eq(second.description, "", "description defaults to empty")
	check(first.id != 0 and second.id != first.id, "ids are unique")
	check_eq(_registry.get_from_id(first.id), first, "lookup by id")
	check(_registry.get_all().has(second), "listed")


func test_add_refuses_duplicate_or_empty_name() -> void:
	_add("reg_dup")
	check(_add("reg_dup") == null, "duplicate name refused")
	check(_add("") == null, "empty name refused")


func test_remove() -> void:
	var chip: ChipRessource = _add("reg_rm")
	var id: int = chip.id
	check(_registry.remove(id), "removed")
	check(_registry.get_from_id(id) == null, "gone from registry")
	check(not _registry.remove(id), "second remove reports false")
	check(_add("reg_rm") != null, "name reusable after removal")
