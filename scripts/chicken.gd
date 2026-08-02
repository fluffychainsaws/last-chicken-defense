extends Node3D
## One chicken. Wanders and forages by day, garrisons the Armory (or fights) by night.

const MK = preload("res://scripts/meshkit.gd")
const CL = preload("res://scripts/classes.gd")

var game: Node3D
var hp := 25.0
var max_hp := 25.0
# wander | eat | forage_go | forage_work | forage_return | to_coop | in_coop | guard | panic | carried
var state := "wander"
var forager := false
var is_chick := false
var age := 0.0

var _target := Vector3.ZERO
var _timer := 0.0
var _peck_t := 0.0
var _attack_cd := 0.0
var _tree := Vector3.ZERO
var _eat_pile = null

var _head: Node3D
var _body_mat: StandardMaterial3D
var _helmet: MeshInstance3D = null
## A guard post, held for several seconds at a time. Re-rolling a destination on
## every single frame is what made helmeted hens vibrate in the coop doorway.
var _post := Vector3.ZERO
## Class, specialisation and the points poured into each track. Stats are
## derived from those three and cached, since they change only on purchase.
var class_id := "hen"
var spec_id := ""
var tracks := {}
var stats := {}
var _gear: Array = []
var _summon_cd := 0.0
## Owning a helmet is permanent and per bird; _helmet is only the mesh, worn
## at dusk and stowed at dawn. A hen can own one and not be wearing it.
var helmeted := false
var _gear_pos := Vector3.ZERO
var _legs: Array = []
var _stride := 0.0
var _head_base_z := 0.22

func setup(g: Node3D, pos: Vector3, chick: bool) -> void:
	game = g
	position = pos
	is_chick = chick
	if chick:
		hp = 12.0
		max_hp = 12.0
	_build_mesh()
	if chick:
		scale = Vector3.ONE * 0.45

func _build_mesh() -> void:
	# deranged clipart-chicken look: scraggly feathers, googly eyes, gangly everything
	var palettes := [
		[Color(0.13, 0.13, 0.15), Color(0.4, 0.4, 0.44)],    # charcoal
		[Color(0.55, 0.55, 0.58), Color(0.22, 0.22, 0.25)],  # gray
		[Color(0.75, 0.42, 0.16), Color(0.45, 0.2, 0.08)],   # rusty orange
		[Color(0.5, 0.34, 0.18), Color(0.82, 0.52, 0.2)],    # brown / ginger
		[Color(0.92, 0.88, 0.76), Color(0.55, 0.45, 0.3)],   # cream / tan
		[Color(0.95, 0.94, 0.9), Color(0.55, 0.55, 0.58)],   # white / gray
	]
	var pal: Array = palettes[randi() % palettes.size()]
	var body_col: Color = pal[0].lightened(randf() * 0.08)
	var accent: Color = pal[1]
	var leg_col := Color(0.9, 0.62, 0.2)
	# scrawny legs + big feet, pivoting from the hip so they can stride
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.07, 0.32, 0)
		add_child(hip)
		_legs.append(hip)
		MK.cyl(hip, 0.022, 0.022, 0.32, leg_col, Vector3(0, -0.16, 0))
		MK.box(hip, Vector3(0.09, 0.02, 0.13), leg_col, Vector3(0, -0.31, 0.04))
	# body (smaller, higher = ganglier)
	var body := MK.sphere(self, 0.27, body_col, Vector3(0, 0.5, 0))
	body.scale = Vector3(0.85, 0.95, 1.05)
	_body_mat = body.material_override
	# scraggly feather spikes bursting off the body
	for i in 14:
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.2, 1), randf_range(-1, 0.4)).normalized()
		var sp := MK.cyl(self, 0.0, 0.05, randf_range(0.2, 0.38), body_col.lerp(accent, randf() * 0.8), Vector3(0, 0.5, 0) + dir * 0.24)
		sp.quaternion = Quaternion(Vector3.UP, dir)
	# unhinged tail spray
	for i in 6:
		var tdir := Vector3(randf_range(-0.35, 0.35), randf_range(0.5, 1.1), randf_range(-1.3, -0.8)).normalized()
		var tl := randf_range(0.35, 0.55)
		var tsp := MK.cyl(self, 0.0, 0.055, tl, accent.lerp(Color(0.85, 0.3, 0.1), randf() * 0.5), Vector3(0, 0.6, -0.26) + tdir * tl * 0.4)
		tsp.quaternion = Quaternion(Vector3.UP, tdir)
	# gangly neck, random length
	var neck_h := randf_range(0.1, 0.3)
	var neck := MK.cyl(self, 0.045, 0.065, neck_h + 0.18, body_col, Vector3(0, 0.66 + neck_h * 0.5, 0.16))
	neck.rotation.x = deg_to_rad(-12)
	# head
	_head = Node3D.new()
	_head_base_z = 0.22
	_head.position = Vector3(0, 0.8 + neck_h, _head_base_z)
	add_child(_head)
	MK.sphere(_head, 0.12, body_col, Vector3.ZERO)
	# giant mismatched googly eyes with wandering pupils
	for side in [-1.0, 1.0]:
		var er := randf_range(0.06, 0.105)
		var epos := Vector3(side * 0.08, 0.04 + randf_range(-0.015, 0.03), 0.06)
		MK.sphere(_head, er, Color(0.97, 0.96, 0.93), epos)
		MK.sphere(_head, er * 0.42, Color(0.05, 0.04, 0.04), epos + Vector3(randf_range(-0.025, 0.025), randf_range(-0.025, 0.02), er * 0.82))
	# beak, permanently mid-squawk
	var top_beak := MK.cyl(_head, 0.0, 0.042, 0.16, Color(0.95, 0.6, 0.1), Vector3(0, -0.01, 0.15))
	top_beak.rotation.x = deg_to_rad(78)
	var bot_beak := MK.cyl(_head, 0.0, 0.035, 0.12, Color(0.85, 0.5, 0.08), Vector3(0, -0.07, 0.13))
	bot_beak.rotation.x = deg_to_rad(112)
	# wild comb: red spikes flopping at random angles
	for i in 2 + randi() % 3:
		var cs := MK.cyl(_head, 0.0, 0.028, randf_range(0.08, 0.17), Color(0.8, 0.12, 0.1), Vector3(randf_range(-0.03, 0.03), 0.1, randf_range(-0.05, 0.04)))
		cs.rotation.z = randf_range(-0.6, 0.6)
		cs.rotation.x = randf_range(-0.4, 0.3)
	# wattle
	MK.sphere(_head, 0.032, Color(0.75, 0.12, 0.1), Vector3(0, -0.1, 0.08))

