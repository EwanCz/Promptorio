extends "res://tests/test_case.gd"


func test_machine_scene_nodes() -> void:
	var machine: Node = load("res://scenes/machines/machine.tscn").instantiate()
	check(machine is Machine, "root is a Machine")
	check(machine.get_node_or_null("Sprite2D") != null, "has Sprite2D")
	machine.free()
