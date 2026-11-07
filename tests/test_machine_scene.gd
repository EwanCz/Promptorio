extends "res://tests/test_case.gd"


func test_machine_scene_has_chip() -> void:
	var machine: Node = load("res://scenes/machines/machine.tscn").instantiate()
	check(machine is Machine, "root is a Machine")
	check(machine.get_node_or_null("ChipComponent") is ChipComponent, "has ChipComponent")
	check(machine.get_node_or_null("Sprite2D") != null, "has Sprite2D")
	machine.free()
