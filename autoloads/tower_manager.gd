extends Node
## Owns all tower and barricade state — attack shapes, targeting, firing, demolish.
## Consumes EntityManager (lifecycle), InfectionManager (effects),
## NavigationManager (obstacles), and VillagerManager (demolish signal).


# === Signals ===

signal barricade_destroyed(barricade: Node, tile: Vector2i)
signal tower_inspected(tower: Node)
signal tower_fired(from_pos: Vector2, to_pos: Vector2)
signal tower_aoe_burst(center_pos: Vector2, radius: float)
signal tower_chain_fired(positions: Array[Vector2])
signal tower_line_fired(from_pos: Vector2, line_end: Vector2)
signal ground_patch_spawned(patch_id: int, world_pos: Vector2, radius: float)
signal ground_patch_expired(patch_id: int)
signal call_of_void_spawned(void_id: int, world_pos: Vector2)
signal call_of_void_depleted(void_id: int)


# === Private Variables ===

var _states: Dictionary = {}         # Node → TowerState
var _ground_patches: Array[GroundPatch] = []
var _calls_of_void: Array[CallOfVoid] = []
var _next_zone_id: int = 0


# === Inner Classes ===

class TowerState:
	var tower_data: TowerData = null
	var tile: Vector2i = Vector2i.ZERO
	var targeting_mode: StringName = &"closest"
	var fire_accumulator: float = 0.0
	var is_barricade: bool = false
	var barricade_hp: float = 0.0
	var expanding_radius: float = 0.0
	var expanding_active: bool = false
	var expanding_hit: Dictionary = {}  # Node → bool


class GroundPatch:
	var id: int = 0
	var world_pos: Vector2 = Vector2.ZERO
	var radius: float = 0.0
	var duration_remaining: float = 0.0
	var infection_effects: Array[InfectionEffect] = []
	var tick_accumulator: float = 0.0


class CallOfVoid:
	var id: int = 0
	var world_pos: Vector2 = Vector2.ZERO
	var stacks_remaining: int = 0
	var in_radius: Dictionary = {}  # Node → bool, entry-detection per frame


# === Lifecycle ===

func _ready() -> void:
	EntityManager.register_type(
		&"tower",
		preload("res://scenes/towers/tower_base.tscn"),
		10
	)
	VillagerManager.barricade_demolish_tick.connect(_on_barricade_demolish_tick)
	InfectionManager.villager_died.connect(_on_villager_died)


func _physics_process(delta: float) -> void:
	_process_towers(delta)
	_process_ground_patches(delta)
	_process_calls_of_void()


# === Public API ===

func place_tower(tower_data: TowerData, tile: Vector2i) -> Node:
	NavigationManager.place_obstacle(tile)
	var pos: Vector2 = NavigationManager.tile_to_world(tile)
	var entity: Node = EntityManager.spawn_entity(&"tower", pos, {})

	var state := TowerState.new()
	state.tower_data = tower_data
	state.tile = tile
	state.targeting_mode = tower_data.default_targeting_mode
	_states[entity] = state

	var tower_node: TowerBase = entity as TowerBase
	if is_instance_valid(tower_node):
		tower_node.setup_visuals(tower_data.range_radius)

	return entity


func set_targeting_mode(tower: Node, mode: StringName) -> void:
	if not _states.has(tower):
		return
	(_states[tower] as TowerState).targeting_mode = mode


func get_targeting_mode(tower: Node) -> StringName:
	if not _states.has(tower):
		return &""
	return (_states[tower] as TowerState).targeting_mode


func convert_to_barricade(tower: Node) -> Node:
	if not _states.has(tower):
		return tower
	var state: TowerState = _states[tower] as TowerState
	state.is_barricade = true
	state.barricade_hp = GameConfig.BARRICADE_HP
	state.fire_accumulator = 0.0
	state.expanding_active = false
	state.expanding_hit.clear()
	var tower_node: TowerBase = tower as TowerBase
	if is_instance_valid(tower_node):
		tower_node.set_barricade_visual()
	return tower


func get_tower_data(tower: Node) -> TowerData:
	if not _states.has(tower):
		return null
	return (_states[tower] as TowerState).tower_data


func is_barricade(tower: Node) -> bool:
	if not _states.has(tower):
		return false
	return (_states[tower] as TowerState).is_barricade


func notify_tower_clicked(tower: Node) -> void:
	if _states.has(tower):
		tower_inspected.emit(tower)


