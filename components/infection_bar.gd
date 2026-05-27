class_name InfectionBar
extends ProgressBar
## Per-villager infection progress bar. Colour lerps caustic green → toxic purple.
## Attach to a ProgressBar node on the villager scene. Call setup(villager) after spawn.


# === Constants ===

const COLOR_HEALTHY: Color = Color(0.2, 0.8, 0.2)
const COLOR_INFECTED: Color = Color(0.6, 0.1, 0.8)
const COLOR_DEATH_FLASH: Color = Color.WHITE
const DEATH_FLASH_DURATION: float = 0.15


# === Private Variables ===

var _villager: Node = null
var _flashing: bool = false
var _last_pct: float = 0.0


# === Public API ===

func setup(villager: Node) -> void:
	_villager = villager
	min_value = 0.0
	max_value = 1.0
	value = 0.0
	modulate = COLOR_HEALTHY


# === Lifecycle ===

func _process(_delta: float) -> void:
	if not is_instance_valid(_villager):
		return
	var pct: float = InfectionManager.get_infection_pct(_villager)
	value = pct
	if not _flashing:
		modulate = COLOR_HEALTHY.lerp(COLOR_INFECTED, pct)
	# Trigger death flash on the tick the bar reaches 100%
	if pct >= 1.0 and _last_pct < 1.0:
		_trigger_death_flash()
	_last_pct = pct


# === Private ===

func _trigger_death_flash() -> void:
	_flashing = true
	modulate = COLOR_DEATH_FLASH
	var tween := create_tween()
	tween.tween_property(self, "modulate", COLOR_INFECTED, DEATH_FLASH_DURATION)
	tween.tween_callback(func() -> void: _flashing = false)
