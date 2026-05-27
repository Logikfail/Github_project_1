class_name VillageSkeleton
extends Resource
## Hand-authored template for one village — biome identity, slot layout, exits.
## Per-run, the generator fills each slot with a procedurally chosen Module.


# === Exports ===

## Biome / aesthetic theme. e.g. &"farmstead", &"market", &"monastery".
@export var biome: StringName = &"farmstead"
## Grid dimensions in tiles. Must be <= GameConfig.GRID_WIDTH / GRID_HEIGHT.
@export var grid_size: Vector2i = Vector2i(20, 20)
## Slot definitions — generator places one module per slot, in declaration order.
@export var slots: Array[SlotDef] = []
## Fixed exit tile positions. Authored, not random.
@export var exit_tiles: Array[Vector2i] = []
## Fraction of non-module, non-exit tiles that may receive a filler obstacle.
@export var filler_density: float = 0.10
