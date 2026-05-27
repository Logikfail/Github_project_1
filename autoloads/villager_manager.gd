extends Node
## Villager AI, movement, and all archetype behaviours.
## Consumes NavigationManager (paths), InfectionManager (effects), EntityManager (lifecycle).


# === Enums ===

enum MoveState { MOVING, DESPERATE, ESCAPED, DEAD }


# === Signals ===

signal villager_escaped(villager: Node)
signal villager_infected(villager: Node)
signal barricade_demolish_tick(villager: Node, barricade: Node, damage: float)


# === Private Variables ===

var _states: Dictionary = {}              # Node → VillagerState
var _demolish_accumulator: float = 0.0


# === Lifecycle ===

func _ready() -> void:
	EntityManager.register_type(&"villager", preload("res://scenes/villager.tscn"), 20)
	InfectionManager.villager_died.connect(_on_villager_died)
	InfectionManager.rot_threshold_reached.connect(_on_rot_threshold_reached)


func _physics_process(delta: float) -> void:
	_process_movement(delta)
	_process_auras(delta)
	_process_demolish(delta)


# === Public API ===

func spawn_villager(archetype: StringName, house: Node) -> Node:
	var pos: Vector2 = _get_spawn_pos_near_house(house)
	var villager: Node = EntityManager.spawn_entity(&"villager", pos, {})

	var hp_ratio: float = GameConfig.ARCHETYPE_HP_RATIOS.get(archetype, 1.0)
	InfectionManager.register_villager(villager, GameConfig.VILLAGER_BASE_HP * hp_ratio)

	var state := VillagerState.new()
	state.archetype = archetype
	state.move_state = MoveState.MOVING
	_states[villager] = state

	_setup_archetype(villager, state)
	_request_path(villager, state)

	return villager


func set_desperate(villager: Node, target_barricade: Node) -> void:
	if not _states.has(villager):
		return
	var state: VillagerState = _states[villager]
	state.move_state = MoveState.DESPERATE
	state.desperate_target = target_barricade
	state.path = PackedVector2Array()
	state.path_index = 0


func get_shield_hp(villager: Node) -> float:
	if not _states.has(villager):
		return 0.0
	return (_states[villager] as VillagerState).shield_hp


func is_shield_active(villager: Node) -> bool:
	if not _states.has(villager):
		return false
	return (_states[villager] as VillagerState).shield_active


func get_aura_recipients(source: Node, radius: float) -> Array[Node]:
	return EntityManager.get_entities_in_radius(EntityManager.get_entity_position(source), radius, &"villager")


func set_all_desperate(barricades: Array[Node]) -> void:
	for villager: Node in _states.keys():
		if not is_instance_valid(villager):
			continue
		var state: VillagerState = _states[villager]
		if state.move_state != MoveState.MOVING:
			continue
		var nearest: Node = _find_nearest_from_list(villager, barricades)
		if nearest:
			set_desperate(villager, nearest)


# === Private Methods — Utilities ===

func _find_nearest_from_list(source: Node, candidates: Array[Node]) -> Node:
	var best: Node = null
	var best_dist_sq: float = INF
	var spos: Vector2 = EntityManager.get_entity_position(source)
	for c: Node in candidates:
		if not is_instance_valid(c):
			continue
		var d: float = spos.distance_squared_to(EntityManager.get_entity_position(c))
		if d < best_dist_sq:
			best_dist_sq = d
			best = c
	return best


# === Private Methods — Setup ===

func _setup_archetype(villager: Node, state: VillagerState) -> void:
	match state.archetype:
		&"guard":
			state.shield_hp = GameConfig.GUARD_SHIELD_HP
			state.shield_active = true
		&"gravedigger":
			InfectionManager.set_rot_immune(villager, true)
			for type: StringName in GameConfig.INFECTION_EFFECT_TYPES:
				InfectionManager.set_base_resistance(villager, type, GameConfig.GRAVEDIGGER_FLAT_RESISTANCE)


func _get_spawn_pos_near_house(house: Node) -> Vector2:
	var raw: Variant = house.get("spawn_tile")
	if raw == null:
		return EntityManager.get_entity_position(house)
	var center_tile: Vector2i = raw as Vector2i
	var neighbors: Array[Vector2i] = NavigationManager.get_walkable_neighbors(center_tile)
	if neighbors.is_empty():
		return NavigationManager.tile_to_world(center_tile)
	return NavigationManager.tile_to_world(neighbors[randi() % neighbors.size()])


func _request_path(villager: Node, state: VillagerState) -> void:
	var from: Vector2 = EntityManager.get_entity_position(villager)
	state.path = _find_path_to_any_exit(from, state.archetype == &"child")
	state.path_index = 0
	# If pathing fails, leave the villager idle — WaveManager polls path existence
	# from each house and will trigger desperate state globally via set_all_desperate.


