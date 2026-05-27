extends Node
## Tech Tree point economy, stat node purchases, Discovery unlocks, stat propagation.
## Branches are built programmatically from GameConfig constants.
## Persists across villages; reset() on new campaign.


# === Signals ===

signal node_purchased(node: TechNode)
signal synthesis_tower_unlocked(tower_type: StringName)


# === Private Variables ===

var _points: int = 0
# StringName (branch) → Array (of TechNode)
var _branches: Dictionary = {}
# StringName (tower_type) → Dictionary (stat_name → float)
var _accumulated_stats: Dictionary = {}
var _unlocked_synthesis: Array[StringName] = []


# === Lifecycle ===

func _ready() -> void:
	_build_branches()


# === Public API ===

func get_points() -> int:
	return _points


func add_points(amount: int) -> void:
	_points += amount


func get_available_nodes(branch: StringName) -> Array[TechNode]:
	var result: Array[TechNode] = []
	if not _branches.has(branch):
		return result
	var nodes: Array = _branches[branch]
	for i: int in nodes.size():
		var node: TechNode = nodes[i] as TechNode
		if node.purchased:
			continue
		if i == 0 or (nodes[i - 1] as TechNode).purchased:
			result.append(node)
	return result


func purchase_node(node: TechNode, choice_index: int) -> void:
	if node.purchased:
		return
	if _points < node.cost:
		return
	var max_choices: int = node.stat_options.size() if node.node_type == &"stat" \
		else node.synthesis_options.size()
	if choice_index < 0 or choice_index >= max_choices:
		return
	_points -= node.cost
	node.purchased = true
	node.chosen_index = choice_index
	if node.node_type == &"stat":
		_apply_stat_purchase(node)
	else:
		_apply_discovery_purchase(node)
	node_purchased.emit(node)


func get_tower_stats(tower_type: StringName) -> Dictionary:
	return (_accumulated_stats.get(tower_type, {}) as Dictionary).duplicate()


func get_unlocked_synthesis_towers() -> Array[StringName]:
	return _unlocked_synthesis.duplicate()


func reset() -> void:
	_points = 0
	_unlocked_synthesis.clear()
	_accumulated_stats.clear()
	_build_branches()


# === Private — Purchase Handlers ===

func _apply_stat_purchase(node: TechNode) -> void:
	var stat: StringName = node.stat_options[node.chosen_index]
	var amount: float = node.stat_amounts[node.chosen_index]
	_accumulate_stat(node.branch, stat, amount)
	TowerManager.apply_stat_delta(node.branch, stat, amount)
	# chain_count from Plague or Pestilence propagates to all their chain-shape derivatives
	if stat == &"chain_count":
		for chain_type: StringName in _chain_towers_for_branch(node.branch):
			_accumulate_stat(chain_type, stat, amount)
			TowerManager.apply_stat_delta(chain_type, stat, amount)


func _apply_discovery_purchase(node: TechNode) -> void:
	var tower_type: StringName = node.synthesis_options[node.chosen_index]
	if _unlocked_synthesis.has(tower_type):
		return
	_unlocked_synthesis.append(tower_type)
	synthesis_tower_unlocked.emit(tower_type)


func _accumulate_stat(tower_type: StringName, stat: StringName, amount: float) -> void:
	if not _accumulated_stats.has(tower_type):
		_accumulated_stats[tower_type] = {}
	var stats: Dictionary = _accumulated_stats[tower_type] as Dictionary
	stats[stat] = stats.get(stat, 0.0) + amount


func _chain_towers_for_branch(branch: StringName) -> Array[StringName]:
	# Virulence = Plague + Pestilence — chain_count from either branch applies
	var result: Array[StringName] = []
	if branch == &"plague" or branch == &"pestilence":
		result.append(&"virulence")
	return result


# === Private — Branch Building ===

func _build_branches() -> void:
	_branches.clear()
	_build_plague_branch()
	_build_pestilence_branch()
	_build_blight_branch()
	_build_miasma_branch()
	_build_festering_branch()


func _build_plague_branch() -> void:
	var opts: Array[StringName] = [
		&"tick_damage", &"dot_duration", &"contact_range", &"stack_count", &"chain_count"
	]
	var amts: Array[float] = [
		GameConfig.TECH_STAT_DELTA,
		GameConfig.TECH_STAT_DELTA,
		GameConfig.TECH_STAT_DELTA,
		GameConfig.TECH_STAT_DELTA,
		float(GameConfig.TECH_CHAIN_COUNT_DELTA),
	]
	var disc: Array[StringName] = [&"wither", &"virulence", &"septic", &"fester_burst"]
	_branches[&"plague"] = [
		_make_stat_node(&"plague", 0, opts, amts),
		_make_stat_node(&"plague", 1, opts, amts),
		_make_discovery_node(&"plague", 2, disc),
		_make_stat_node(&"plague", 3, opts, amts),
		_make_stat_node(&"plague", 4, opts, amts),
		_make_discovery_node(&"plague", 5, disc),
	]


