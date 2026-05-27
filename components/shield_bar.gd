class_name ShieldBar
extends ProgressBar
## Guard villager secondary shield bar. Blue; hides when shield is not active.
## Attach to a ProgressBar node on the guard villager scene. Call setup(villager) after spawn.


# === Constants ===

const COLOR_SHIELD: Color = Color(0.2, 0.6, 1.0)


# === Private Variables ===

var _villager: Node = null


# === Public API ===

func setup(villager: Node) -> void:
	_villager = villager
	min_value = 0.0
	max_value = GameConfig.GUARD_SHIELD_HP
	modulate = COLOR_SHIELD
	visible = false


# === Lifecycle ===

func _process(_delta: float) -> void:
	if not is_instance_valid(_villager):
		visible = false
		return
	var active: bool = VillagerManager.is_shield_active(_villager)
	visible = active
	if active:
		value = VillagerManager.get_shield_hp(_villager)
