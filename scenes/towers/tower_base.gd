class_name TowerBase
extends StaticBody3D
## Thin tower/barricade entity. Visual state managed here; game logic lives in TowerManager.


# === Constants ===

const _CLICK_COOLDOWN: float = 0.3


# === Private Variables ===

var _click_enabled: bool = false


# === Onready ===

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _range_ring: MeshInstance3D = $RangeRing


# === Lifecycle ===

func _ready() -> void:
	_start_click_cooldown()


func _input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int) -> void:
	if not _click_enabled:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			TowerManager.notify_tower_clicked(self)


# === Public Methods ===

func setup(_params: Dictionary) -> void:
	pass


func reset() -> void:
	_mesh.set_surface_override_material(0, null)
	_range_ring.visible = false
	_start_click_cooldown()


func setup_visuals(range_radius: float) -> void:
	_range_ring.scale = Vector3(range_radius, 1.0, range_radius)
	_range_ring.visible = false  # only visible when selected via TowerInspector


func show_range_ring() -> void:
	_range_ring.visible = true


func hide_range_ring() -> void:
	_range_ring.visible = false


func _start_click_cooldown() -> void:
	_click_enabled = false
	get_tree().create_timer(_CLICK_COOLDOWN).timeout.connect(func() -> void: _click_enabled = true)


func set_barricade_visual() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.45, 0.5)
	_mesh.set_surface_override_material(0, mat)
	_range_ring.visible = false
