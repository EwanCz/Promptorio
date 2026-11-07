class_name ChipRessource
extends Resource
## Pure data for one AI chip. No logic: ChipRegistry owns it, Machine runs it. Exported so ChipLibrary can save it as a .tres.

@export var id: int = 0
@export var name: String = ""
@export var description: String = ""
@export var prompt: String = ""