func upgrade_tower(tower: Node, new_data: TowerData) -> void:
	if not _states.has(tower):
		return
	var state: TowerState = _states[tower] as TowerState
	if state.is_barricade:
		return
	state.tower_data = new_data
	state.targeting_mode = new_data.default_targeting_mode
	state.fire_accumulator = 0.0
	state.expanding_active = false
	state.expanding_hit.clear()


func apply_stat_delta(tower_type: StringName, stat_name: StringName, delta: float) -> void:
	for tower: Node in _states.keys():
		if not is_instance_valid(tower):
			continue
		var state: TowerState = _states[tower] as TowerState
		if state.is_barricade:
			continue
		if state.tower_data.tower_type != tower_type:
			continue
		match stat_name:
			&"chain_count":
				state.tower_data.chain_count += int(delta)
			&"contact_range":
				state.tower_data.range_radius += delta
			&"aoe_radius":
				state.tower_data.aoe_radius += delta
			# pulse_frequency: positive delta increases fire rate (reduces interval)
			&"pulse_frequency":
				state.tower_data.fire_rate = maxf(GameConfig.TOWER_MIN_FIRE_RATE, state.tower_data.fire_rate - delta)


func clear_all() -> void:
	for tower: Node in _states.keys():
		if not is_instance_valid(tower):
			continue
		var state: TowerState = _states[tower] as TowerState
		NavigationManager.remove_obstacle(state.tile)
		EntityManager.despawn_entity(tower)
	_states.clear()


func get_all_towers() -> Array[Node]:
	var result: Array[Node] = []
	for tower: Node in _states.keys():
		if is_instance_valid(tower):
			result.append(tower)
	return result


func get_barricades() -> Array[Node]:
	var result: Array[Node] = []
	for tower: Node in _states.keys():
		if not is_instance_valid(tower):
			continue
		if (_states[tower] as TowerState).is_barricade:
			result.append(tower)
	return result


func demolish_barricade(tower: Node, damage: float) -> void:
	if not _states.has(tower):
		return
	var state: TowerState = _states[tower] as TowerState
	# Non-barricade towers can still be demolished — give them HP on first hit
	if not state.is_barricade and state.barricade_hp <= 0.0:
		state.barricade_hp = GameConfig.BARRICADE_HP
	state.barricade_hp -= damage
	if state.barricade_hp <= 0.0:
		_destroy_barricade(tower, state)


# === Private — Tower Processing ===

func _process_towers(delta: float) -> void:
	for tower: Node in _states.keys():
		if not is_instance_valid(tower):
			continue
		var state: TowerState = _states[tower] as TowerState
		if state.is_barricade:
			continue
		if state.tower_data.attack_shape == &"expanding_aoe":
			_process_expanding(tower, state, delta)
		else:
			state.fire_accumulator += delta
			if state.fire_accumulator >= state.tower_data.fire_rate:
				state.fire_accumulator -= state.tower_data.fire_rate
				_fire_tower(tower, state)


func _fire_tower(tower: Node, state: TowerState) -> void:
	var pos: Vector2 = EntityManager.get_entity_position(tower)
	var in_range: Array[Node] = EntityManager.get_entities_in_radius(
		pos, state.tower_data.range_radius, &"villager"
	)
	if in_range.is_empty():
		return
	match state.tower_data.attack_shape:
		&"single":
			_fire_single(pos, state, in_range)
		&"circle_aoe":
			_fire_circle_aoe(pos, state, in_range)
		&"cone":
			_fire_cone(pos, state, in_range)
		&"line":
			_fire_line(pos, state, in_range)
		&"chain":
			_fire_chain(pos, state, in_range)
		&"targeted_aoe":
			_fire_targeted_aoe(pos, state, in_range)


# === Private — Attack Shapes ===

func _fire_single(tower_pos: Vector2, state: TowerState, in_range: Array[Node]) -> void:
	var target: Node = _select_target(tower_pos, state.targeting_mode, in_range)
	if not target:
		return
	var target_pos: Vector2 = EntityManager.get_entity_position(target)
	tower_fired.emit(tower_pos, target_pos)
	_apply_effects(target, state.tower_data)
	if state.tower_data.tower_type == &"festering":
		_spawn_ground_patch(target_pos, state.tower_data)


func _fire_circle_aoe(tower_pos: Vector2, state: TowerState, in_range: Array[Node]) -> void:
	tower_aoe_burst.emit(tower_pos, state.tower_data.range_radius)
	for v: Node in in_range:
		tower_fired.emit(tower_pos, EntityManager.get_entity_position(v))
		_apply_effects(v, state.tower_data)


