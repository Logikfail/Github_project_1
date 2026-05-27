class_name WorldRoot
extends Node3D
## Game scene coordinator — bridges CampaignManager, VillageGenerator output,
## DraftManager, and WaveManager into a playable session.
## Instantiates house nodes from VillageData, manages tile-click tower placement,
## and wires DraftUI.rouse_confirmed → WaveManager.start_wave.


# === Constants ===

const _CAMERA_HEIGHT: float = 1800.0
const _CAMERA_DEPTH: float = -1100.0
const _CAMERA_SIZE: float = 2200.0

const _PROJ_RADIUS: float = 6.0
const _PROJ_HEIGHT: float = 12.0
const _PROJ_Y: float = 40.0
const _PROJ_TWEEN_DURATION: float = 0.12
const _PROJ_CHAIN_DELAY: float = 0.1
const _PROJ_AOE_TWEEN_DURATION: float = 0.35


# === Private Variables ===

var _house_scene: PackedScene = preload("res://scenes/world/house.tscn")
var _obstacle_scene: PackedScene = preload("res://scenes/world/obstacle.tscn")

var _house_nodes: Array[House] = []
var _obstacle_nodes: Array[Node3D] = []
var _exit_markers: Array[Node3D] = []
var _selected_house: House = null
var _placing_tower_data: TowerData = null
var _zone_meshes: Dictionary = {}  # zone_id: int → MeshInstance3D


# === Onready ===

@onready var _camera: Camera3D = %MainCamera
@onready var _world_container: Node3D = %WorldContainer
@onready var _draft_ui: DraftUI = %DraftUI
@onready var _tower_inspector: TowerInspector = %TowerInspector
@onready var _hud: HUD = %HUD
@onready var _pause_menu: PauseMenu = %PauseMenu


# === Lifecycle ===

func _ready() -> void:
	CampaignManager.village_started.connect(_on_village_started)
	CampaignManager.village_complete.connect(_on_village_complete)
	CampaignManager.campaign_won.connect(_on_campaign_won)
	CampaignManager.campaign_failed.connect(_on_campaign_failed)
	WaveManager.wave_complete.connect(_on_wave_complete)
	TowerManager.tower_inspected.connect(_on_tower_inspected)
	TowerManager.tower_fired.connect(_on_tower_fired)
	TowerManager.tower_aoe_burst.connect(_on_tower_aoe_burst)
	TowerManager.tower_chain_fired.connect(_on_tower_chain_fired)
	TowerManager.tower_line_fired.connect(_on_tower_line_fired)
	TowerManager.ground_patch_spawned.connect(_on_ground_patch_spawned)
	TowerManager.ground_patch_expired.connect(_on_ground_patch_expired)
	TowerManager.call_of_void_spawned.connect(_on_call_of_void_spawned)
	TowerManager.call_of_void_depleted.connect(_on_call_of_void_depleted)
	_draft_ui.rouse_confirmed.connect(_on_rouse_confirmed)
	_draft_ui.request_next_tower_placement.connect(_on_place_next_tower_requested)
	_hud.menu_button_pressed.connect(_pause_menu.show_menu)
	_setup_camera()
	CampaignManager.enter_village(CampaignManager.get_villages_completed())


func _setup_camera() -> void:
	# Hex grid is centered at world (0,0). Camera sits above and behind, looks at origin.
	var world_center := Vector3(0.0, 0.0, 0.0)
	_camera.global_position = Vector3(0.0, _CAMERA_HEIGHT, _CAMERA_DEPTH)
	_camera.look_at(world_center, Vector3.UP)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = _CAMERA_SIZE


func _unhandled_input(event: InputEvent) -> void:
	if _placing_tower_data == null:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_try_place_at_mouse(mb.position)


# === Public Methods ===

func select_pending_tower(tower_data: TowerData) -> void:
	_placing_tower_data = tower_data
	_set_status("Click a tile to place: %s" % tower_data.tower_type)


func _on_place_next_tower_requested() -> void:
	var pending: Array[TowerData] = DraftManager.get_pending_draft()
	if pending.is_empty():
		return
	select_pending_tower(pending[0])


# === Private — Village Setup ===

func _on_village_started(village_data: VillageData) -> void:
	_clear_world()
	_spawn_houses(village_data)
	_place_obstacles(village_data)
	_spawn_exit_markers()
	var village_num: int = village_data.village_index + 1
	_set_status("Village %d — click a house to begin placement." % village_num)


