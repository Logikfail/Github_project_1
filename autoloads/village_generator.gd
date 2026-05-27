extends Node
## Procedural village layout — houses, obstacles, exit tile.
## Returns a fully populated VillageData whose every house spawn has a valid path to exit.
## modifier_cards is left empty — filled by CampaignManager after generation.


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


# === Public API ===

func generate_village(village_index: int, seed: int) -> VillageData:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

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


# === Private — Obstacle Generation ===

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