func _find_path_to_any_exit(from: Vector2, ignore_obstacles: bool) -> PackedVector2Array:
	var exit_positions: Array[Vector2] = NavigationManager.get_exit_positions()
	var best_path: PackedVector2Array = PackedVector2Array()
	var best_dist: float = INF
	for exit_pos: Vector2 in exit_positions:
		var path: PackedVector2Array
		if ignore_obstacles:
			path = NavigationManager.request_path_ignore_obstacles(from, exit_pos)
		else:
			path = NavigationManager.request_path(from, exit_pos)
		if path.is_empty():
			continue
		var dist: float = from.distance_squared_to(exit_pos)
		if dist < best_dist:
			best_dist = dist
			best_path = path
	return best_path


# === Private Methods — Movement ===

func _process_movement(delta: float) -> void:
	var escaped: Array[Node] = []

	for villager: Node in _states.keys():
		if not is_instance_valid(villager):
			continue
		var state: VillagerState = _states[villager]
		match state.move_state:
			MoveState.MOVING:
				if _advance_path(villager, state, delta):
					escaped.append(villager)
			MoveState.DESPERATE:
				_advance_toward_barricade(villager, state, delta)

	for villager: Node in escaped:
		_despawn_escaped(villager)


func _advance_path(villager: Node, state: VillagerState, delta: float) -> bool:
	if state.path.is_empty():
		_request_path(villager, state)
		return false
	if state.path_index >= state.path.size():
		return true

	var base_speed: float = (
		GameConfig.VILLAGER_BASE_SPEED
		* GameConfig.ARCHETYPE_SPEED_MULTIPLIERS.get(state.archetype, 1.0)
	)
	var speed: float = base_speed * InfectionManager.get_speed_multiplier(villager)

	if state.archetype == &"child":
		var tile: Vector2i = NavigationManager.get_tile_at(EntityManager.get_entity_position(villager))
		if NavigationManager.is_tile_occupied(tile):
			speed *= (1.0 - GameConfig.CHILD_SOLID_SPEED_PENALTY)

	var villager3d: Node3D = villager as Node3D
	var current_xz := Vector2(villager3d.global_position.x, villager3d.global_position.z)
	var target_wp: Vector2 = state.path[state.path_index]
	var dir: Vector2 = target_wp - current_xz
	var dist: float = dir.length()
	var step: float = speed * delta

	if step >= dist:
		villager3d.global_position.x = target_wp.x
		villager3d.global_position.z = target_wp.y
		state.path_index += 1
		if state.path_index >= state.path.size():
			return true
	else:
		var new_xz: Vector2 = current_xz + dir.normalized() * step
		villager3d.global_position.x = new_xz.x
		villager3d.global_position.z = new_xz.y

	return false


func _advance_toward_barricade(villager: Node, state: VillagerState, delta: float) -> void:
	if not is_instance_valid(state.desperate_target):
		state.move_state = MoveState.MOVING
		_request_path(villager, state)
		return

	var barricade_pos: Vector2 = EntityManager.get_entity_position(state.desperate_target)
	var villager3d: Node3D = villager as Node3D
	var current_xz := Vector2(villager3d.global_position.x, villager3d.global_position.z)
	var dir: Vector2 = barricade_pos - current_xz
	var dist: float = dir.length()
	var stop_dist: float = GameConfig.TILE_HALF_WIDTH

	if dist <= stop_dist:
		return

	var base_speed: float = (
		GameConfig.VILLAGER_BASE_SPEED
		* GameConfig.ARCHETYPE_SPEED_MULTIPLIERS.get(state.archetype, 1.0)
	)
	var speed: float = base_speed * InfectionManager.get_speed_multiplier(villager)
	var step: float = minf(speed * delta, dist - stop_dist)
	var new_xz: Vector2 = current_xz + dir.normalized() * step
	villager3d.global_position.x = new_xz.x
	villager3d.global_position.z = new_xz.y


# === Private Methods — Demolish Tick ===

func _process_demolish(delta: float) -> void:
	_demolish_accumulator += delta
	if _demolish_accumulator < GameConfig.DEMOLISH_TICK_INTERVAL:
		return
	_demolish_accumulator -= GameConfig.DEMOLISH_TICK_INTERVAL

	for villager: Node in _states.keys():
		if not is_instance_valid(villager):
			continue
		var state: VillagerState = _states[villager]
		if state.move_state != MoveState.DESPERATE:
			continue
		if not is_instance_valid(state.desperate_target):
			continue
		var dist: float = EntityManager.get_entity_position(villager).distance_to(EntityManager.get_entity_position(state.desperate_target))
		if dist <= GameConfig.TILE_HALF_WIDTH:
			barricade_demolish_tick.emit(villager, state.desperate_target, GameConfig.DEMOLISH_RATE)


# === Private Methods — Auras ===