func _spawn_houses(village_data: VillageData) -> void:
	for house_data: HouseData in village_data.houses:
		var house: House = _house_scene.instantiate() as House
		_world_container.add_child(house)

		house.house_type = house_data.house_type
		house.spawn_tile = house_data.spawn_tile
		house.house_position = house_data.house_position
		house.villager_archetypes = house_data.villager_archetypes

		var world_pos: Vector2 = NavigationManager.tile_to_world(house_data.spawn_tile)
		house.global_position = Vector3(world_pos.x, 0.0, world_pos.y)
		house.house_selected.connect(_on_house_selected)
		_house_nodes.append(house)
		NavigationManager.place_obstacle(house_data.spawn_tile)


func _place_obstacles(village_data: VillageData) -> void:
	for tile: Vector2i in village_data.obstacle_tiles:
		NavigationManager.place_obstacle(tile)
		if _obstacle_scene != null:
			var obs: Node3D = _obstacle_scene.instantiate() as Node3D
			_world_container.add_child(obs)
			var world_pos: Vector2 = NavigationManager.tile_to_world(tile)
			obs.global_position = Vector3(world_pos.x, 0.0, world_pos.y)
			_obstacle_nodes.append(obs)


func _spawn_exit_markers() -> void:
	var exit_positions: Array[Vector2] = NavigationManager.get_exit_positions()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.9, 0.1)
	for pos: Vector2 in exit_positions:
		var marker := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 20.0
		mesh.bottom_radius = 20.0
		mesh.height = 60.0
		marker.mesh = mesh
		marker.set_surface_override_material(0, mat)
		_world_container.add_child(marker)
		marker.global_position = Vector3(pos.x, 30.0, pos.y)
		_exit_markers.append(marker)


func _clear_world() -> void:
	for house: House in _house_nodes:
		if is_instance_valid(house):
			house.queue_free()
	_house_nodes.clear()
	for obs: Node3D in _obstacle_nodes:
		if is_instance_valid(obs):
			obs.queue_free()
	_obstacle_nodes.clear()
	for marker: Node3D in _exit_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	_exit_markers.clear()
	for mesh: MeshInstance3D in _zone_meshes.values():
		if is_instance_valid(mesh):
			mesh.queue_free()
	_zone_meshes.clear()
	_selected_house = null
	_placing_tower_data = null


# === Private — House Selection ===

func _on_house_selected(house: House) -> void:
	if WaveManager.is_wave_active():
		_set_status("A wave is already in progress.")
		return
	_selected_house = house
	_set_status("House selected: %s — place towers then click Rouse." % house.house_type)


# === Private — Tower Placement ===

func _try_place_at_mouse(mouse_pos: Vector2) -> void:
	var world_pos: Vector2 = _ray_to_ground(mouse_pos)
	var tile: Vector2i = NavigationManager.get_tile_at(world_pos)

	if NavigationManager.is_tile_occupied(tile):
		_set_status("Tile occupied — pick another.")
		return

	DraftManager.place_from_draft(_placing_tower_data, tile)
	_placing_tower_data = null
	var pending: Array[TowerData] = DraftManager.get_pending_draft()
	if not pending.is_empty():
		select_pending_tower(pending[0])
		_set_status("Tower placed — click to place next (%d remaining)." % pending.size())
	else:
		_set_status("All towers placed. Select a tower to keep or combine, then Rouse.")


func _ray_to_ground(screen_pos: Vector2) -> Vector2:
	var ray_from: Vector3 = _camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = _camera.project_ray_normal(screen_pos)
	if abs(ray_dir.y) < 0.001:
		return Vector2.ZERO
	var t: float = -ray_from.y / ray_dir.y
	var hit: Vector3 = ray_from + ray_dir * t
	return Vector2(hit.x, hit.z)


# === Private — Wave Lifecycle ===

func _on_rouse_confirmed() -> void:
	if not is_instance_valid(_selected_house):
		_set_status("No house selected.")
		return
	if WaveManager.is_wave_active():
		_set_status("Wave already in progress.")
		return
	_set_status("Wave started!")
	var cleared: int = CampaignManager.get_houses_cleared_this_village()
	var wave_scale: float = 1.0 + cleared * GameConfig.WAVE_SCALE_PER_HOUSE
	WaveManager.start_wave(_selected_house, wave_scale)


func _on_wave_complete(
	house: Node,
	_all_infected: bool,
	escaped_count: int,
	_infected_count: int
) -> void:
	var h: House = house as House
	if is_instance_valid(h):
		h.mark_cleared()
	_selected_house = null
	_set_status("House cleared! %d escaped. Click next house or wait." % escaped_count)


func _on_village_complete(_village_index: int) -> void:
	get_tree().change_scene_to_file("res://scenes/ui/tech_tree_screen.tscn")


func _on_campaign_won() -> void:
	pass  # tech_tree_screen checks CampaignManager.is_active() and routes to main menu