func _build_pestilence_branch() -> void:
	var opts: Array[StringName] = [
		&"spread_chance", &"spread_range", &"dot_damage", &"contagion_duration", &"chain_count"
	]
	var amts: Array[float] = [
		GameConfig.TECH_STAT_DELTA,
		GameConfig.TECH_STAT_DELTA,
		GameConfig.TECH_STAT_DELTA,
		GameConfig.TECH_STAT_DELTA,
		float(GameConfig.TECH_CHAIN_COUNT_DELTA),
	]
	var disc: Array[StringName] = [&"epidemic", &"virulence", &"pandemic", &"plague_pit"]
	_branches[&"pestilence"] = [
		_make_stat_node(&"pestilence", 0, opts, amts),
		_make_stat_node(&"pestilence", 1, opts, amts),
		_make_discovery_node(&"pestilence", 2, disc),
		_make_stat_node(&"pestilence", 3, opts, amts),
		_make_stat_node(&"pestilence", 4, opts, amts),
		_make_discovery_node(&"pestilence", 5, disc),
	]


func _build_blight_branch() -> void:
	var opts: Array[StringName] = [
		&"pulse_damage", &"aoe_radius", &"pulse_frequency", &"resistance_reduction"
	]
	var amts: Array[float] = [
		GameConfig.TECH_STAT_DELTA,
		GameConfig.TECH_STAT_DELTA,
		GameConfig.TECH_STAT_DELTA,
		GameConfig.TECH_STAT_DELTA,
	]
	var disc: Array[StringName] = [&"wither", &"epidemic", &"shroud", &"corpse_bloom"]
	_branches[&"blight"] = [
		_make_stat_node(&"blight", 0, opts, amts),
		_make_stat_node(&"blight", 1, opts, amts),
		_make_discovery_node(&"blight", 2, disc),
		_make_stat_node(&"blight", 3, opts, amts),
		_make_stat_node(&"blight", 4, opts, amts),
		_make_discovery_node(&"blight", 5, disc),
	]


func _build_miasma_branch() -> void:
	var opts: Array[StringName] = [
		&"slow_magnitude", &"resistance_reduction", &"aoe_radius", &"pulse_frequency"
	]
	var amts: Array[float] = [
		GameConfig.TECH_STAT_DELTA,
		GameConfig.TECH_STAT_DELTA,
		GameConfig.TECH_STAT_DELTA,
		GameConfig.TECH_STAT_DELTA,
	]
	var disc: Array[StringName] = [&"shroud", &"septic", &"pandemic", &"necrotic"]
	_branches[&"miasma"] = [
		_make_stat_node(&"miasma", 0, opts, amts),
		_make_stat_node(&"miasma", 1, opts, amts),
		_make_discovery_node(&"miasma", 2, disc),
		_make_stat_node(&"miasma", 3, opts, amts),
		_make_stat_node(&"miasma", 4, opts, amts),
		_make_discovery_node(&"miasma", 5, disc),
	]


func _build_festering_branch() -> void:
	var opts: Array[StringName] = [
		&"tile_damage", &"tile_duration", &"tile_spread", &"infection_chance"
	]
	var amts: Array[float] = [
		GameConfig.TECH_STAT_DELTA,
		GameConfig.TECH_STAT_DELTA,
		GameConfig.TECH_STAT_DELTA,
		GameConfig.TECH_STAT_DELTA,
	]
	var disc: Array[StringName] = [&"corpse_bloom", &"fester_burst", &"plague_pit", &"necrotic"]
	_branches[&"festering"] = [
		_make_stat_node(&"festering", 0, opts, amts),
		_make_stat_node(&"festering", 1, opts, amts),
		_make_discovery_node(&"festering", 2, disc),
		_make_stat_node(&"festering", 3, opts, amts),
		_make_stat_node(&"festering", 4, opts, amts),
		_make_discovery_node(&"festering", 5, disc),
	]


# === Private — Node Factories ===

func _make_stat_node(
	branch: StringName,
	pos: int,
	stat_options: Array[StringName],
	stat_amounts: Array[float]
) -> TechNode:
	var node := TechNode.new()
	node.branch = branch
	node.node_type = &"stat"
	node.position_in_branch = pos
	node.cost = GameConfig.TECH_NODE_COST
	node.stat_options = stat_options.duplicate()
	node.stat_amounts = stat_amounts.duplicate()
	return node


func _make_discovery_node(
	branch: StringName,
	pos: int,
	synthesis_options: Array[StringName]
) -> TechNode:
	var node := TechNode.new()
	node.branch = branch
	node.node_type = &"discovery"
	node.position_in_branch = pos
	node.cost = GameConfig.TECH_NODE_COST
	node.synthesis_options = synthesis_options.duplicate()
	return node
