extends Node
## Owns all infection state per villager. Single source of truth for DoT logic.
## Every tower applies effects by calling into this module — no DoT logic lives elsewhere.


# === Signals ===

signal villager_died(villager: Node, cause: StringName)
signal rot_threshold_reached(villager: Node)


# === Private Variables ===

var _states: Dictionary = {}       # Node → InfectionState
var _tick_accumulator: float = 0.0


# === Lifecycle ===

func _physics_process(delta: float) -> void:
	tick_all(delta)


# === Public API ===

func register_villager(villager: Node, max_hp: float) -> void:
	var state := InfectionState.new()
	state.max_hp = max_hp
	_states[villager] = state


func unregister_villager(villager: Node) -> void:
	_states.erase(villager)


func apply_effect(villager: Node, effect: InfectionEffect) -> void:
	if not _states.has(villager):
		push_warning("InfectionManager: apply_effect on unregistered villager")
		return
	var state: InfectionState = _states[villager]

	if effect.rot_stacks > 0:
		if not state.rot_immune:
			state.rot_stacks += effect.rot_stacks
		return

	if effect.effect_type == &"plague":
		_apply_plague(state, effect)
	else:
		_apply_standard_dot(state, effect)


func tick_all(delta: float) -> void:
	_tick_accumulator += delta
	if _tick_accumulator < GameConfig.INFECTION_TICK_RATE:
		return
	_tick_accumulator -= GameConfig.INFECTION_TICK_RATE

	var newly_dead: Array[Node] = []
	var rot_exploded: Array[Node] = []

	for villager: Node in _states:
		if not is_instance_valid(villager):
			newly_dead.append(villager)
			continue
		_process_villager_tick(villager)
		var state: InfectionState = _states[villager]
		if state.current_damage >= state.max_hp:
			newly_dead.append(villager)
		elif state.rot_stacks >= GameConfig.ROT_THRESHOLD:
			rot_exploded.append(villager)

	for villager: Node in rot_exploded:
		rot_threshold_reached.emit(villager)

	for villager: Node in newly_dead:
		var cause: StringName = _get_death_cause(villager)
		villager_died.emit(villager, cause)
		_states.erase(villager)


func get_infection_pct(villager: Node) -> float:
	if not _states.has(villager):
		return 0.0
	var state: InfectionState = _states[villager]
	return clampf(state.current_damage / state.max_hp, 0.0, 1.0)


func get_rot_stacks(villager: Node) -> int:
	if not _states.has(villager):
		return 0
	return (_states[villager] as InfectionState).rot_stacks


func get_resistance(villager: Node, type: StringName) -> float:
	if not _states.has(villager):
		return 0.0
	var state: InfectionState = _states[villager]
	var base: float = state.base_resistances.get(type, 0.0)
	var aura: float = 0.0
	if not state.suppressed_aura_types.has(type):
		aura = state.aura_resistances.get(type, 0.0)
	var miasma: float = _get_total_miasma_reduction(state)
	return clampf(base + aura - miasma, 0.0, 1.0)


func apply_resistance_suppression(villager: Node, types: Array[StringName]) -> void:
	if not _states.has(villager):
		return
	var state: InfectionState = _states[villager]
	for t: StringName in types:
		if not state.suppressed_aura_types.has(t):
			state.suppressed_aura_types.append(t)


func remove_resistance_suppression(villager: Node) -> void:
	if not _states.has(villager):
		return
	(_states[villager] as InfectionState).suppressed_aura_types.clear()


func apply_rot_transfer(source: Node, targets: Array[Node], transfer_pct: float) -> void:
	if not _states.has(source):
		return
	var source_state: InfectionState = _states[source]
	var transfer_amount: int = int(float(source_state.rot_stacks) * transfer_pct)
	for target: Node in targets:
		if not _states.has(target):
			continue
		var target_state: InfectionState = _states[target]
		target_state.rot_stacks += transfer_amount
		target_state.is_rot_carrier = true
	source_state.rot_stacks = 0


func set_base_resistance(villager: Node, type: StringName, value: float) -> void:
	if not _states.has(villager):
		return
	(_states[villager] as InfectionState).base_resistances[type] = value


func apply_aura_resistance(villager: Node, type: StringName, value: float) -> void:
	if not _states.has(villager):
		return
	(_states[villager] as InfectionState).aura_resistances[type] = value


func clear_aura_resistance(villager: Node, type: StringName) -> void:
	if not _states.has(villager):
		return
	(_states[villager] as InfectionState).aura_resistances.erase(type)


func get_speed_multiplier(villager: Node) -> float:
	if not _states.has(villager):
		return 1.0
	var state: InfectionState = _states[villager]
	var total: float = 1.0
	for mod: float in state.speed_modifiers.values():
		total += mod
	return maxf(total, GameConfig.VILLAGER_SPEED_FLOOR)


