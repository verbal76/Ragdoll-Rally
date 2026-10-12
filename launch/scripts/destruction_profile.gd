extends Resource
## Designer-editable destruction settings for one building / material. Assign an instance to a shell with
## `shell.set_meta("profile", res)` (or save as .tres); anything not assigned falls back to Destruction.PROFILES[material].
## Use with:  const DestructionProfile := preload("res://scripts/destruction_profile.gd")

@export var strength: float = 1.0           ## multiplier on the shell's toughness (impact speed it resists)
@export_range(0.2, 1.5) var cell_tough: float = 0.62      ## a cell's toughness as a fraction of the shell's
@export var chunk_mass: float = 1.0         ## cell mass multiplier
@export var impulse: float = 1.0            ## debris launch strength multiplier
@export var explosive: float = 1.0          ## how readily blasts break it (blast radius multiplier for release)
@export var collapse: bool = true           ## unsupported storeys / cells fall
@export var debris_life: float = 12.0       ## seconds a settled chunk stays simulated before it freezes into the aftermath
@export var crater_resist: float = 1.0      ## larger = smaller craters / cavities from the same blast
@export var max_active: int = 56            ## most rigid bodies one impact may free from this building (rest dissolve to debris)

func to_dict() -> Dictionary:
	return {"cell_tough": cell_tough, "chunk_mass": chunk_mass, "impulse": impulse, "explosive": explosive, "collapse": collapse,
		"debris_life": debris_life, "crater_resist": crater_resist, "strength": strength, "max_active": max_active}