func _fire_cone(tower_pos: Vector2, state: TowerState, in_range: Array[Node]) -> void:
	var best_dir: Vector2 = _find_densest_cone_dir(
		tower_pos, in_range, state.tower_data.cone_angle
	)
	var half_angle_rad: float = deg_to_rad(state.tower_data.cone_angle * 0.5)
	var cos_half: float = cos(half_angle_rad)
	for v: Node in in_range:
		var to_v: Vector2 = (EntityManager.get_entity_position(v) - tower_pos).normalized()
		if best_dir.dot(to_v) >= cos_half:
			tower_fired.emit(tower_pos, EntityManager.get_entity_position(v))
			_apply_effects(v, state.tower_data)


func _find_densest_cone_dir(
	tower_pos: Vector2, in_range: Array[Node], cone_angle: float
) -> Vector2:
	var best_count: int = 0
	var best_dir: Vector2 = Vector2.RIGHT
	var half_angle_rad: float = deg_to_rad(cone_angle * 0.5)
	var cos_half: float = cos(half_angle_rad)
	for candidate: Node in in_range:
		var candidate_dir: Vector2 = (EntityManager.get_entity_position(candidate) - tower_pos).normalized()
		var count: int = 0
		for v: Node in in_range:
			var to_v: Vector2 = (EntityManager.get_entity_position(v) - tower_pos).normalized()
			if candidate_dir.dot(to_v) >= cos_half:
				count += 1
		if count > best_count:
			best_count = count
			best_dir = candidate_dir
	return best_dir


func _fire_line(tower_pos: Vector2, state: TowerState, in_range: Array[Node]) -> void:
	var target: Node = _select_target(tower_pos, state.targeting_mode, in_range)
	if not target:
		return
	var line_dir: Vector2 = (EntityManager.get_entity_position(target) - tower_pos).normalized()
	var line_end: Vector2 = tower_pos + line_dir * state.tower_data.range_radius
	tower_line_fired.emit(tower_pos, line_end)
	for v: Node in in_range:
		if _point_to_segment_dist(EntityManager.get_entity_position(v), tower_pos, line_end) <= GameConfig.TOWER_LINE_HALF_WIDTH:
			_apply_effects(v, state.tower_data)


func _fire_chain(tower_pos: Vector2, state: TowerState, in_range: Array[Node]) -> void:
	var primary: Node = _select_target(tower_pos, state.targeting_mode, in_range)
	if not primary:
		return
	var visited: Dictionary = {}
	var current: Node = primary
	var prev_pos: Vector2 = tower_pos
	var hops_remaining: int = state.tower_data.chain_count
	var hop_positions: Array[Vector2] = [tower_pos]

	while hops_remaining > 0 and is_instance_valid(current):
		var cur_pos: Vector2 = EntityManager.get_entity_position(current)
		hop_positions.append(cur_pos)
		_apply_effects(current, state.tower_data)
		visited[current] = true
		prev_pos = cur_pos
		hops_remaining -= 1
		if hops_remaining == 0:
			break
		current = _find_nearest_chain_hop(current, visited)
		if not current:
			break

	tower_chain_fired.emit(hop_positions)


func _find_nearest_chain_hop(from: Node, visited: Dictionary) -> Node:
	var from_pos: Vector2 = EntityManager.get_entity_position(from)
	var nearby: Array[Node] = EntityManager.get_entities_in_radius(
		from_pos, GameConfig.TOWER_CHAIN_HOP_RANGE, &"villager"
	)
	var best: Node = null
	var best_dist_sq: float = INF
	for v: Node in nearby:
		if visited.has(v):
			continue
		var d: float = from_pos.distance_squared_to(EntityManager.get_entity_position(v))
		if d < best_dist_sq:
			best_dist_sq = d
			best = v
	return best


func _fire_targeted_aoe(tower_pos: Vector2, state: TowerState, in_range: Array[Node]) -> void:
	var anchor: Node = _select_target(tower_pos, state.targeting_mode, in_range)
	if not anchor:
		return
	var anchor_pos: Vector2 = EntityManager.get_entity_position(anchor)
	tower_fired.emit(tower_pos, anchor_pos)
	var aoe_targets: Array[Node] = EntityManager.get_entities_in_radius(
		anchor_pos, state.tower_data.aoe_radius, &"villager"
	)
	tower_aoe_burst.emit(anchor_pos, state.tower_data.aoe_radius)
	for v: Node in aoe_targets:
		tower_fired.emit(anchor_pos, EntityManager.get_entity_position(v))
		_apply_effects(v, state.tower_data)


