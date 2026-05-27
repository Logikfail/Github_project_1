extends Node
## Tower Draft pool management, Pending Draft carry-over, Keep/Combine resolution.
## Consumes TowerManager (place/upgrade/convert) and GameConfig (pool constants).


# === Signals ===

signal draft_resolved()
signal pending_draft_non_empty()
signal tower_placed_from_draft()


# === Private Variables ===

# Towers waiting to be placed (carries over between rounds)
var _pending_draft: Array[TowerData] = []
# TowerData → bool: marks pending towers that came from a Discovery Node (Keep-only)
var _synthesis_pending: Dictionary = {}

# Per-round placement tracking (cleared on resolution)
var _placed_nodes: Array[Node] = []
var _placed_data: Dictionary = {}        # Node → TowerData
var _placed_synthesis: Dictionary = {}   # Node → bool (Keep-only flag)


# === Public API ===

func generate_starter_draft() -> Array[TowerData]:
	var result: Array[TowerData] = []
	for i: int in GameConfig.STARTER_DRAFT_SIZE:
		var type: StringName = _random_from(GameConfig.BASE_TOWER_TYPES)
		result.append(_make_tower_data(type))
	_pending_draft.append_array(result)
	if not _pending_draft.is_empty():
		pending_draft_non_empty.emit()
	return result


func generate_draft(pool: Array[StringName]) -> Array[TowerData]:
	var result: Array[TowerData] = []
	for i: int in GameConfig.TOWER_DRAFT_SIZE:
		var type: StringName = _random_from(pool)
		var data: TowerData = _make_tower_data(type)
		# Synthesis types that appear directly in the draft pool are Keep-only
		if not GameConfig.BASE_TOWER_TYPES.has(type):
			_synthesis_pending[data] = true
		result.append(data)
	_pending_draft.append_array(result)
	if not _pending_draft.is_empty():
		pending_draft_non_empty.emit()
	return result


func place_from_draft(tower_data: TowerData, tile: Vector2i) -> void:
	if not _pending_draft.has(tower_data):
		push_warning("DraftManager: place_from_draft called with data not in pending draft")
		return
	var is_synthesis: bool = _synthesis_pending.get(tower_data, false)
	_pending_draft.erase(tower_data)
	_synthesis_pending.erase(tower_data)

	var node: Node = TowerManager.place_tower(tower_data, tile)
	_placed_nodes.append(node)
	_placed_data[node] = tower_data
	if is_synthesis:
		_placed_synthesis[node] = true
	tower_placed_from_draft.emit()


func reset() -> void:
	_pending_draft.clear()
	_synthesis_pending.clear()
	_clear_round_state()


func get_pending_draft() -> Array[TowerData]:
	return _pending_draft.duplicate()


func get_placed_tower_data(tower: Node) -> TowerData:
	return _placed_data.get(tower, null) as TowerData


func get_placed_this_round() -> Array[Node]:
	return _placed_nodes.duplicate()


func get_valid_combine_pairs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i: int in _placed_nodes.size():
		for j: int in range(i + 1, _placed_nodes.size()):
			var node_a: Node = _placed_nodes[i]
			var node_b: Node = _placed_nodes[j]
			# Synthesis-from-draft towers are Keep-only — exclude from combine
			if _placed_synthesis.get(node_a, false) or _placed_synthesis.get(node_b, false):
				continue
			var data_a: TowerData = _placed_data[node_a] as TowerData
			var data_b: TowerData = _placed_data[node_b] as TowerData
			var result_type: StringName = _combine_result(data_a.tower_type, data_b.tower_type)
			if result_type != &"":
				result.append({ "tower_a": node_a, "tower_b": node_b, "result_type": result_type })
	return result


func resolve_keep(chosen_tower: Node) -> void:
	if not _placed_nodes.has(chosen_tower):
		push_warning("DraftManager: resolve_keep — chosen tower not in placed list")
		return
	for node: Node in _placed_nodes:
		if node == chosen_tower:
			continue
		TowerManager.convert_to_barricade(node)
	_clear_round_state()
	draft_resolved.emit()


