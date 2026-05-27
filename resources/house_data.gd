class_name HouseData
extends Resource
## Data for one house in a village — type, spawn position, wave composition.


# === Exports ===

## "hovel" | "chapel" | "garrison" | "apothecary" | "orphanage" | "almshouse" | "cemetery"
@export var house_type: StringName = &"hovel"
@export var spawn_tile: Vector2i = Vector2i.ZERO
## 0-indexed position within the village (used for wave size scaling).
@export var house_position: int = 0
## Total villager count for this house's wave.
@export var wave_size: int = 10
## Archetype StringName for each villager — WaveManager reads this array to spawn the wave.
@export var villager_archetypes: Array[StringName] = []
## Placeholder tileset identifier — maps to art asset during the visual pass.
@export var tileset_id: int = 0
