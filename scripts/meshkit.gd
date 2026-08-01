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

## Seamless procedural noise texture (albedo or normal map). No image assets needed.
static func noise_tex(noise_seed: int, freq: float, octaves := 4, as_normal := false, floor_v := 0.0) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = noise_seed
	n.frequency = freq
	n.fractal_octaves = octaves
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 256
	t.height = 256
	t.seamless = true
	if as_normal:
		t.as_normal_map = true
		t.bump_strength = 6.0
	elif floor_v > 0.0:
		# compress contrast so the texture is subtle variation, not black blotches
		var g := Gradient.new()
		g.set_color(0, Color(floor_v, floor_v, floor_v))
		g.set_color(1, Color.WHITE)
		t.color_ramp = g
	return t

## Textured PBR material: noise albedo multiplied by tint color, optional normal map.
static func tex_mat(color: Color, tex: Texture2D, uv_scale: float, rough := 0.95, normal: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = tex
	m.roughness = rough
	m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	if normal != null:
		m.normal_enabled = true
		m.normal_texture = normal
	return m

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
