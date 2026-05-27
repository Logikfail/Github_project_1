extends Node
## Owns the tile grid and all pathfinding. Only module that touches AStar2D.
## Uses a pointy-top hex grid with oddr offset coordinates.
## Every path request and obstacle change goes through this module.


# === Signals ===

signal path_blocked(tile: Vector2i)
signal path_restored(tile: Vector2i)


# === Private Variables ===

var _astar: AStar2D           # with obstacles
var _astar_open: AStar2D      # no obstacles — used by Child archetype only

var _occupied_tiles: Dictionary = {}    # Vector2i → true  (permanent: towers, barricades)
var _phantom_tiles: Dictionary = {}     # Vector2i → int   (Shroud ref-count)

var _exit_tiles: Array[Vector2i] = []
var _grid_offset: Vector2 = Vector2.ZERO


# === Lifecycle ===

func _ready() -> void:
	_grid_offset = _compute_grid_offset()
	_astar = _make_hex_grid()
	_astar_open = _make_hex_grid()


# === Public API ===

func setup(exit_tiles: Array[Vector2i]) -> void:
	_exit_tiles = exit_tiles.duplicate()
	# Clear occupied/phantom state between villages
	for tile: Vector2i in _occupied_tiles.keys():
		_astar.set_point_disabled(_tile_to_id(tile), false)
	_occupied_tiles.clear()
	_phantom_tiles.clear()


func request_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	return _astar.get_point_path(_tile_to_id(get_tile_at(from)), _tile_to_id(get_tile_at(to)))


func request_path_ignore_obstacles(from: Vector2, to: Vector2) -> PackedVector2Array:
	return _astar_open.get_point_path(_tile_to_id(get_tile_at(from)), _tile_to_id(get_tile_at(to)))


func place_obstacle(tile: Vector2i) -> void:
	if _occupied_tiles.has(tile):
		return
	_occupied_tiles[tile] = true
	_astar.set_point_disabled(_tile_to_id(tile), true)
	path_blocked.emit(tile)


func remove_obstacle(tile: Vector2i) -> void:
	if not _occupied_tiles.has(tile):
		return
	_occupied_tiles.erase(tile)
	if not _phantom_tiles.has(tile):
		_astar.set_point_disabled(_tile_to_id(tile), false)
		path_restored.emit(tile)


func place_phantom_obstacle(tile: Vector2i, duration: float) -> void:
	var count: int = _phantom_tiles.get(tile, 0)
	_phantom_tiles[tile] = count + 1
	if count == 0 and not _occupied_tiles.has(tile):
		_astar.set_point_disabled(_tile_to_id(tile), true)
		path_blocked.emit(tile)
	var timer := get_tree().create_timer(duration)
	timer.timeout.connect(_expire_phantom.bind(tile), CONNECT_ONE_SHOT)


func path_exists(from: Vector2, to: Vector2) -> bool:
	var from_id := _tile_to_id(get_tile_at(from))
	var to_id := _tile_to_id(get_tile_at(to))
	return not _astar.get_id_path(from_id, to_id).is_empty()


func get_exit_positions() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for tile: Vector2i in _exit_tiles:
		result.append(_tile_to_world(tile))
	return result


func get_closest_exit_position(from: Vector2) -> Vector2:
	if _exit_tiles.is_empty():
		return Vector2.ZERO
	var best: Vector2 = _tile_to_world(_exit_tiles[0])
	var best_dist: float = from.distance_squared_to(best)
	for i: int in range(1, _exit_tiles.size()):
		var pos: Vector2 = _tile_to_world(_exit_tiles[i])
		var d: float = from.distance_squared_to(pos)
		if d < best_dist:
			best_dist = d
			best = pos
	return best


func path_exists_to_any_exit(from: Vector2) -> bool:
	var from_id: int = _tile_to_id(get_tile_at(from))
	for exit_tile: Vector2i in _exit_tiles:
		if not _astar.get_id_path(from_id, _tile_to_id(exit_tile)).is_empty():
			return true
	return false