func apply_helmet() -> void:
	if _helmet != null or _head == null:
		return
	_helmet = MK.cyl(_head, 0.14, 0.18, 0.1, Color(0.35, 0.4, 0.35), Vector3(0, 0.14, 0))
	_rebuild_gear()

## Recomputes stats and re-skins the bird. Called on every purchase.
func refresh_class() -> void:
	if tracks.is_empty():
		tracks = CL.new_tracks()
	stats = CL.stats(class_id, spec_id, tracks)
	var was_full: bool = hp >= max_hp - 0.01
	max_hp = stats["hp"] * (0.45 if is_chick else 1.0)
	hp = max_hp if was_full else minf(hp, max_hp)
	if _body_mat != null and class_id != "hen":
		_body_mat.albedo_color = stats["colour"]
	_rebuild_gear()

func title() -> String:
	return CL.title(class_id, spec_id, tracks)

## Class kit, worn only at night alongside the helmet. Rebuilt from scratch
## rather than patched, so a promotion can't leave the old class's gear on.
func _rebuild_gear() -> void:
	for g in _gear:
		if is_instance_valid(g):
			g.queue_free()
	_gear.clear()
	if _helmet == null:
		return
	var c: Color = stats.get("shot_colour", Color.WHITE)
	match class_id:
		"battle":
			_gear.append(MK.box(self, Vector3(0.06, 0.34, 0.05), Color(0.7, 0.7, 0.74), Vector3(0.24, 0.3, 0.1)))
		"archer":
			var bow := MK.cyl(self, 0.02, 0.02, 0.44, Color(0.42, 0.3, 0.16), Vector3(0.24, 0.3, 0.06))
			bow.rotation.z = deg_to_rad(18)
			_gear.append(bow)
		"mage":
			_gear.append(MK.cyl(self, 0.018, 0.022, 0.5, Color(0.35, 0.26, 0.18), Vector3(0.24, 0.3, 0.06)))
			_gear.append(MK.sphere(self, 0.06, c, Vector3(0.24, 0.58, 0.06), true, 2.2))
		"knight":
			_gear.append(MK.box(self, Vector3(0.22, 0.26, 0.04), Color(0.66, 0.68, 0.74), Vector3(-0.24, 0.28, 0.12)))
			_gear.append(MK.box(self, Vector3(0.05, 0.3, 0.05), Color(0.75, 0.76, 0.8), Vector3(0.24, 0.32, 0.08)))
		"military":
			_gear.append(MK.box(self, Vector3(0.05, 0.05, 0.5), Color(0.22, 0.22, 0.2), Vector3(0.2, 0.3, 0.16)))