func _process_expanding(tower: Node, state: TowerState, delta: float) -> void:
	if not state.expanding_active:
		state.fire_accumulator += delta
		if state.fire_accumulator >= state.tower_data.fire_rate:
			state.fire_accumulator -= state.tower_data.fire_rate
			state.expanding_active = true
			state.expanding_radius = 0.0
			state.expanding_hit.clear()
		return

	state.expanding_radius += state.tower_data.expanding_speed * delta
	var tower_pos: Vector2 = EntityManager.get_entity_position(tower)
	var in_radius: Array[Node] = EntityManager.get_entities_in_radius(
		tower_pos, state.expanding_radius, &"villager"
	)
	for v: Node in in_radius:
		if not state.expanding_hit.has(v):
			state.expanding_hit[v] = true
			tower_fired.emit(tower_pos, EntityManager.get_entity_position(v))
			_apply_effects(v, state.tower_data)

	if state.expanding_radius >= state.tower_data.range_radius:
		state.expanding_active = false


# === Private — Targeting System ===

func _select_target(
	tower_pos: Vector2, mode: StringName, in_range: Array[Node]
) -> Node:
	if in_range.is_empty():
		return null
	match mode:
		&"closest":
			return _target_closest(tower_pos, in_range)
		&"first":
			return _target_first(in_range)
		&"last":
			return _target_last(in_range)
		&"healthiest":
			return _target_healthiest(in_range)
		&"uninfected":
			return _target_uninfected(tower_pos, in_range)
		&"most_infected":
			return _target_most_infected(in_range)
	return _target_closest(tower_pos, in_range)


func _target_closest(tower_pos: Vector2, candidates: Array[Node]) -> Node:
	var best: Node = null
	var best_dist_sq: float = INF
	for v: Node in candidates:
		var d: float = tower_pos.distance_squared_to(EntityManager.get_entity_position(v))
		if d < best_dist_sq:
			best_dist_sq = d
			best = v
	return best


func _target_first(candidates: Array[Node]) -> Node:
	# First = villager closest to their nearest exit (will escape soonest)
	var best: Node = null
	var best_dist_sq: float = INF
	for v: Node in candidates:
		var vpos: Vector2 = EntityManager.get_entity_position(v)
		var exit_pos: Vector2 = NavigationManager.get_closest_exit_position(vpos)
		var d: float = exit_pos.distance_squared_to(vpos)
		if d < best_dist_sq:
			best_dist_sq = d
			best = v
	return best


func _target_last(candidates: Array[Node]) -> Node:
	# Last = villager furthest from their nearest exit (least path progress)
	var best: Node = null
	var worst_dist_sq: float = -1.0
	for v: Node in candidates:
		var vpos: Vector2 = EntityManager.get_entity_position(v)
		var exit_pos: Vector2 = NavigationManager.get_closest_exit_position(vpos)
		var d: float = exit_pos.distance_squared_to(vpos)
		if d > worst_dist_sq:
			worst_dist_sq = d
			best = v
	return best


func _target_healthiest(candidates: Array[Node]) -> Node:
	var best: Node = null
	var lowest_pct: float = INF
	for v: Node in candidates:
		var pct: float = InfectionManager.get_infection_pct(v)
		if pct < lowest_pct:
			lowest_pct = pct
			best = v
	return best


func _target_uninfected(tower_pos: Vector2, candidates: Array[Node]) -> Node:
	var uninfected: Array[Node] = []
	for v: Node in candidates:
		if InfectionManager.get_infection_pct(v) == 0.0:
			uninfected.append(v)
	if uninfected.is_empty():
		return _target_closest(tower_pos, candidates)
	return _target_closest(tower_pos, uninfected)


func _target_most_infected(candidates: Array[Node]) -> Node:
	var best: Node = null
	var highest_pct: float = -1.0
	for v: Node in candidates:
		var pct: float = InfectionManager.get_infection_pct(v)
		if pct > highest_pct:
			highest_pct = pct
			best = v
	return best


# === Private — Ground Patches ===

func _spawn_ground_patch(world_pos: Vector2, tower_data: TowerData) -> void:
	var patch := GroundPatch.new()
	patch.id = _next_zone_id
	_next_zone_id += 1
	patch.world_pos = world_pos
	patch.radius = GameConfig.FESTERING_PATCH_RADIUS
	patch.duration_remaining = GameConfig.FESTERING_PATCH_DURATION
	patch.infection_effects = tower_data.infection_effects.duplicate()
	_ground_patches.append(patch)
	ground_patch_spawned.emit(patch.id, world_pos, patch.radius)


