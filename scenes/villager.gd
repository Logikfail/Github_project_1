class_name Villager
extends CharacterBody3D
## Thin villager entity. All state and behaviour lives in VillagerManager.
## Polls InfectionManager each frame to update mesh color (green → red as damage accumulates).


# === Onready ===

@onready var _mesh: MeshInstance3D = $MeshInstance3D


# === Private Variables ===

var _mat: StandardMaterial3D = null

static var _healthy_color: Color = Color(0.2, 0.8, 0.2)
static var _infected_color: Color = Color(0.9, 0.2, 0.2)


# === Lifecycle ===

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = _healthy_color
	_mesh.set_surface_override_material(0, _mat)


func _process(_delta: float) -> void:
	if _mat == null:
		return
	var pct: float = InfectionManager.get_infection_pct(self)
	_mat.albedo_color = _healthy_color.lerp(_infected_color, pct)


# === Public Methods ===

func setup(_params: Dictionary) -> void:
	pass


func reset() -> void:
	if _mat != null:
		_mat.albedo_color = _healthy_color