func apply_speed_modifier(villager: Node, source_id: StringName, modifier: float) -> void:
	if not _states.has(villager):
		return
	(_states[villager] as InfectionState).speed_modifiers[source_id] = modifier


func remove_speed_modifier(villager: Node, source_id: StringName) -> void:
	if not _states.has(villager):
		return
	(_states[villager] as InfectionState).speed_modifiers.erase(source_id)


func reset_infection_damage(villager: Node) -> void:
	if not _states.has(villager):
		return
	(_states[villager] as InfectionState).current_damage = 0.0


func set_rot_immune(villager: Node, immune: bool) -> void:
	if not _states.has(villager):
		return
	(_states[villager] as InfectionState).rot_immune = immune


# === Private Methods ===

func _apply_plague(state: InfectionState, effect: InfectionEffect) -> void:
	for dot in state.active_dots:
		var d := dot as InfectionState.ActiveDot
		if d.effect_type == &"plague":
			d.stack_count += 1
			return
	_apply_standard_dot(state, effect)


func _apply_standard_dot(state: InfectionState, effect: InfectionEffect) -> void:
	var dot := InfectionState.ActiveDot.new()
	dot.effect_type = effect.effect_type
	dot.base_damage = effect.base_damage
	dot.escalation_rate = effect.escalation_rate
	dot.ticks_remaining = effect.tick_count if effect.tick_count > 0 else -1
	dot.spread_chance = effect.spread_chance
	dot.spread_range = effect.spread_range
	dot.slow_amount = effect.slow_amount
	dot.resistance_mod = effect.resistance_mod
	state.active_dots.append(dot)
	if effect.slow_amount > 0.0:
		state.speed_modifiers[effect.effect_type] = -effect.slow_amount


func _process_villager_tick(villager: Node) -> void:
	var state: InfectionState = _states[villager]
	var expired: Array = []

	for dot in state.active_dots:
		var d := dot as InfectionState.ActiveDot
		var resistance: float = get_resistance(villager, d.effect_type)
		var raw: float = (d.base_damage + d.escalation_rate * float(d.ticks_elapsed)) * float(d.stack_count)
		state.current_damage += raw * (1.0 - resistance)

		if d.effect_type == &"pestilence" and d.spread_chance > 0.0:
			_pestilence_spread_roll(villager, d)

		d.ticks_elapsed += 1

		if d.ticks_remaining > 0:
			d.ticks_remaining -= 1
			if d.ticks_remaining == 0:
				expired.append(d)

	for d in expired:
		var dot := d as InfectionState.ActiveDot
		if dot.slow_amount > 0.0:
			state.speed_modifiers.erase(dot.effect_type)
		state.active_dots.erase(d)

	if state.is_rot_carrier:
		_rot_carrier_tick(villager)


func _pestilence_spread_roll(source: Node, dot: InfectionState.ActiveDot) -> void:
	var pos: Vector2 = EntityManager.get_entity_position(source)
	var nearby: Array[Node] = EntityManager.get_entities_in_radius(pos, dot.spread_range, &"villager")
	for target: Node in nearby:
		if target == source or not _states.has(target):
			continue
		if randf() < dot.spread_chance:
			var spread := InfectionEffect.new()
			spread.effect_type = &"pestilence"
			spread.base_damage = dot.base_damage
			spread.tick_count = dot.ticks_remaining if dot.ticks_remaining > 0 else GameConfig.PESTILENCE_SPREAD_DEFAULT_TICKS
			spread.spread_chance = dot.spread_chance
			spread.spread_range = dot.spread_range
			apply_effect(target, spread)


func _rot_carrier_tick(carrier: Node) -> void:
	var pos: Vector2 = EntityManager.get_entity_position(carrier)
	var nearby: Array[Node] = EntityManager.get_entities_in_radius(
		pos, GameConfig.ROT_CARRIER_RANGE, &"villager"
	)
	for target: Node in nearby:
		if target == carrier or not _states.has(target):
			continue
		var target_state: InfectionState = _states[target] as InfectionState
		if not target_state.rot_immune and randf() < GameConfig.ROT_CARRIER_CHANCE:
			target_state.rot_stacks += GameConfig.ROT_CARRIER_STACKS_PER_TICK


func _get_total_miasma_reduction(state: InfectionState) -> float:
	var total: float = 0.0
	for dot in state.active_dots:
		var d := dot as InfectionState.ActiveDot
		if d.effect_type == &"miasma":
			total += d.resistance_mod
	return total


func _get_death_cause(villager: Node) -> StringName:
	if not _states.has(villager):
		return &"unknown"
	var state: InfectionState = _states[villager]
	if state.rot_stacks >= GameConfig.ROT_THRESHOLD:
		return &"rot"
	if not state.active_dots.is_empty():
		return (state.active_dots[0] as InfectionState.ActiveDot).effect_type
	return &"infection"
