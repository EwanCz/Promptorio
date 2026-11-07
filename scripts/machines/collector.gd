class_name Collector
extends Machine
## Accepts every item and sells it for money.

# shortcut: hardcoded prices, move to a Resource when items get more varied.
const PRICES: Dictionary = {"ore": 1, "ingot": 3, "part": 10}

var sold: int = 0


func receive(item: String) -> bool:
	GameState.add_money(int(PRICES.get(item, 1)))
	sold += 1
	return true