func resolve_combine(tower_a: Node, tower_b: Node) -> void:
	if not _placed_nodes.has(tower_a) or not _placed_nodes.has(tower_b):
		push_warning("DraftManager: resolve_combine — tower not in placed list")
		return
	var data_a: TowerData = _placed_data[tower_a] as TowerData
	var data_b: TowerData = _placed_data[tower_b] as TowerData
	var result_type: StringName = _combine_result(data_a.tower_type, data_b.tower_type)
	if result_type == &"":
		push_warning("DraftManager: resolve_combine — no valid synthesis for this pair")
		return
	var synthesis_data: TowerData = _make_synthesis_data(tower_a, tower_b, result_type)
	TowerManager.upgrade_tower(tower_a, synthesis_data)
	for node: Node in _placed_nodes:
		if node == tower_a:
			continue
		TowerManager.convert_to_barricade(node)
	_clear_round_state()
	draft_resolved.emit()


# === Private — Resolution ===

func _clear_round_state() -> void:
	_placed_nodes.clear()
	_placed_data.clear()
	_placed_synthesis.clear()


# === Private — Combine Logic ===

func _combine_result(type_a: StringName, type_b: StringName) -> StringName:
	var parts: Array[String] = [str(type_a), str(type_b)]
	parts.sort()
	var key: String = parts[0] + "|" + parts[1]
	return GameConfig.SYNTHESIS_COMBINE_TABLE.get(key, &"")


func _make_synthesis_data(tower_a: Node, tower_b: Node, result_type: StringName) -> TowerData:
	var data_a: TowerData = _placed_data[tower_a] as TowerData
	var data_b: TowerData = _placed_data[tower_b] as TowerData
	var d: TowerData = _make_tower_data(result_type)
	# Synthesis towers carry both source towers' infection effects
	for effect: InfectionEffect in data_a.infection_effects:
		d.infection_effects.append(effect)
	for effect: InfectionEffect in data_b.infection_effects:
		d.infection_effects.append(effect)
	return d


# === Private — Tower Data Factory ===
# Placeholder factory — creates TowerData with correct shape and type.
# Replace with preloaded .tres resources in data/towers/ when art/balance pass begins.

func _make_tower_data(type: StringName) -> TowerData:
	var d := TowerData.new()
	d.tower_type = type
	d.range_radius = GameConfig.TOWER_DEFAULT_RANGE
	d.fire_rate = GameConfig.TOWER_DEFAULT_FIRE_RATE
	match type:
		&"blight":       d.attack_shape = &"circle_aoe"
		&"plague":       d.attack_shape = &"single"
		&"pestilence":   d.attack_shape = &"single"
		&"miasma":       d.attack_shape = &"circle_aoe"
		&"festering":    d.attack_shape = &"single"
		&"wither":       d.attack_shape = &"targeted_aoe"
		&"epidemic":     d.attack_shape = &"cone"
		&"shroud":       d.attack_shape = &"circle_aoe"
		&"corpse_bloom": d.attack_shape = &"circle_aoe"
		&"virulence":
			d.attack_shape = &"chain"
			d.chain_count = 5
		&"septic":       d.attack_shape = &"single"
		&"fester_burst":
			d.attack_shape = &"line"
			d.default_targeting_mode = &"last"
		&"pandemic":     d.attack_shape = &"circle_aoe"
		&"plague_pit":   d.attack_shape = &"single"
		&"necrotic":     d.attack_shape = &"circle_aoe"
	# Default infection effect so towers actually deal damage until .tres assets exist
	var effect := InfectionEffect.new()
	effect.effect_type = &"plague"
	effect.base_damage = GameConfig.TOWER_DEFAULT_BASE_DAMAGE
	effect.tick_count = 5
	d.infection_effects.append(effect)
	return d


# === Private — Utilities ===

func _random_from(arr: Array[StringName]) -> StringName:
	return arr[randi() % arr.size()]
