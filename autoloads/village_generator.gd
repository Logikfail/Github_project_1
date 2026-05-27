extends Node
## Procedural village layout — houses, obstacles, exit tile.
## Returns a fully populated VillageData whose every house spawn has a valid path to exit.
## modifier_cards is left empty — filled by CampaignManager after generation.
##
## Two generation modes, toggled by GameConfig.USE_MODULAR_GENERATION:
##   • Legacy: random per-tile house placement + random obstacle scattering.
##   • Modular: pick a VillageSkeleton, place one Module per slot, then run filler obstacles.


# === Constants ===

const _HOUSE_TYPES: Array[StringName] = [
	&"hovel", &"chapel", &"garrison", &"apothecary", &"orphanage", &"almshouse", &"cemetery"
]

# Signature archetype for each house type (high-ratio archetype in its wave).
const _SIGNATURE_ARCHETYPE: Dictionary = {
	&"hovel":      &"standard",
	&"chapel":     &"priest",
	&"garrison":   &"guard",
	&"apothecary": &"doctor",
	&"orphanage":  &"child",
	&"almshouse":  &"elder",
	&"cemetery":   &"gravedigger",
}

# Placeholder tileset id per house type — replaced when art assets land.
const _TILESET_ID: Dictionary = {
	&"hovel": 0, &"chapel": 1, &"garrison": 2, &"apothecary": 3,
	&"orphanage": 4, &"almshouse": 5, &"cemetery": 6,
}


# === Private Variables ===

# Cached skeleton + module pool — built lazily on first modular generation.
var _skeleton: VillageSkeleton = null
var _module_pool: Array[Module] = []


# === Public API ===

func generate_village(village_index: int, seed: int) -> VillageData:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	if GameConfig.USE_MODULAR_GENERATION:
		return _generate_modular(rng, village_index)
	return _generate_legacy(rng, village_index)


# === Modular Generation ===

func _generate_modular(rng: RandomNumberGenerator, village_index: int) -> VillageData:
	if _skeleton == null:
		_skeleton = _build_test_skeleton()
		_module_pool = _build_module_pool()

	var data := VillageData.new()
	data.village_index = village_index
	data.exit_tiles = _skeleton.exit_tiles.duplicate()

	var occupied: Dictionary = {}        # Vector2i → true (any non-walkable tile)
	var house_spawns: Array[Vector2i] = []
	var module_obstacles: Array[Vector2i] = []

	for slot_idx: int in _skeleton.slots.size():
		var slot: SlotDef = _skeleton.slots[slot_idx]
		var module: Module = _pick_module_for_slot(rng, slot)
		if module == null:
			continue   # slot left empty — generator could not satisfy constraints

		var house_tile: Vector2i = slot.origin_tile + module.house_offset
		house_spawns.append(house_tile)

		for off: Vector2i in module.obstacle_offsets:
			var tile: Vector2i = slot.origin_tile + off
			module_obstacles.append(tile)
			occupied[tile] = true

		data.houses.append(_make_house_from_module(module, house_tile, slot_idx, village_index))

	# Filler obstacles fill the remaining walkable tiles, preserving the path invariant.
	var filler: Array[Vector2i] = _place_filler_obstacles(
		rng, module_obstacles, house_spawns, data.exit_tiles, occupied
	)
	var all_obstacles: Array[Vector2i] = []
	for t: Vector2i in module_obstacles:
		all_obstacles.append(t)
	for t: Vector2i in filler:
		all_obstacles.append(t)
	data.obstacle_tiles = all_obstacles

	return data


func _pick_module_for_slot(rng: RandomNumberGenerator, slot: SlotDef) -> Module:
	# Filter pool by category gate (empty allowed_categories = any category accepted)
	# and by footprint fit.
	var candidates: Array[Module] = []
	for m: Module in _module_pool:
		if not _module_fits_slot(m, slot):
			continue
		if slot.allowed_categories.size() > 0 and not slot.allowed_categories.has(m.category):
			continue
		candidates.append(m)
	if candidates.is_empty():
		return null
	for _attempt: int in GameConfig.MODULE_ASSIGNMENT_ATTEMPTS:
		var pick: Module = candidates[rng.randi() % candidates.size()]
		return pick
	return null


