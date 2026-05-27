class_name HexGrid
extends MeshInstance3D
## Draws the hex tile grid as line wireframe in the 3D world.
## Uses PRIMITIVE_LINES — each hex's 6 edges drawn as vertex pairs.


# === Lifecycle ===

func _ready() -> void:
	mesh = _build_mesh()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.4, 0.4, 0.45, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	set_surface_override_material(0, mat)


# === Private ===

func _build_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var size: float = GameConfig.HEX_SIZE

	for r: int in GameConfig.GRID_HEIGHT:
		for q: int in GameConfig.GRID_WIDTH:
			var center: Vector2 = NavigationManager.tile_to_world(Vector2i(q, r))
			var cx: float = center.x
			var cz: float = center.y
			for i: int in 6:
				var a0: float = deg_to_rad(30.0 + 60.0 * i)
				var a1: float = deg_to_rad(30.0 + 60.0 * (i + 1))
				vertices.append(Vector3(cx + size * cos(a0), 1.0, cz + size * sin(a0)))
				vertices.append(Vector3(cx + size * cos(a1), 1.0, cz + size * sin(a1)))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices

	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return arr_mesh
