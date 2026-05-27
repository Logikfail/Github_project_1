class_name SlotDef
extends Resource
## A named placement region inside a VillageSkeleton. Holds one module per village run.


# === Exports ===

## Identifier (for debug + per-village overrides). e.g. &"north_compound".
@export var slot_name: StringName = &""
## Top-left tile of the slot's bounding box, in skeleton tile space.
@export var origin_tile: Vector2i = Vector2i.ZERO
## Tile dimensions of the slot — modules with larger footprints are rejected.
@export var bounds: Vector2i = Vector2i(6, 6)
## Module categories that may be placed here. Empty array = any category accepted.
@export var allowed_categories: Array[StringName] = []