func _process_auras(delta: float) -> void:
	var all_villagers: Array[Node] = EntityManager.get_all_entities(&"villager")

	# Clear all aura resistances so stale out-of-range values don't persist.
	# base_resistances (Gravedigger) and speed_modifiers are not touched here.
	for target: Node in all_villagers:
		if not is_instance_valid(target):
			continue
		for type: StringName in GameConfig.INFECTION_EFFECT_TYPES:
			InfectionManager.clear_aura_resistance(target, type)

	for source: Node in _states.keys():
		if not is_instance_valid(source):
			continue
		var state: VillagerState = _states[source]
		if state.move_state == MoveState.DEAD or state.move_state == MoveState.ESCAPED:
			continue
		match state.archetype:
			&"elder":
				_apply_elder_aura(source, all_villagers)
			&"priest":
				_apply_priest_aura(source, all_villagers)
			&"doctor":
				_apply_doctor_aura(source, all_villagers)
			&"guard":
				_apply_guard_shield(source, state, all_villagers, delta)


func _apply_elder_aura(source: Node, all_villagers: Array[Node]) -> void:
	var elder_id: StringName = StringName("elder_" + str(source.get_instance_id()))
	for target: Node in all_villagers:
		if target == source or not is_instance_valid(target):
			continue
		if _distance_xz(source, target) <= GameConfig.ELDER_AURA_RADIUS:
			InfectionManager.apply_speed_modifier(target, elder_id, GameConfig.ELDER_SPEED_BONUS)
		else:
			InfectionManager.remove_speed_modifier(target, elder_id)


func _apply_priest_aura(source: Node, all_villagers: Array[Node]) -> void:
	for target: Node in all_villagers:
		if target == source or not is_instance_valid(target):
			continue
		if _distance_xz(source, target) <= GameConfig.PRIEST_AURA_RADIUS:
			InfectionManager.apply_aura_resistance(target, &"pestilence", GameConfig.PRIEST_RESISTANCE_BONUS)


func _apply_doctor_aura(source: Node, all_villagers: Array[Node]) -> void:
	for target: Node in all_villagers:
		if target == source or not is_instance_valid(target):
			continue
		if _distance_xz(source, target) <= GameConfig.DOCTOR_AURA_RADIUS:
			InfectionManager.apply_aura_resistance(target, &"blight", GameConfig.DOCTOR_RESISTANCE_BONUS)


func _apply_guard_shield(
	source: Node, state: VillagerState, all_villagers: Array[Node], delta: float
) -> void:
	if not state.shield_active:
		return

	state.shield_hp -= GameConfig.GUARD_SHIELD_DRAIN_RATE * delta

	if state.shield_hp <= 0.0:
		state.shield_hp = 0.0
		state.shield_active = false
		# Shield broken: reset Guard's accumulated infection damage (continues at full HP)
		InfectionManager.reset_infection_damage(source)
		return

	for target: Node in all_villagers:
		if not is_instance_valid(target):
			continue
		if _distance_xz(source, target) <= GameConfig.GUARD_SHIELD_RADIUS:
			for type: StringName in GameConfig.INFECTION_EFFECT_TYPES:
				InfectionManager.apply_aura_resistance(target, type, 1.0)


# === Private Methods — Despawn ===

func _despawn_infected(villager: Node) -> void:
	if not _states.has(villager):
		return
	var state: VillagerState = _states[villager]
	_clear_aura_contributions(villager, state)
	EntityManager.despawn_entity(villager)
	_states.erase(villager)
	villager_infected.emit(villager)


func _despawn_escaped(villager: Node) -> void:
	if not _states.has(villager):
		return
	var state: VillagerState = _states[villager]
	_clear_aura_contributions(villager, state)
	InfectionManager.unregister_villager(villager)
	EntityManager.despawn_entity(villager)
	_states.erase(villager)
	villager_escaped.emit(villager)


func _clear_aura_contributions(villager: Node, state: VillagerState) -> void:
	if state.archetype != &"elder":
		return
	var elder_id: StringName = StringName("elder_" + str(villager.get_instance_id()))
	for target: Node in EntityManager.get_all_entities(&"villager"):
		if is_instance_valid(target):
			InfectionManager.remove_speed_modifier(target, elder_id)


# === Signal Handlers ===

func _on_villager_died(villager: Node, _cause: StringName) -> void:
	# InfectionManager already erased this villager from its own state.
	_despawn_infected(villager)


func _on_rot_threshold_reached(villager: Node) -> void:
	if not _states.has(villager):
		return
	# Rot explosion kills the villager — unregister before despawn.
	InfectionManager.unregister_villager(villager)
	_despawn_infected(villager)


func handle_barricade_destroyed(barricade: Node, _tile: Vector2i) -> void:
	for villager: Node in _states.keys():
		if not is_instance_valid(villager):
			continue
		var state: VillagerState = _states[villager]
		if state.move_state == MoveState.DESPERATE and state.desperate_target == barricade:
			state.move_state = MoveState.MOVING
			state.desperate_target = null
			state.path = PackedVector2Array()
			state.path_index = 0
			_request_path(villager, state)


# === Utilities ===

func _distance_xz(a: Node, b: Node) -> float:
	return EntityManager.get_entity_position(a).distance_to(EntityManager.get_entity_position(b))