func remove_helmet() -> void:
	if _helmet != null:
		_helmet.queue_free()
		_helmet = null
	for g in _gear:
		if is_instance_valid(g):
			g.queue_free()
	_gear.clear()

## Somewhere near the coop to stand watch, held until the timer runs out.
func _pick_post() -> void:
	var a := randf() * TAU
	var r := randf_range(2.2, 4.8)
	_post = game.coop_door + Vector3(cos(a) * r, 0, sin(a) * r)
	_timer = randf_range(4.0, 8.0)

func targetable() -> bool:
	return state != "in_coop" and state != "carried"

func tick(delta: float) -> void:
	_timer -= delta
	_attack_cd -= delta
	_summon_cd -= delta
	_peck_t += delta
	if is_chick and not game.is_night:
		age += delta
		var s: float = lerpf(0.45, 1.0, clampf(age / 340.0, 0.0, 1.0))
		scale = Vector3.ONE * s
		if age >= 340.0:
			is_chick = false
			hp = 25.0
			max_hp = 25.0
			scale = Vector3.ONE
	match state:
		"carried", "in_coop":
			return
		"wander":
			if _timer <= 0.0:
				_target = game.rand_in_yard()
				_timer = randf_range(2.0, 5.0)
				if randf() < 0.3:
					game.sfx.cluck(-15.0)
			_walk_toward(_target, 1.6, delta)
			_head.rotation.x = maxf(0.0, sin(_peck_t * 3.0)) * 0.9
		"eat":
			if _eat_pile == null or not is_instance_valid(_eat_pile.node):
				_eat_pile = null
				state = "wander"
				return
			var p: Vector3 = _eat_pile.node.position
			if _walk_toward(p, 2.4, delta):
				_timer -= delta
				_head.rotation.x = maxf(0.0, sin(_peck_t * 8.0)) * 1.1
				if _timer <= 0.0:
					hp = minf(max_hp, hp + 30.0)
					game.consume_feed_pile(_eat_pile)
					_eat_pile = null
					state = "wander"
					game.sfx.cluck(-10.0)
		"forage_go":
			if _walk_toward(_tree, 2.2, delta):
				state = "forage_work"
				_timer = 4.0
		"forage_work":
			_head.rotation.x = maxf(0.0, sin(_peck_t * 7.0)) * 1.0
			_timer -= delta
			if _timer <= 0.0:
				state = "forage_return"
		"forage_return":
			var home := Vector3(randf_range(-8.0, 8.0), 0, randf_range(12.0, 18.0))
			if _walk_toward(Vector3(0, 0, 16), 2.2, delta):
				game.forage_deposit(self)
				_tree = game.pick_tree()
				state = "forage_go" if forager else "wander"
				_target = home
		"to_coop":
			if _walk_toward(game.coop_door, 3.2, delta):
				if game.coop_broken:
					state = "panic"
				else:
					state = "in_coop"
					visible = false
		"fetch_gear":
			# walk out to whatever the drone dropped and claim it
			if _walk_toward(_gear_pos, 2.6, delta):
				helmeted = true
				game.sfx.cluck(-6.0)
				game.spawn_poof(position + Vector3(0, 0.6, 0), Color(0.6, 0.7, 0.5), 6)
				state = "wander" if not game.is_night else "to_arm"
		"to_arm":
			# fetch the gear from the coop, then take up a post outside it
			if _walk_toward(game.coop_door, 3.2, delta):
				apply_helmet()
				if bool(stats.get("perch", false)):
					state = "perch"
				else:
					_pick_post()
					state = "guard"
		"to_stow":
			# the night's gear goes back in the coop before the day resumes
			if _walk_toward(game.coop_door, 2.6, delta):
				remove_helmet()
				if forager:
					_tree = game.pick_tree()
					state = "forage_go"
				else:
					state = "wander"
		"perch":
			# the military hen fights from the coop roof and never comes down
			position = position.lerp(game.coop_pos + Vector3(0, 3.1, 0), delta * 2.0)
			_fire_at(game.nearest_enemy(position, float(stats.get("range", 12.0))), delta)
		"guard":
			var reach: float = float(stats.get("range", 1.6))
			# search well past reach, so melee birds actually close the gap
			var enemy = game.nearest_enemy(position, maxf(reach, 6.0))
			if enemy != null:
				if not bool(stats.get("ranged", false)):
					_walk_toward(enemy.position, 2.6 * float(stats.get("speed", 1.0)), delta)
				_head.rotation.x = maxf(0.0, sin(_peck_t * 10.0)) * 1.2
				_fire_at(enemy, delta)
			else:
				if _timer <= 0.0 or _post == Vector3.ZERO:
					_pick_post()
				_walk_toward(_post, 1.6, delta)
		"panic":
			if _timer <= 0.0:
				_target = game.rand_in_yard()
				_timer = randf_range(0.5, 1.2)
				game.sfx.cluck(-6.0)
			_walk_toward(_target, 4.2, delta)

