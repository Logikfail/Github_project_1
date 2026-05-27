class_name Module
extends Resource
## Hand-crafted multi-tile composition placed into a VillageSkeleton slot.
## One module contributes exactly one house and zero or more obstacles.


# === Exports ===

## Display / debug name. e.g. "farmstead_pen", "market_stall_row".
@export var module_name: StringName = &""
## Category tag used by slot.allowed_categories. e.g. &"farmstead", &"market", &"religious".
@export var category: StringName = &"civic"
## Bounding tile size. Module footprint must fit inside the slot's bounds.
@export var footprint: Vector2i = Vector2i(4, 4)
## Tile offset (relative to slot origin) where this module's house spawns.
@export var house_offset: Vector2i = Vector2i.ZERO
## Tile offsets (relative to slot origin) where this module places obstacles.
@export var obstacle_offsets: Array[Vector2i] = []
## House type tag — drives wave size scaling and visuals.
@export var house_type: StringName = &"hovel"
## Villager archetype mix for this module's wave (overrides house_type signature lookup).
@export var villager_archetypes: Array[StringName] = []
## Which sides of the footprint have walkable openings (reserved for future
## rotation + connectivity validation). &"north" / &"east" / &"south" / &"west".
@export var open_edges: Array[StringName] = []