func _module_fits_slot(m: Module, slot: SlotDef) -> bool:
	return m.footprint.x <= slot.bounds.x and m.footprint.y <= slot.bounds.y


func _place_filler_obstacles(
	rng: RandomNumberGenerator,
	module_obstacles: Array[Vector2i],
	house_spawns: Array[Vector2i],
	exit_tiles: Array[Vector2i],
	occupied: Dictionary
) -> Array[Vector2i]:
	# Forbid module obstacle tiles, house spawn tiles, and exit tiles from filler placement.
	var forbidden: Dictionary = occupied.duplicate()
	for t: Vector2i in house_spawns:
		forbidden[t] = true
	for t: Vector2i in exit_tiles:
		forbidden[t] = true

	var w: int = _skeleton.grid_size.x
	var h: int = _skeleton.grid_size.y
	var open_tile_count: int = w * h - forbidden.size()
	var target_count: int = int(float(open_tile_count) * _skeleton.filler_density)
	target_count = mini(target_count, GameConfig.OBSTACLE_COUNT_BASE)

	var filler: Array[Vector2i] = []
	var attempts: int = 0
	while filler.size() < target_count and attempts < GameConfig.OBSTACLE_GEN_ATTEMPTS * 2:
		var tile := Vector2i(rng.randi() % w, rng.randi() % h)
		attempts += 1
		if forbidden.has(tile):
			continue
		var combined: Array[Vector2i] = []
		for t: Vector2i in module_obstacles:
			combined.append(t)
		for t: Vector2i in filler:
			combined.append(t)
		combined.append(tile)
		if _all_paths_valid(combined, house_spawns, exit_tiles):
			filler.append(tile)
			forbidden[tile] = true

	return filler


func _make_house_from_module(
	module: Module, spawn_tile: Vector2i, position_index: int, village_index: int
) -> HouseData:
	var house := HouseData.new()
	house.house_type = module.house_type
	house.spawn_tile = spawn_tile
	house.house_position = position_index
	house.tileset_id = _TILESET_ID.get(module.house_type, 0) as int
	house.wave_size = _compute_wave_size(village_index, position_index)
	if module.villager_archetypes.is_empty():
		house.villager_archetypes = _make_archetype_list(module.house_type, house.wave_size)
	else:
		house.villager_archetypes = _scale_archetype_mix(module.villager_archetypes, house.wave_size)
	return house


func _scale_archetype_mix(mix: Array[StringName], wave_size: int) -> Array[StringName]:
	# Repeat the declared mix until we hit wave_size, in order.
	var result: Array[StringName] = []
	for i: int in wave_size:
		result.append(mix[i % mix.size()])
	return result


# === Modular Test Data — Skeleton + Module Pool ===

func _build_test_skeleton() -> VillageSkeleton:
	var sk := VillageSkeleton.new()
	sk.biome = &"test_farmstead"
	sk.grid_size = Vector2i(GameConfig.GRID_WIDTH, GameConfig.GRID_HEIGHT)
	sk.filler_density = GameConfig.MODULAR_FILLER_DENSITY

	# Five 4x4 slots, two columns on the left half; right half is the exit corridor.
	# Layout (15x15 grid; '#' is slot, '.' walkable, 'E' exit):
	#   .###.###.....E.
	#   .###.###.......
	#   .###.###.......
	#   .###.###.......
	#   ...............
	#   .###.###.....E.
	#   .###.###.......
	#   .###.###.......
	#   .###.###.......
	#   ...............
	#   .###...........
	#   .###...........
	#   .###...........
	#   .###...........
	#   ...............
	var slots: Array[SlotDef] = []
	slots.append(_make_slot(&"top_left",    Vector2i(1, 0),  Vector2i(4, 4)))
	slots.append(_make_slot(&"top_mid",     Vector2i(5, 0),  Vector2i(4, 4)))
	slots.append(_make_slot(&"middle_left", Vector2i(1, 5),  Vector2i(4, 4)))
	slots.append(_make_slot(&"middle_mid",  Vector2i(5, 5),  Vector2i(4, 4)))
	slots.append(_make_slot(&"bottom_left", Vector2i(1, 10), Vector2i(4, 4)))
	sk.slots = slots

	var exits: Array[Vector2i] = []
	exits.append(Vector2i(GameConfig.GRID_WIDTH - 1, 2))
	exits.append(Vector2i(GameConfig.GRID_WIDTH - 1, 7))
	exits.append(Vector2i(GameConfig.GRID_WIDTH - 1, 12))
	sk.exit_tiles = exits
	return sk


