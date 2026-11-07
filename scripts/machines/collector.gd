class_name Collector
extends Machine
## Accepts every item and sells it for money.

# shortcut: hardcoded prices, move to a Resource when items get more varied.
const PRICES: Dictionary = {"ore": 1, "ingot": 3, "part": 10}

var sold: int = 0
var earned: int = 0


func receive(item: String) -> bool:
	var price: int = int(PRICES.get(item, 1))
	GameState.add_money(price)
	sold += 1
	earned += price
	return true


func is_removable() -> bool:
	return false


func can_rotate() -> bool:
	return false


func get_action_text() -> String:
	return "Sold %d items, earned %d" % [sold, earned]
