class_name House
extends Node3D
## Represents a single house node in the world.
## Holds the archetype list WaveManager reads on wave start.
## Emits house_selected when the player clicks this house.


# === Signals ===

signal house_selected(house: House)


# === Exports ===

@export var house_type: StringName = &"hovel"
@export var spawn_tile: Vector2i = Vector2i.ZERO
@export var house_position: int = 0
@export var villager_archetypes: Array[StringName] = []


# === Public Variables ===

var cleared: bool = false


# === Onready ===

@onready var _label: Label3D = %HouseLabel
@onready var _area: Area3D = %ClickArea
@onready var _mesh: MeshInstance3D = $MeshInstance3D


# === Lifecycle ===

func _ready() -> void:
	_area.input_event.connect(_on_input_event)
	_refresh_label()


# === Public Methods ===

func mark_cleared() -> void:
	cleared = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.4, 0.4)
	_mesh.set_surface_override_material(0, mat)
	_refresh_label()


# === Private Methods ===

func _refresh_label() -> void:
	if not is_instance_valid(_label):
		return
	var status: String = " [CLEARED]" if cleared else ""
	_label.text = "%s%s\n%d villagers" % [house_type, status, villager_archetypes.size()]


func _on_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not cleared:
			house_selected.emit(self)