func _make_slot(slot_name: StringName, origin: Vector2i, bounds: Vector2i) -> SlotDef:
	var s := SlotDef.new()
	s.slot_name = slot_name
	s.origin_tile = origin
	s.bounds = bounds
	s.allowed_categories = []   # any module accepted (loose gating for MVP)
	return s


func _build_module_pool() -> Array[Module]:
	var pool: Array[Module] = []
	pool.append(_make_farmstead_pen())
	pool.append(_make_market_stall_row())
	pool.append(_make_religious_compound())
	pool.append(_make_civic_well())
	return pool


# 4x4 footprint. House sits in centre; L-shaped fence on the north and west edges.
#   F F F .
#   F . . .
#   F . H .
#   . . . .
func _make_farmstead_pen() -> Module:
	var m := Module.new()
	m.module_name = &"farmstead_pen"
	m.category = &"farmstead"
	m.footprint = Vector2i(4, 4)
	m.house_offset = Vector2i(2, 2)
	m.house_type = &"cemetery"   # signature: gravedigger
	var obs: Array[Vector2i] = []
	obs.append(Vector2i(0, 0)); obs.append(Vector2i(1, 0)); obs.append(Vector2i(2, 0))
	obs.append(Vector2i(0, 1)); obs.append(Vector2i(0, 2))
	m.obstacle_offsets = obs
	var edges: Array[StringName] = [&"south", &"east"]
	m.open_edges = edges
	return m


# 4x4 footprint. Three stall obstacles form a row with aisles between them.
#   . S . S
#   . . . .
#   H S . S
#   . . . .
func _make_market_stall_row() -> Module:
	var m := Module.new()
	m.module_name = &"market_stall_row"
	m.category = &"market"
	m.footprint = Vector2i(4, 4)
	m.house_offset = Vector2i(0, 2)
	m.house_type = &"apothecary"  # signature: doctor
	var obs: Array[Vector2i] = []
	obs.append(Vector2i(1, 0)); obs.append(Vector2i(3, 0))
	obs.append(Vector2i(1, 2)); obs.append(Vector2i(3, 2))
	m.obstacle_offsets = obs
	var edges: Array[StringName] = [&"north", &"south", &"east"]
	m.open_edges = edges
	return m


# 4x4 footprint. Cloister-style: house centred, paired pillar clusters at opposite corners.
#   P P . .
#   P . . .
#   . . H .
#   . . . P
func _make_religious_compound() -> Module:
	var m := Module.new()
	m.module_name = &"religious_compound"
	m.category = &"religious"
	m.footprint = Vector2i(4, 4)
	m.house_offset = Vector2i(2, 2)
	m.house_type = &"chapel"      # signature: priest
	var obs: Array[Vector2i] = []
	obs.append(Vector2i(0, 0)); obs.append(Vector2i(1, 0)); obs.append(Vector2i(0, 1))
	obs.append(Vector2i(3, 3))
	m.obstacle_offsets = obs
	var edges: Array[StringName] = [&"south", &"east"]
	m.open_edges = edges
	return m


# 4x4 footprint. Civic well — single obstacle cluster at one corner, house opposite.
#   . . . H
#   . . . .
#   . W . .
#   . . . .
func _make_civic_well() -> Module:
	var m := Module.new()
	m.module_name = &"civic_well"
	m.category = &"civic"
	m.footprint = Vector2i(4, 4)
	m.house_offset = Vector2i(3, 0)
	m.house_type = &"almshouse"   # signature: elder
	var obs: Array[Vector2i] = []
	obs.append(Vector2i(1, 2))
	m.obstacle_offsets = obs
	var edges: Array[StringName] = [&"north", &"south", &"east", &"west"]
	m.open_edges = edges
	return m


