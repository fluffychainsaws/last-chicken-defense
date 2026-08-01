extends RefCounted
## Tiny helpers for building low-poly placeholder models out of primitives.

static func mat(color: Color, emissive := false, energy := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emissive:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
	return m

static func add_mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, emissive := false, energy := 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color, emissive, energy)
	mi.position = pos
	parent.add_child(mi)
	return mi

static func box(parent: Node3D, size: Vector3, color: Color, pos: Vector3, emissive := false) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return add_mesh(parent, m, color, pos, emissive)

static func sphere(parent: Node3D, r: float, color: Color, pos: Vector3, emissive := false, energy := 1.0) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	return add_mesh(parent, m, color, pos, emissive, energy)

static func cyl(parent: Node3D, r_top: float, r_bottom: float, h: float, color: Color, pos: Vector3, emissive := false) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = h
	return add_mesh(parent, m, color, pos, emissive)

static func capsule(parent: Node3D, r: float, h: float, color: Color, pos: Vector3) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	return add_mesh(parent, m, color, pos)

## Invisible (or colored) static collider box.
static func static_box(parent: Node3D, size: Vector3, pos: Vector3, color = null) -> StaticBody3D:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sb.add_child(cs)
	sb.position = pos
	parent.add_child(sb)
	if color != null:
		box(sb, size, color, Vector3.ZERO)
	return sb
