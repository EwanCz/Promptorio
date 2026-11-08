class_name ChipRessource
extends Resource
## Pure data for one AI chip. No logic: ChipRegistry owns it, Machine runs it. Exported so ChipLibrary can save it as a .tres.

@export var id: int = 0
@export var name: String = ""
@export var description: String = ""
@export var prompt: String = ""
## 0 for a player-authored chip. Otherwise the machine_id of the Orchestrator that generated it with
## create_chip: only that Orchestrator may later revise it (ChipRegistry.revise()), same convention as
## ChipComponent.assigned_by. A player save through ChipPage always resets this to 0 (ChipRegistry.update()):
## editing a generated chip claims it, so an Orchestrator never overwrites a player's edit afterwards.
@export var created_by: int = 0