func _process_ground_patches(delta: float) -> void:
	var remaining: Array[GroundPatch] = []
	for patch: GroundPatch in _ground_patches:
		patch.duration_remaining -= delta
		if patch.duration_remaining <= 0.0:
			ground_patch_expired.emit(patch.id)
			continue
		patch.tick_accumulator += delta
		if patch.tick_accumulator >= GameConfig.FESTERING_PATCH_TICK_INTERVAL:
			patch.tick_accumulator -= GameConfig.FESTERING_PATCH_TICK_INTERVAL
			var in_patch: Array[Node] = EntityManager.get_entities_in_radius(
				patch.world_pos, patch.radius, &"villager"
			)
			for v: Node in in_patch:
				for effect: InfectionEffect in patch.infection_effects:
					InfectionManager.apply_effect(v, effect)
		remaining.append(patch)
	_ground_patches = remaining


# === Private — Call of the Void ===

func _spawn_call_of_void(world_pos: Vector2) -> void:
	var cv := CallOfVoid.new()
	cv.id = _next_zone_id
	_next_zone_id += 1
	cv.world_pos = world_pos
	cv.stacks_remaining = GameConfig.CALL_OF_VOID_STACKS
	_calls_of_void.append(cv)
	call_of_void_spawned.emit(cv.id, world_pos)


func _process_calls_of_void() -> void:
	var remaining: Array[CallOfVoid] = []
	for cv: CallOfVoid in _calls_of_void:
		var in_radius: Array[Node] = EntityManager.get_entities_in_radius(
			cv.world_pos, GameConfig.CALL_OF_VOID_RADIUS, &"villager"
		)
		var currently_in: Dictionary = {}
		for v: Node in in_radius:
			currently_in[v] = true
			if not cv.in_radius.has(v):
				_apply_call_of_void_contact(v)
				cv.stacks_remaining -= 1
				if cv.stacks_remaining <= 0:
					break
		cv.in_radius = currently_in
		if cv.stacks_remaining > 0:
			remaining.append(cv)
		else:
			call_of_void_depleted.emit(cv.id)
	_calls_of_void = remaining


func _apply_call_of_void_contact(villager: Node) -> void:
	var effect := InfectionEffect.new()
	effect.effect_type = &"blight"
	effect.base_damage = GameConfig.VILLAGER_BASE_HP * GameConfig.CALL_OF_VOID_BLIGHT_RATIO
	effect.tick_count = 1
	effect.slow_amount = GameConfig.CALL_OF_VOID_SLOW
	InfectionManager.apply_effect(villager, effect)


# === Private — Barricade ===

func _destroy_barricade(barricade: Node, state: TowerState) -> void:
	var tile: Vector2i = state.tile
	NavigationManager.remove_obstacle(tile)
	_states.erase(barricade)
	EntityManager.despawn_entity(barricade)
	barricade_destroyed.emit(barricade, tile)


# === Signal Handlers ===

func _on_barricade_demolish_tick(_villager: Node, barricade: Node, damage: float) -> void:
	demolish_barricade(barricade, damage)


func _on_villager_died(villager: Node, _cause: StringName) -> void:
	if not is_instance_valid(villager):
		return
	var vpos: Vector2 = EntityManager.get_entity_position(villager)
	for tower: Node in _states.keys():
		if not is_instance_valid(tower):
			continue
		var state: TowerState = _states[tower] as TowerState
		if state.is_barricade or state.tower_data.tower_type != &"corpse_bloom":
			continue
		var tpos: Vector2 = EntityManager.get_entity_position(tower)
		var range_sq: float = state.tower_data.range_radius * state.tower_data.range_radius
		if tpos.distance_squared_to(vpos) <= range_sq:
			_spawn_call_of_void(vpos)
			break


# === Utilities ===

func _apply_effects(villager: Node, tower_data: TowerData) -> void:
	for effect: InfectionEffect in tower_data.infection_effects:
		InfectionManager.apply_effect(villager, effect)


func _point_to_segment_dist(point: Vector2, seg_a: Vector2, seg_b: Vector2) -> float:
	var seg: Vector2 = seg_b - seg_a
	var len_sq: float = seg.length_squared()
	if len_sq == 0.0:
		return point.distance_to(seg_a)
	var t: float = clampf((point - seg_a).dot(seg) / len_sq, 0.0, 1.0)
	return point.distance_to(seg_a + t * seg)