# === Legacy Generation (preserved unchanged behind feature flag) ===

func _generate_legacy(rng: RandomNumberGenerator, village_index: int) -> VillageData:
	var data := VillageData.new()
	data.village_index = village_index

	var exit_result: Dictionary = _pick_exit_tiles(rng)
	data.exit_tiles = exit_result["tiles"]
	var exit_side: int = exit_result["side"]

	var house_types: Array[StringName] = _pick_house_types(rng, village_index)
	var spawn_tiles: Array[Vector2i] = _pick_spawn_tiles(rng, house_types.size(), data.exit_tiles, exit_side)

	for i: int in house_types.size():
		data.houses.append(_make_house(house_types[i], spawn_tiles[i], i, village_index))

	data.obstacle_tiles = _generate_obstacles(rng, spawn_tiles, data.exit_tiles)
	return data


func _pick_exit_tiles(rng: RandomNumberGenerator) -> Dictionary:
	# side: 0=right, 1=left, 2=bottom, 3=top
	var side: int = rng.randi() % 4
	var count: int = rng.randi_range(GameConfig.EXIT_COUNT_MIN, GameConfig.EXIT_COUNT_MAX)
	var is_vertical: bool = (side == 0 or side == 1)
	var max_pos: int = (GameConfig.GRID_HEIGHT if is_vertical else GameConfig.GRID_WIDTH) - 1

	var positions: Array[int] = []
	var attempts: int = 0
	while positions.size() < count and attempts < 50:
		var pos: int = rng.randi_range(2, max_pos - 2)
		var ok: bool = true
		for p: int in positions:
			if abs(pos - p) < GameConfig.EXIT_MIN_SEPARATION:
				ok = false
				break
		if ok:
			positions.append(pos)
		attempts += 1
	if positions.is_empty():
		positions.append(max_pos / 2)

	var exits: Array[Vector2i] = []
	for pos: int in positions:
		match side:
			0:  exits.append(Vector2i(GameConfig.GRID_WIDTH - 1, pos))   # right edge
			1:  exits.append(Vector2i(0, pos))                            # left edge
			2:  exits.append(Vector2i(pos, GameConfig.GRID_HEIGHT - 1))  # bottom edge
			3:  exits.append(Vector2i(pos, 0))                            # top edge
	return {"tiles": exits, "side": side}


# === Private — House Selection ===

func _pick_house_types(rng: RandomNumberGenerator, village_index: int) -> Array[StringName]:
	var result: Array[StringName] = []
	for _i: int in GameConfig.HOUSES_PER_VILLAGE:
		result.append(_HOUSE_TYPES[rng.randi() % _HOUSE_TYPES.size()])
	# Village 1 (index 0) must contain at least one Hovel
	if village_index == 0 and not result.has(&"hovel"):
		result[0] = &"hovel"
	return result


# === Private — House Placement ===

func _pick_spawn_tiles(
	rng: RandomNumberGenerator,
	count: int,
	exit_tiles: Array[Vector2i],
	exit_side: int
) -> Array[Vector2i]:
	var placed: Array[Vector2i] = []
	for _i: int in count:
		var tile: Vector2i = _find_spawn_tile(rng, exit_tiles, placed, exit_side)
		placed.append(tile)
	return placed


func _find_spawn_tile(
	rng: RandomNumberGenerator,
	exit_tiles: Array[Vector2i],
	placed: Array[Vector2i],
	exit_side: int
) -> Vector2i:
	var m: int = GameConfig.EXIT_MARGIN_TILES
	var w: int = GameConfig.GRID_WIDTH
	var h: int = GameConfig.GRID_HEIGHT
	for _attempt: int in GameConfig.HOUSE_PLACEMENT_ATTEMPTS:
		var tile: Vector2i
		match exit_side:
			0:  tile = Vector2i(rng.randi() % (w - m), rng.randi() % h)         # right exit — avoid right columns
			1:  tile = Vector2i(m + rng.randi() % (w - m), rng.randi() % h)     # left exit — avoid left columns
			2:  tile = Vector2i(rng.randi() % w, rng.randi() % (h - m))         # bottom exit — avoid bottom rows
			_:  tile = Vector2i(rng.randi() % w, m + rng.randi() % (h - m))     # top exit — avoid top rows
		if _spawn_tile_valid(tile, exit_tiles, placed):
			return tile
	# Fallback: center of the non-exit half
	match exit_side:
		0:  return Vector2i((w - m) / 2, h / 2)
		1:  return Vector2i(m + (w - m) / 2, h / 2)
		2:  return Vector2i(w / 2, (h - m) / 2)
		_:  return Vector2i(w / 2, m + (h - m) / 2)