## One attack path for every class. Melee needs contact; ranged only needs to
## be in reach, and hands off to the game's projectile pool.
func _fire_at(enemy, _delta: float) -> void:
	if enemy == null or _attack_cd > 0.0:
		return
	if position.distance_to(enemy.position) > float(stats.get("range", 1.6)):
		return
	_attack_cd = float(stats.get("cd", 0.8))
	# a summoner keeps a small retinue up while she has something to shoot at
	if bool(stats.get("summon", false)) and _summon_cd <= 0.0:
		if game.minion_count("spirit") < 5:
			_summon_cd = 6.0
			game.summon_minion(position, "spirit", float(stats.get("dmg", 8.0)) * 0.45)
	var dmg: float = float(stats.get("dmg", 4.0))
	if bool(stats.get("ranged", false)):
		game.hen_shot(self, enemy, dmg, stats)
	else:
		enemy.damage(dmg)
		game.sfx.cluck(-8.0)

## Called when a delivery lands. The hen drops what she is doing and goes.
func await_package(pos: Vector3) -> void:
	if helmeted or is_chick:
		return
	_gear_pos = pos
	state = "fetch_gear"

func start_forage() -> void:
	forager = true
	_tree = game.pick_tree()
	state = "forage_go"

func stop_forage() -> void:
	forager = false
	if state.begins_with("forage"):
		state = "wander"

func night_mode() -> void:
	stop_forage()
	if helmeted and not is_chick:
		state = "to_arm"
	else:
		state = "to_coop"

func day_mode() -> void:
	visible = true
	position.y = 0.0
	hp = minf(max_hp, hp + 5.0)
	_post = Vector3.ZERO
	if _helmet != null:
		state = "to_stow"
		return
	state = "forage_go" if forager else "wander"
	if forager:
		_tree = game.pick_tree()

func assign_eat(pile) -> void:
	if state in ["wander", "forage_go", "forage_return"]:
		_eat_pile = pile
		_timer = 1.6
		state = "eat"

## Returns true when arrived. Speed in m/s.
func _walk_toward(dest: Vector3, speed: float, delta: float) -> bool:
	var flat := Vector3(dest.x, 0, dest.z)
	var d := flat - Vector3(position.x, 0, position.z)
	if d.length() < 0.35:
		_settle_legs(delta)
		return true
	var dir := d.normalized()
	position += dir * speed * delta
	rotation.y = atan2(dir.x, dir.z)
	_step_legs(speed, delta)
	return false

## Alternating leg strides + slight body dip + chicken head-bob.
func _step_legs(speed: float, delta: float) -> void:
	_stride += delta * speed * 4.2
	var swing := sin(_stride) * 0.55
	if _legs.size() == 2:
		_legs[0].rotation.x = swing
		_legs[1].rotation.x = -swing
	# body dips on each footfall (twice per stride cycle)
	position.y = absf(sin(_stride)) * 0.022
	# head thrusts forward then holds — the classic chicken bob
	if _head != null:
		_head.position.z = _head_base_z + sin(_stride * 2.0) * 0.045

## Ease the legs back to neutral when standing still.
func _settle_legs(delta: float) -> void:
	position.y = lerpf(position.y, 0.0, delta * 8.0)
	for leg in _legs:
		leg.rotation.x = lerpf(leg.rotation.x, 0.0, delta * 8.0)
	if _head != null:
		_head.position.z = lerpf(_head.position.z, _head_base_z, delta * 8.0)

func damage(n: float) -> void:
	if randf() < float(stats.get("dodge", 0.0)):
		game.spawn_poof(position + Vector3(0, 0.5, 0), Color(0.9, 0.9, 1.0), 3)
		return
	hp -= n * (1.0 - float(stats.get("armor", 0.0)))
	if _body_mat != null:
		# energy only — toggling the feature recompiles the shader mid-fight
		_body_mat.emission = Color(1, 0.3, 0.3)
		_body_mat.emission_energy_multiplier = 0.7
		var tw := create_tween()
		tw.tween_interval(0.12)
		tw.tween_callback(func(): _body_mat.emission_energy_multiplier = 0.0)
	game.sfx.cluck(-4.0)
	if hp <= 0.0:
		game.chicken_died(self)