func _on_campaign_failed(_reason: StringName) -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


# === Private — Tower Inspector ===

func _on_tower_inspected(tower: Node) -> void:
	_tower_inspector.inspect(tower)


# === Private — Projectiles ===

func _on_tower_aoe_burst(center_pos: Vector2, radius: float) -> void:
	var burst := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 2.0
	burst.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.9, 0.2, 0.35)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	burst.set_surface_override_material(0, mat)
	_world_container.add_child(burst)
	burst.global_position = Vector3(center_pos.x, 2.0, center_pos.y)
	var tween := create_tween()
	tween.tween_property(burst, "scale", Vector3(radius, 1.0, radius), _PROJ_AOE_TWEEN_DURATION)
	tween.tween_callback(burst.queue_free)


func _on_ground_patch_spawned(patch_id: int, world_pos: Vector2, radius: float) -> void:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 4.0
	disc.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.7, 0.1, 0.55)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc.set_surface_override_material(0, mat)
	_world_container.add_child(disc)
	disc.global_position = Vector3(world_pos.x, 2.0, world_pos.y)
	_zone_meshes[patch_id] = disc


func _on_ground_patch_expired(patch_id: int) -> void:
	if _zone_meshes.has(patch_id):
		var mesh: MeshInstance3D = _zone_meshes[patch_id] as MeshInstance3D
		if is_instance_valid(mesh):
			mesh.queue_free()
		_zone_meshes.erase(patch_id)


func _on_call_of_void_spawned(void_id: int, world_pos: Vector2) -> void:
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 30.0
	mesh.height = 60.0
	sphere.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.0, 0.25, 0.85)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.set_surface_override_material(0, mat)
	_world_container.add_child(sphere)
	sphere.global_position = Vector3(world_pos.x, 30.0, world_pos.y)
	_zone_meshes[void_id] = sphere


func _on_call_of_void_depleted(void_id: int) -> void:
	if _zone_meshes.has(void_id):
		var mesh: MeshInstance3D = _zone_meshes[void_id] as MeshInstance3D
		if is_instance_valid(mesh):
			mesh.queue_free()
		_zone_meshes.erase(void_id)


func _on_tower_line_fired(from_pos: Vector2, line_end: Vector2) -> void:
	var dir: Vector2 = line_end - from_pos
	var length: float = dir.length()
	if length < 0.001:
		return
	var mid: Vector2 = (from_pos + line_end) * 0.5
	var beam := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(length, 6.0, 6.0)
	beam.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 1.0, 0.5, 0.85)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam.set_surface_override_material(0, mat)
	_world_container.add_child(beam)
	beam.global_position = Vector3(mid.x, 5.0, mid.y)
	beam.rotation.y = atan2(-dir.y, dir.x)
	var tween := create_tween()
	tween.tween_property(mat, "albedo_color", Color(0.5, 1.0, 0.5, 0.0), _PROJ_AOE_TWEEN_DURATION)
	tween.tween_callback(beam.queue_free)


func _on_tower_chain_fired(positions: Array[Vector2]) -> void:
	if positions.size() < 2:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.9, 0.15)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i: int in positions.size() - 1:
		var from: Vector2 = positions[i]
		var to: Vector2 = positions[i + 1]
		var delay: float = i * _PROJ_CHAIN_DELAY
		var proj := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = _PROJ_RADIUS
		sphere.height = _PROJ_HEIGHT
		proj.mesh = sphere
		proj.set_surface_override_material(0, mat)
		_world_container.add_child(proj)
		proj.global_position = Vector3(from.x, _PROJ_Y, from.y)
		proj.visible = false
		var tween := create_tween()
		tween.tween_interval(delay)
		tween.tween_callback(func() -> void: proj.visible = true)
		tween.tween_property(proj, "global_position",
			Vector3(to.x, _PROJ_Y, to.y), _PROJ_TWEEN_DURATION)
		tween.tween_callback(proj.queue_free)


func _on_tower_fired(from_pos: Vector2, to_pos: Vector2) -> void:
	var proj := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = _PROJ_RADIUS
	sphere.height = _PROJ_HEIGHT
	proj.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.9, 0.15)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	proj.set_surface_override_material(0, mat)
	_world_container.add_child(proj)
	proj.global_position = Vector3(from_pos.x, _PROJ_Y, from_pos.y)
	var tween := create_tween()
	tween.tween_property(proj, "global_position",
		Vector3(to_pos.x, _PROJ_Y, to_pos.y), _PROJ_TWEEN_DURATION)
	tween.tween_callback(proj.queue_free)


# === Private — Helpers ===

func _set_status(text: String) -> void:
	if is_instance_valid(_hud):
		_hud.set_status(text)
