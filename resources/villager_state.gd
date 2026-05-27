class_name VillagerState
extends Resource
## Per-villager runtime state. Owned and mutated by VillagerManager only.


# === Public Variables ===

var archetype: StringName = &""
var move_state: int = 0    # VillagerManager.MoveState enum value
var path: PackedVector2Array = []
var path_index: int = 0
var desperate_target: Node = null

# Guard-specific
var shield_hp: float = 0.0
var shield_active: bool = false
