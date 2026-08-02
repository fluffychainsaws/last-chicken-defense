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

## Attach a mesh using a material the caller already built, instead of deriving
## one from a colour. Lets a whole creature share two or three materials — which
## also means a damage flash can tint all of it by touching just those.
static func skinned(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi

## SphereMesh defaults to 64x32 segments — ~2k triangles, which is absurd for a
## wart the size of a pea. Callers pick a budget: the default is plenty for small
## detail, and only the big silhouette pieces need to go higher.
static func sphere_mesh(r: float, segs := 16, rings := 8) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = segs
	m.rings = rings
	return m

static func cone_mesh(r: float, h: float, segs := 8) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = r
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return m

## Wet, oily hide: mottled albedo, bumpy normal, and a tight specular highlight.
## Forward+ gets a clearcoat lacquer for the greasy sheen; the compatibility
## renderer (web) silently drops clearcoat, so there the roughness is pulled
## down instead to keep the highlight from washing out flat.
## `sss` adds subsurface scattering, which is what stops flesh reading as
## painted plastic — light penetrates a little and bleeds back out. Opt-in
## rather than default: it belongs on skin, not on ice, keratin or eyeballs,
## and it is forward_plus only, so web silently gets nothing either way.
static func oily_mat(color: Color, tex: Texture2D, normal: Texture2D, uv_scale := 2.0, rough := 0.18, sss := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if tex != null:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	if normal != null:
		m.normal_enabled = true
		m.normal_texture = normal
		m.normal_scale = 1.5
	m.roughness = rough
	m.metallic = 0.0
	m.metallic_specular = 0.9
	# grazing-angle sheen: reads as a wet film over the whole body
	m.rim_enabled = true
	m.rim = 0.6
	m.rim_tint = 0.2
	if OS.has_feature("web"):
		m.roughness = rough * 0.7
	else:
		m.clearcoat_enabled = true
		m.clearcoat = 0.9
		m.clearcoat_roughness = 0.05
		if sss:
			m.subsurf_scatter_enabled = true
			m.subsurf_scatter_strength = 0.55
			# skin_mode uses the wider, redder falloff meant for flesh
			m.subsurf_scatter_skin_mode = true
			# thin parts — ears, fingers, webbing — glow when backlit by the moon
			m.subsurf_scatter_transmittance_enabled = true
			m.subsurf_scatter_transmittance_color = color.lerp(Color(0.9, 0.35, 0.3), 0.55)
			m.subsurf_scatter_transmittance_depth = 0.35
			m.subsurf_scatter_transmittance_boost = 0.25
	return m

## Collapse a node's MeshInstance3D descendants into one MeshInstance3D carrying
## a surface per distinct material, baking each piece's transform into its
## vertices. A creature built from seventy primitives costs seventy draw calls;
## merged, it costs one per material.
##
## This is a batching win, not a modelling one — the primitives still
## interpenetrate exactly as before, because nothing here computes a boolean
## union. Normals are carried over untouched for the same reason: regenerating
## them across pieces that overlap rather than join would wreck the shading.
##
## Anything in `stop` is left alone, subtree and all. Animated joints belong
## there — bake a leg into the body and it can no longer swing.
static func merge(holder: Node3D, stop := []) -> void:
	var found: Array = []
	_gather(holder, Transform3D.IDENTITY, stop, found)
	if found.size() < 2:
		return
	# group by material, preserving first-seen order so surfaces are stable
	var order: Array = []
	var groups := {}
	for entry in found:
		var m: Material = entry[2]
		if not groups.has(m):
			groups[m] = []
			order.append(m)
		groups[m].append(entry)
	var out := ArrayMesh.new()
	for m in order:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for entry in groups[m]:
			st.append_from(entry[0], 0, entry[1])
		st.commit(out)
	for entry in found:
		var n: MeshInstance3D = entry[3]
		n.get_parent().remove_child(n)
		n.queue_free()
	var merged := MeshInstance3D.new()
	merged.mesh = out
	holder.add_child(merged)
	# keep the very same material instances, so a damage flash still finds them
	for i in order.size():
		merged.set_surface_override_material(i, order[i])

static func _gather(n: Node, xform: Transform3D, stop: Array, acc: Array) -> void:
	for c in n.get_children():
		if c in stop:
			continue
		if not (c is Node3D):
			continue
		var child_x: Transform3D = xform * (c as Node3D).transform
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var mat := mi.material_override
			if mi.mesh != null and mat != null:
				acc.append([mi.mesh, child_x, mat, mi])
		_gather(c, child_x, stop, acc)

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