func get_tile_at(world_pos: Vector2) -> Vector2i:
	# Subtract grid offset, then convert to fractional axial, then cube-round, then to oddr offset.
	var adj: Vector2 = world_pos - _grid_offset
	var size: float = GameConfig.HEX_SIZE
	var q_frac: float = (sqrt(3.0) / 3.0 * adj.x - 1.0 / 3.0 * adj.y) / size
	var r_frac: float = (2.0 / 3.0 * adj.y) / size
	var s_frac: float = -q_frac - r_frac

	var rq: float = round(q_frac)
	var rr: float = round(r_frac)
	var rs: float = round(s_frac)

	var dq: float = abs(rq - q_frac)
	var dr: float = abs(rr - r_frac)
	var ds: float = abs(rs - s_frac)

	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs

	# Axial to oddr offset
	var col: int = int(rq) + (int(rr) - (int(rr) & 1)) / 2
	var row: int = int(rr)
	return Vector2i(
		clampi(col, 0, GameConfig.GRID_WIDTH - 1),
		clampi(row, 0, GameConfig.GRID_HEIGHT - 1)
	)


func is_tile_occupied(tile: Vector2i) -> bool:
	return _occupied_tiles.has(tile) or _phantom_tiles.has(tile)


func get_walkable_neighbors(tile: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for neighbor: Vector2i in _hex_neighbors(tile):
		if _in_bounds(neighbor) and not is_tile_occupied(neighbor):
			result.append(neighbor)
	return result


func tile_to_world(tile: Vector2i) -> Vector2:
	return _tile_to_world(tile)


# === Private Methods ===

func _compute_grid_offset() -> Vector2:
	# Center the grid at world (0, 0).
	var max_x: float = GameConfig.HEX_SIZE * sqrt(3.0) * (GameConfig.GRID_WIDTH - 1)
	var max_z: float = GameConfig.HEX_SIZE * 1.5 * (GameConfig.GRID_HEIGHT - 1)
	return Vector2(-max_x / 2.0, -max_z / 2.0)


func _tile_to_world(tile: Vector2i) -> Vector2:
	# Pointy-top hex, oddr offset (odd rows shifted right by half a hex width).
	var q := tile.x
	var r := tile.y
	var x: float = GameConfig.HEX_SIZE * sqrt(3.0) * (q + 0.5 * (r % 2))
	var z: float = GameConfig.HEX_SIZE * 1.5 * r
	return Vector2(x, z) + _grid_offset


func _tile_to_id(tile: Vector2i) -> int:
	return tile.y * GameConfig.GRID_WIDTH + tile.x


func _make_hex_grid() -> AStar2D:
	var astar := AStar2D.new()

	for r: int in GameConfig.GRID_HEIGHT:
		for q: int in GameConfig.GRID_WIDTH:
			var tile := Vector2i(q, r)
			astar.add_point(_tile_to_id(tile), _tile_to_world(tile))

	for r: int in GameConfig.GRID_HEIGHT:
		for q: int in GameConfig.GRID_WIDTH:
			var tile := Vector2i(q, r)
			var id: int = _tile_to_id(tile)
			for neighbor: Vector2i in _hex_neighbors(tile):
				if _in_bounds(neighbor):
					var nid: int = _tile_to_id(neighbor)
					if not astar.are_points_connected(id, nid):
						astar.connect_points(id, nid)

	return astar


func _hex_neighbors(tile: Vector2i) -> Array[Vector2i]:
	var q := tile.x
	var r := tile.y
	var neighbors: Array[Vector2i] = []
	if r % 2 == 0:
		neighbors = [
			Vector2i(q + 1, r),     Vector2i(q - 1, r),
			Vector2i(q,     r - 1), Vector2i(q - 1, r - 1),
			Vector2i(q,     r + 1), Vector2i(q - 1, r + 1),
		]
	else:
		neighbors = [
			Vector2i(q + 1, r),     Vector2i(q - 1, r),
			Vector2i(q + 1, r - 1), Vector2i(q,     r - 1),
			Vector2i(q + 1, r + 1), Vector2i(q,     r + 1),
		]
	return neighbors


func _in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < GameConfig.GRID_WIDTH \
		and tile.y >= 0 and tile.y < GameConfig.GRID_HEIGHT


func _expire_phantom(tile: Vector2i) -> void:
	if not _phantom_tiles.has(tile):
		return
	var count: int = _phantom_tiles[tile] - 1
	if count > 0:
		_phantom_tiles[tile] = count
		return
	_phantom_tiles.erase(tile)
	if not _occupied_tiles.has(tile):
		_astar.set_point_disabled(_tile_to_id(tile), false)
		path_restored.emit(tile)
