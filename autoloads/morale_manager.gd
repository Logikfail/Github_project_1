extends Node
## Morale Counter state machine. Tracks player alignment across a village run.
## Resets to 0 at each village start. Fail state reached when morale hits MORALE_MAX.


# === Signals ===

signal morale_changed(new_value: int)
signal fail_state_reached()


# === Private Variables ===

var _morale: int = 0


# === Lifecycle ===

func _ready() -> void:
	VillagerManager.villager_escaped.connect(_on_villager_escaped)
	VillagerManager.villager_infected.connect(_on_villager_infected)


# === Public API ===

func get_morale() -> int:
	return _morale


func get_morale_state() -> StringName:
	match _morale:
		GameConfig.MORALE_MIN:      return &"pure_evil"
		GameConfig.MORALE_MIN + 1:  return &"evil"
		0:                          return &"neutral"
		GameConfig.MORALE_MAX - 1:  return &"righteous"
		_:                          return &"fail"


func reset() -> void:
	_morale = 0
	morale_changed.emit(_morale)


# === Private Methods ===

func _shift(amount: int) -> void:
	var prev: int = _morale
	_morale = clampi(_morale + amount, GameConfig.MORALE_MIN, GameConfig.MORALE_MAX)
	if _morale != prev:
		morale_changed.emit(_morale)
	if _morale >= GameConfig.MORALE_MAX:
		fail_state_reached.emit()


# === Signal Handlers ===

func _on_villager_escaped(_villager: Node) -> void:
	_shift(GameConfig.MORALE_SHIFT_PER_ESCAPE)


func _on_villager_infected(_villager: Node) -> void:
	_shift(-GameConfig.MORALE_SHIFT_PER_INFECTION)
