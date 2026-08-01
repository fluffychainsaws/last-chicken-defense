extends SceneTree
## Dev utility: print a .glb's node tree, size and animations.
## Run: godot --headless --path . --script scripts/inspect_model.gd -- <res-path>

func _init() -> void:
	var path := "res://models/goblin.glb"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("res://"):
			path = a
	var packed = load(path)
	if packed == null:
		print("FAILED to load ", path)
		quit()
		return
	var root = packed.instantiate()
	print("--- ", path, " ---")
	_walk(root, 0)
	var aabb := _aabb(root)
	print("bounds size: ", aabb.size)
	print("bounds center: ", aabb.get_center())
	print("height: %.3f  width: %.3f  depth: %.3f" % [aabb.size.y, aabb.size.x, aabb.size.z])
	quit()

func _walk(n: Node, depth: int) -> void:
	var pad := ""
	for i in depth:
		pad += "  "
	var extra := ""
	if n is AnimationPlayer:
		extra = "  ANIMS=" + str(n.get_animation_list())
	if n is MeshInstance3D:
		extra = "  surfaces=%d" % n.mesh.get_surface_count()
		for i in n.mesh.get_surface_count():
			var mat = n.get_active_material(i)
			extra += "\n%s   surf%d mat=%s" % [pad, i, mat]
			if mat is StandardMaterial3D:
				extra += " albedo=%s tex=%s" % [mat.albedo_color, mat.albedo_texture]
				extra += " metal=%.2f rough=%.2f" % [mat.metallic, mat.roughness]
			if mat is BaseMaterial3D:
				extra += " vcol=%s" % mat.vertex_color_use_as_albedo
		var arr = n.mesh.surface_get_arrays(0)
		extra += "\n%s   verts=%d has_uv=%s has_color=%s has_normal=%s" % [pad, (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), arr[Mesh.ARRAY_TEX_UV] != null, arr[Mesh.ARRAY_COLOR] != null, arr[Mesh.ARRAY_NORMAL] != null]
		if arr[Mesh.ARRAY_NORMAL] != null:
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var avg := Vector3.ZERO
			var zero_count := 0
			for i in mini(2000, norms.size()):
				avg += norms[i]
				if norms[i].length() < 0.5:
					zero_count += 1
			extra += "\n%s   normals: n=%d degenerate=%d sample_avg_len=%.3f" % [pad, norms.size(), zero_count, (avg / float(mini(2000, norms.size()))).length()]
	print(pad, n.name, " [", n.get_class(), "]", extra)
	for c in n.get_children():
		_walk(c, depth + 1)

func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(n):
		var b: AABB = mi.global_transform * mi.mesh.get_aabb() if mi.is_inside_tree() else mi.transform * mi.mesh.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out

func _meshes(n: Node) -> Array:
	var acc := []
	if n is MeshInstance3D:
		acc.append(n)
	for c in n.get_children():
		acc += _meshes(c)
	return acc
