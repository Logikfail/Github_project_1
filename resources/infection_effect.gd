class_name InfectionEffect
extends Resource
## Config template for one DoT type applied by a tower.
## Stored in TowerData.infection_effects; passed to InfectionManager.apply_effect().


# === Exports ===

@export var effect_type: StringName = &""        # &"blight", &"plague", &"pestilence", etc.
@export var base_damage: float = 0.0
@export var escalation_rate: float = 0.0         # 0 = flat; >0 = Blight escalation
@export var tick_count: int = 5                  # ticks before expiry; 0 = persistent (AOE-managed)
@export var spread_chance: float = 0.0           # Pestilence: roll per tick
@export var spread_range: float = 0.0            # Pestilence: radius for spread targets
@export var resistance_mod: float = 0.0          # Miasma: how much it reduces others' resistances
@export var slow_amount: float = 0.0             # additive movement slow (fraction of base speed)
@export var rot_stacks: int = 0                  # Rot stacks added per application
