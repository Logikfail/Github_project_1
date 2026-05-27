class_name InfectionState
extends Resource
## Per-villager runtime infection state. Owned and mutated by InfectionManager only.


# === Inner Classes ===

class ActiveDot:
	## A running instance of one applied InfectionEffect.
	var effect_type: StringName = &""
	var base_damage: float = 0.0
	var escalation_rate: float = 0.0
	var stack_count: int = 1        # Plague increments this per re-application
	var ticks_elapsed: int = 0
	var ticks_remaining: int = -1   # -1 = persistent (caller-managed expiry, e.g. Miasma AOE)
	var spread_chance: float = 0.0
	var spread_range: float = 0.0
	var slow_amount: float = 0.0
	var resistance_mod: float = 0.0  # Miasma: resistance reduction applied to other types


# === Public Variables ===

var active_dots: Array = []                      # Array of ActiveDot (untyped — inner class)
var rot_stacks: int = 0
var is_rot_carrier: bool = false

var base_resistances: Dictionary = {}            # StringName type → float [0–1]
var aura_resistances: Dictionary = {}            # StringName type → float [0–1]; suppressable
var suppressed_aura_types: Array[StringName] = [] # types whose aura resistance is zeroed (Necrotic)

var speed_modifiers: Dictionary = {}             # StringName source_id → float (negative = slow)

var current_damage: float = 0.0
var max_hp: float = 100.0
var rot_immune: bool = false
