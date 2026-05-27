extends Node
## Central registry for all in-scene entities.
## Handles pooled spawn/despawn and spatial queries. Callers never instantiate scenes directly.


# === Signals ===

signal entity_spawned(entity: Node, type: StringName)
signal entity_despawned(entity: Node, type: StringName)


# === Private Variables ===

# StringName → PackedScene
var _scenes: Dictionary = {}
# StringName → Array (of Node) — available (inactive) pool instances
var _pool_available: Dictionary = {}
# StringName → Array (of Node) — active (in-scene) instances
var _pool_active: Dictionary = {}
# Node → StringName — reverse lookup for despawn
var _entity_types: Dictionary = {}


# === Public API ===

func register_type(type: StringName, scene: PackedScene, warm_count: int = 0) -> void:
	if _scenes.has(type):
		return
	_scenes[type] = scene
	_pool_available[type] = []
	_pool_active[type] = []
	for i: int in warm_count:
		(_pool_available[type] as Array).append(_create_instance(type))


func spawn_entity(type: StringName, position: Vector2, params: Dictionary = {}) -> Node:
	if not _scenes.has(type):
		push_error("EntityManager: unknown entity type '%s'" % type)
		return null

	var available: Array = _pool_available[type]
	var entity: Node
	if available.is_empty():
		entity = _create_instance(type)
	else:
		entity = available.pop_back()

	(_pool_active[type] as Array).append(entity)
	_entity_types[entity] = type

	_set_entity_position(entity, position)
	entity.process_mode = Node.PROCESS_MODE_INHERIT
	entity.show()

	if entity.has_method(&"reset"):
		entity.reset()
	if not params.is_empty() and entity.has_method(&"setup"):
		entity.setup(params)

	entity_spawned.emit(entity, type)
	return entity


func despawn_entity(entity: Node) -> void:
	if not is_instance_valid(entity):
		return
	if not _entity_types.has(entity):
		push_warning("EntityManager: despawn called on unregistered entity")
		return

	var type: StringName = _entity_types[entity]
	_entity_types.erase(entity)
	(_pool_active[type] as Array).erase(entity)

	entity.process_mode = Node.PROCESS_MODE_DISABLED
	entity.hide()
	(_pool_available[type] as Array).append(entity)

	entity_despawned.emit(entity, type)


func get_entities_in_radius(position: Vector2, radius: float, type_filter: StringName = &"") -> Array[Node]:
	var result: Array[Node] = []
	var radius_sq: float = radius * radius
	for type: StringName in _pool_active:
		if type_filter != &"" and type != type_filter:
			continue
		for entity: Node in (_pool_active[type] as Array):
			if not is_instance_valid(entity):
				continue
			var delta: Vector2 = get_entity_position(entity) - position
			if delta.length_squared() <= radius_sq:
				result.append(entity)
	return result


func get_all_entities(type_filter: StringName = &"") -> Array[Node]:
	var result: Array[Node] = []
	for type: StringName in _pool_active:
		if type_filter != &"" and type != type_filter:
			continue
		for entity: Node in (_pool_active[type] as Array):
			result.append(entity)
	return result


func despawn_all_of_type(type: StringName) -> void:
	if not _pool_active.has(type):
		return
	var active_copy: Array = (_pool_active[type] as Array).duplicate()
	for entity: Node in active_copy:
		despawn_entity(entity)


func get_entity_position(entity: Node) -> Vector2:
	if entity is Node3D:
		var p: Vector3 = (entity as Node3D).global_position
		return Vector2(p.x, p.z)
	if entity is Node2D:
		return (entity as Node2D).global_position
	return Vector2.ZERO


func get_entity_count(type_filter: StringName = &"") -> int:
	if type_filter != &"":
		if not _pool_active.has(type_filter):
			return 0
		return (_pool_active[type_filter] as Array).size()
	var total: int = 0
	for type: StringName in _pool_active:
		total += (_pool_active[type] as Array).size()
	return total


# === Private Methods ===

func _create_instance(type: StringName) -> Node:
	var entity: Node = (_scenes[type] as PackedScene).instantiate()
	entity.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(entity)
	entity.hide()
	return entity


func _set_entity_position(entity: Node, position: Vector2) -> void:
	if entity is Node3D:
		(entity as Node3D).global_position = Vector3(position.x, 0.0, position.y)
	elif entity is Node2D:
		(entity as Node2D).global_position = position


