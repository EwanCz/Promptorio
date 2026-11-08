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
## 0 (the default): a newly attached component starts at ChipComponent.DEFAULT_TIMEOUT. Above 0: the
## ticks it starts with instead, for a shipped chip whose prompt needs a tighter poll than that default to
## stay safe (e.g. the Smelter Cooler) — see Machine.attach_chip(). Never affects a component already
## attached: that keeps whatever timeout it was given (saved, or set by hand in the tooltip).
@export var default_timeout: int = 0


## This chip's own default_timeout if set, else ChipComponent.DEFAULT_TIMEOUT.
func effective_default_timeout() -> int:
	return default_timeout if default_timeout > 0 else ChipComponent.DEFAULT_TIMEOUT
