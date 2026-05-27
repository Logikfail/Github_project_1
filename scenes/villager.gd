class_name Villager
extends CharacterBody3D
## Thin villager entity. All state and behaviour lives in VillagerManager.
## Polls InfectionManager each frame to update mesh color (green → red as damage accumulates).
## Renders a red outline mesh when set into Desperate mode by VillagerManager.


# === Onready ===

@onready var _mesh: MeshInstance3D = $MeshInstance3D


# === Private Variables ===

var _mat: StandardMaterial3D = null
var _outline_mesh: MeshInstance3D = null

static var _healthy_color: Color = Color(0.2, 0.8, 0.2)
static var _infected_color: Color = Color(0.9, 0.2, 0.2)


# === Lifecycle ===

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = _healthy_color
	_mesh.set_surface_override_material(0, _mat)
	_build_desperate_outline()


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
	if is_instance_valid(_outline_mesh):
		_outline_mesh.visible = false


## Toggle the red outline mesh — called by VillagerManager on Desperate enter/exit.
func set_desperate_visual(active: bool) -> void:
	if is_instance_valid(_outline_mesh):
		_outline_mesh.visible = active


# === Private Methods ===

func _build_desperate_outline() -> void:
	# Inverted-normals outline trick: scaled-up copy of the body mesh, rendered
	# only from the inside-facing polys, so it shows as a halo behind the villager.
	var outline_mat := StandardMaterial3D.new()
	outline_mat.albedo_color = GameConfig.DESPERATE_OUTLINE_COLOR
	outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT

	_outline_mesh = MeshInstance3D.new()
	_outline_mesh.name = "DesperateOutline"
	_outline_mesh.mesh = _mesh.mesh
	_outline_mesh.position = _mesh.position
	_outline_mesh.scale = Vector3.ONE * GameConfig.DESPERATE_OUTLINE_SCALE
	_outline_mesh.set_surface_override_material(0, outline_mat)
	_outline_mesh.visible = false
	add_child(_outline_mesh)