func _spawn_tile_valid(
	tile: Vector2i,
	exit_tiles: Array[Vector2i],
	placed: Array[Vector2i]
) -> bool:
	if exit_tiles.has(tile):
		return false
	for other: Vector2i in placed:
		var dist: int = abs(tile.x - other.x) + abs(tile.y - other.y)
		if dist < GameConfig.HOUSE_MIN_SEPARATION:
			return false
	return true


# === Private — Wave Composition ===

func _make_house(
	house_type: StringName,
	spawn_tile: Vector2i,
	position_index: int,
	village_index: int
) -> HouseData:
	var house := HouseData.new()
	house.house_type = house_type
	house.spawn_tile = spawn_tile
	house.house_position = position_index
	house.tileset_id = _TILESET_ID.get(house_type, 0) as int
	house.wave_size = _compute_wave_size(village_index, position_index)
	house.villager_archetypes = _make_archetype_list(house_type, house.wave_size)
	return house


func _compute_wave_size(village_index: int, position_index: int) -> int:
	var village_mult: float = GameConfig.VILLAGE_COUNT_MULTIPLIERS[village_index]
	var pos_mult: float = GameConfig.HOUSE_POSITION_MULTIPLIERS[position_index]
	return roundi(GameConfig.VILLAGER_BASE_COUNT * village_mult * pos_mult)


func _make_archetype_list(house_type: StringName, wave_size: int) -> Array[StringName]:
	var result: Array[StringName] = []
	var signature: StringName = _SIGNATURE_ARCHETYPE.get(house_type, &"standard") as StringName
	var sig_count: int = roundi(wave_size * GameConfig.ARCHETYPE_SIGNATURE_RATIO)
	for _i: int in sig_count:
		result.append(signature)
	for _i: int in (wave_size - sig_count):
		result.append(&"standard")
	return result


# === Private — Obstacle Generation (legacy) ===

func _generate_obstacles(
	rng: RandomNumberGenerator,
	spawn_tiles: Array[Vector2i],
	exit_tiles: Array[Vector2i]
) -> Array[Vector2i]:
	var forbidden: Dictionary = {}
	for t: Vector2i in exit_tiles:
		forbidden[t] = true
	for t: Vector2i in spawn_tiles:
		forbidden[t] = true

	var obstacles: Array[Vector2i] = []
	var attempts: int = 0

	while obstacles.size() < GameConfig.OBSTACLE_COUNT_BASE \
			and attempts < GameConfig.OBSTACLE_GEN_ATTEMPTS:
		var tile := Vector2i(
			rng.randi() % GameConfig.GRID_WIDTH,
			rng.randi() % GameConfig.GRID_HEIGHT
		)
		attempts += 1
		if forbidden.has(tile):
			continue
		obstacles.append(tile)
		if not _all_paths_valid(obstacles, spawn_tiles, exit_tiles):
			obstacles.pop_back()
		else:
			forbidden[tile] = true

	return obstacles


func _all_paths_valid(
	obstacle_tiles: Array[Vector2i],
	spawn_tiles: Array[Vector2i],
	exit_tiles: Array[Vector2i]
) -> bool:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, GameConfig.GRID_WIDTH, GameConfig.GRID_HEIGHT)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for tile: Vector2i in obstacle_tiles:
		grid.set_point_solid(tile, true)
	for spawn: Vector2i in spawn_tiles:
		var has_path: bool = false
		for exit: Vector2i in exit_tiles:
			if not grid.get_id_path(spawn, exit).is_empty():
				has_path = true
				break
		if not has_path:
			return false
	return true
