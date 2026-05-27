class_name TechNode
extends Resource
## One node in the Tech Tree — either a Stat upgrade or a Discovery unlock.


# === Exports (design-time data) ===

## Which base tower branch this node belongs to.
@export var branch: StringName = &""
## "stat" or "discovery"
@export var node_type: StringName = &"stat"
## 0–5, left to right within the branch.
@export var position_in_branch: int = 0
@export var cost: int = 1

# Stat node: parallel arrays — one entry per choice.
@export var stat_options: Array[StringName] = []
@export var stat_amounts: Array[float] = []

# Discovery node: synthesis tower types the player can unlock.
@export var synthesis_options: Array[StringName] = []


# === Public Variables (runtime state — reset when branch is rebuilt) ===

var purchased: bool = false
var chosen_index: int = -1
