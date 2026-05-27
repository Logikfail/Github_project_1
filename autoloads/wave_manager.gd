extends Node
## Manages the lifecycle of a single wave — spawn, path polling, completion, Desperate trigger.
## Consumes VillagerManager (spawn/signals), TowerManager (barricade list),
## NavigationManager (path existence), and GameConfig (timing constants).


# === Signals ===

signal wave_complete(house: Node, all_infected: bool, escaped_count: int, infected_count: int)
signal no_path_detected()


# === Private Variables ===

var _wave: WaveState = null
var _spawn_queue: Array[Dictionary] = []
var _spawn_timer: float = 0.0


# === Inner Class ===

class WaveState:
	var house: Node = null
	var total: int = 0
	var infected: int = 0
	var escaped: int = 0
	var no_path_timer: float = -1.0   # -1 = not counting; >= 0 = countdown in progress
	var desperate_triggered: bool = false


# === Lifecycle ===

func _ready() -> void:
	VillagerManager.villager_escaped.connect(_on_villager_escaped)
	VillagerManager.villager_infected.connect(_on_villager_infected)
	TowerManager.barricade_destroyed.connect(_on_barricade_destroyed)


func _physics_process(delta: float) -> void:
	if not _wave:
		return
	_poll_path(delta)
	_process_spawn_queue(delta)


# === Public API ===

func start_wave(house: Node, scale: float = 1.0) -> void:
	if _wave:
		push_warning("WaveManager: start_wave called while wave already active")
		return

	var base_archetypes: Array[StringName] = []
	var raw: Variant = house.get("villager_archetypes")
	if raw != null and raw is Array:
		for a: Variant in (raw as Array):
			base_archetypes.append(a as StringName)
	if base_archetypes.is_empty():
		base_archetypes.append(&"standard")

	var scaled_count: int = maxi(1, roundi(base_archetypes.size() * scale))

	_wave = WaveState.new()
	_wave.house = house
	_wave.total = scaled_count

	_spawn_queue.clear()
	_spawn_timer = 0.0
	for i: int in scaled_count:
		_spawn_queue.append({
			"archetype": base_archetypes[i % base_archetypes.size()],
			"house": house,
		})


func get_wave_status() -> Dictionary:
	if not _wave:
		return { "total": 0, "infected": 0, "escaped": 0, "in_progress": false }
	return {
		"total": _wave.total,
		"infected": _wave.infected,
		"escaped": _wave.escaped,
		"in_progress": true,
	}


func is_wave_active() -> bool:
	return _wave != null


func reset() -> void:
	_wave = null
	_spawn_queue.clear()
	_spawn_timer = 0.0


# === Private — Spawn Queue ===

func _process_spawn_queue(delta: float) -> void:
	if _spawn_queue.is_empty():
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = GameConfig.WAVE_SPAWN_INTERVAL
	var batch: int = mini(GameConfig.WAVE_SPAWN_BATCH_SIZE, _spawn_queue.size())
	for _i: int in batch:
		if _spawn_queue.is_empty():
			break
		var entry: Dictionary = _spawn_queue.pop_front()
		var villager: Node = VillagerManager.spawn_villager(
			entry["archetype"] as StringName, entry["house"] as Node
		)
		# If desperate state already triggered this wave, route the new villager
		# straight to the nearest barricade so it doesn't sit idle.
		if _wave.desperate_triggered and is_instance_valid(villager):
			var barricades: Array[Node] = TowerManager.get_barricades()
			if not barricades.is_empty():
				var nearest: Node = _nearest_barricade(villager, barricades)
				if nearest:
					VillagerManager.set_desperate(villager, nearest)


# === Private — Path Polling ===

func _poll_path(delta: float) -> void:
	var house_pos: Vector2 = EntityManager.get_entity_position(_wave.house)
	var path_ok: bool = NavigationManager.path_exists_to_any_exit(house_pos)

	if path_ok:
		# Path restored — reset countdown so it can re-trigger if blocked again
		_wave.no_path_timer = -1.0
		_wave.desperate_triggered = false
		return

	if _wave.desperate_triggered:
		return

	if _wave.no_path_timer < 0.0:
		_wave.no_path_timer = GameConfig.DESPERATE_STATE_DELAY
	else:
		_wave.no_path_timer -= delta
		if _wave.no_path_timer <= 0.0:
			_wave.desperate_triggered = true
			_wave.no_path_timer = -1.0
			_trigger_desperate()


func _trigger_desperate() -> void:
	var barricades: Array[Node] = TowerManager.get_barricades()
	VillagerManager.set_all_desperate(barricades)
	no_path_detected.emit()


func _nearest_barricade(villager: Node, barricades: Array[Node]) -> Node:
	var best: Node = null
	var best_dist_sq: float = INF
	var spos: Vector2 = EntityManager.get_entity_position(villager)
	for b: Node in barricades:
		if not is_instance_valid(b):
			continue
		var d: float = spos.distance_squared_to(EntityManager.get_entity_position(b))
		if d < best_dist_sq:
			best_dist_sq = d
			best = b
	return best


# === Private — Wave Completion ===

func _check_wave_complete() -> void:
	if not _wave:
		return
	if not _spawn_queue.is_empty():
		return
	if _wave.infected + _wave.escaped < _wave.total:
		return
	var house: Node = _wave.house
	var all_infected: bool = _wave.escaped == 0
	var escaped_count: int = _wave.escaped
	var infected_count: int = _wave.infected
	_wave = null
	wave_complete.emit(house, all_infected, escaped_count, infected_count)


# === Signal Handlers ===

func _on_villager_escaped(_villager: Node) -> void:
	if not _wave:
		return
	_wave.escaped += 1
	_check_wave_complete()


func _on_villager_infected(_villager: Node) -> void:
	if not _wave:
		return
	_wave.infected += 1
	_check_wave_complete()


func _on_barricade_destroyed(barricade: Node, tile: Vector2i) -> void:
	VillagerManager.handle_barricade_destroyed(barricade, tile)


