extends Node3D
## The Rooster. All black, iridescent, extremely serious.
## Struts by day. Perches on the Armory roof at night. Divebombs intruders.

const MK = preload("res://scripts/meshkit.gd")

var game: Node3D
# strut | to_perch | perch | swoop
var state := "strut"
var _target := Vector3.ZERO
var _timer := 0.0
var _anim_t := 0.0
var _attack_cd := 0.0
var _victim = null
var _wings: Array = []
var _legs: Array = []
var _stride := 0.0
var perch := Vector3(20.0, 3.15, -12.0)

func setup(g: Node3D, pos: Vector3) -> void:
	game = g
	position = pos
	_build_mesh()

func _iri(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.7
	m.roughness = 0.35
	return m

func _iri_mesh(mi: MeshInstance3D, c: Color) -> MeshInstance3D:
	mi.material_override = _iri(c)
	return mi

func _build_mesh() -> void:
	var black := Color(0.05, 0.055, 0.075)
	var leg_c := Color(0.13, 0.13, 0.15)
	# tall proud legs, hip-pivoted for the strut
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.08, 0.44, 0)
		add_child(hip)
		_legs.append(hip)
		MK.cyl(hip, 0.025, 0.028, 0.44, leg_c, Vector3(0, -0.22, 0))
		MK.box(hip, Vector3(0.1, 0.02, 0.15), leg_c, Vector3(0, -0.43, 0.05))
	# chest-out body
	_iri_mesh(MK.sphere(self, 0.28, black, Vector3(0, 0.6, -0.04)), black)
	var chest := _iri_mesh(MK.sphere(self, 0.24, black, Vector3(0, 0.78, 0.1)), Color(0.05, 0.07, 0.1))
	chest.scale = Vector3(0.85, 1.1, 0.95)
	# hackle (neck feather cape)
	var hackle := _iri_mesh(MK.cyl(self, 0.06, 0.17, 0.34, black, Vector3(0, 0.95, 0.13)), Color(0.04, 0.08, 0.09))
	hackle.rotation.x = deg_to_rad(-10)
	# tall neck + head
	_iri_mesh(MK.cyl(self, 0.05, 0.07, 0.3, black, Vector3(0, 1.1, 0.17)), black)
	_iri_mesh(MK.sphere(self, 0.1, black, Vector3(0, 1.28, 0.21)), black)
	# black comb: serrated spikes
	for i in 5:
		var cs := MK.box(self, Vector3(0.035, randf_range(0.07, 0.13), 0.05), Color(0.07, 0.06, 0.09), Vector3(0, 1.4, 0.14 + float(i) * 0.045))
		cs.rotation.x = randf_range(-0.25, 0.25)
	# dark wattles + short beak
	MK.sphere(self, 0.045, Color(0.16, 0.05, 0.07), Vector3(0.03, 1.17, 0.27))
	MK.sphere(self, 0.045, Color(0.16, 0.05, 0.07), Vector3(-0.03, 1.17, 0.27))
	var beak := MK.cyl(self, 0.0, 0.035, 0.11, Color(0.1, 0.09, 0.1), Vector3(0, 1.27, 0.32))
	beak.rotation.x = deg_to_rad(80)
	# small intense eyes
	MK.sphere(self, 0.02, Color(0.4, 0.08, 0.06), Vector3(0.07, 1.3, 0.26))
	MK.sphere(self, 0.02, Color(0.4, 0.08, 0.06), Vector3(-0.07, 1.3, 0.26))
	# wings
	for side in [-1.0, 1.0]:
		var w := _iri_mesh(MK.sphere(self, 0.2, black, Vector3(side * 0.24, 0.68, -0.02)), Color(0.04, 0.06, 0.09))
		w.scale = Vector3(0.35, 0.75, 1.1)
		_wings.append(w)
	# the great tail: long iridescent sickle feathers
	for i in 10:
		var tdir := Vector3(randf_range(-0.3, 0.3), randf_range(0.7, 1.4), randf_range(-1.4, -0.9)).normalized()
		var tl := randf_range(0.5, 0.95)
		var shade: Color = [Color(0.04, 0.08, 0.1), Color(0.05, 0.1, 0.08), Color(0.06, 0.06, 0.11)][i % 3]
		var f := MK.cyl(self, 0.0, 0.05, tl, shade, Vector3(0, 0.72, -0.24) + tdir * tl * 0.42)
		f.quaternion = Quaternion(Vector3.UP, tdir)
		_iri_mesh(f, shade)

func tick(delta: float) -> void:
	_anim_t += delta
	_attack_cd -= delta
	var flying := state == "to_perch" or state == "swoop"
	for i in _wings.size():
		var flap := sin(_anim_t * 18.0) * 0.7 if flying else 0.0
		_wings[i].rotation.z = flap * (1.0 if i == 0 else -1.0)
	match state:
		"strut":
			if game.is_night:
				state = "to_perch"
				return
			_timer -= delta
			if _timer <= 0.0:
				_target = game.rand_in_yard()
				_timer = randf_range(3.0, 6.0)
			_walk_toward(_target, 1.3, delta)
		"to_perch":
			if game.is_day():
				state = "strut"
				return
			if _fly_toward(perch, 6.0, delta):
				state = "perch"
				position = perch
		"perch":
			if game.is_day():
				state = "strut"
				return
			rotation.y += delta * 0.5  # slow menacing scan
			position = perch
			var e = game.nearest_enemy(game.coop_pos, 8.5)
			if e != null and game.enemies.has(e):
				_victim = e
				state = "swoop"
		"swoop":
			if game.is_day():
				state = "strut"
				return
			# an enemy pulled from game.enemies (killed, carried off, burned at dawn)
			# can still be a live node until end-of-frame, so check membership too
			if _victim == null or not is_instance_valid(_victim) or not game.enemies.has(_victim) or _victim.state == "burn":
				_victim = game.nearest_enemy(game.coop_pos, 8.5)
				if _victim == null:
					state = "to_perch"
					return
			var aim: Vector3 = _victim.position + Vector3(0, 0.6, 0)
			if _fly_toward(aim, 9.0, delta) or position.distance_to(aim) < 1.2:
				if _attack_cd <= 0.0:
					_attack_cd = 0.9
					game.spawn_poof(aim, Color(0.08, 0.09, 0.12), 5)
					game.sfx.play("hit", -4.0)
					_victim.damage(9.0)

func _walk_toward(dest: Vector3, speed: float, delta: float) -> bool:
	var d := Vector3(dest.x - position.x, 0, dest.z - position.z)
	if d.length() < 0.35:
		position.y = lerpf(position.y, 0.0, delta * 8.0)
		for leg in _legs:
			leg.rotation.x = lerpf(leg.rotation.x, 0.0, delta * 8.0)
		return true
	var dir := d.normalized()
	position += dir * speed * delta
	rotation.y = atan2(dir.x, dir.z)
	# slow, deliberate strut
	_stride += delta * speed * 3.4
	var swing := sin(_stride) * 0.6
	if _legs.size() == 2:
		_legs[0].rotation.x = swing
		_legs[1].rotation.x = -swing
	position.y = absf(sin(_stride)) * 0.03
	return false

func _fly_toward(dest: Vector3, speed: float, delta: float) -> bool:
	var d := dest - position
	if d.length() < 0.4:
		return true
	var dir := d.normalized()
	position += dir * speed * delta
	rotation.y = atan2(dir.x, dir.z)
	return false
