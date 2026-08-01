extends Node3D
## Last Chicken Defense - The Armaeggin
## Cozy chicken farm by day. Something comes out of the trees at night.

const MK = preload("res://scripts/meshkit.gd")
const ChickenScript = preload("res://scripts/chicken.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const PlayerScript = preload("res://scripts/player.gd")
const UIScript = preload("res://scripts/game_ui.gd")
const SfxScript = preload("res://scripts/sfx.gd")

const DAY_LEN := 170.0
const NIGHT_LEN := 115.0
const SAVE_PATH := "user://armaeggin_save.json"
const MAX_CHICKENS := 24

const YARD := {"min_x": -30.0, "max_x": 30.0, "min_z": -20.0, "max_z": 20.0}
const GATE_HALF := 3.0

const WHISPERS := [
	"it smells the eggs",
	"don't look at the tree line",
	"the coop remembers",
	"they were never chickens",
	"count them again",
	"one of them is watching you",
	"the rooster knows something",
	"lock the gate. lock the gate. lock the",
]

var sfx: Node
var ui: CanvasLayer
var player: CharacterBody3D
var env: Environment
var sun: DirectionalLight3D
var moon: MeshInstance3D
var moon_mat: StandardMaterial3D
var fence_mat: StandardMaterial3D

var chickens: Array = []
var enemies: Array = []
var projectiles: Array = []
var particles: Array = []
var egg_pickups: Array = []
var feed_piles: Array = []
var tree_spots: Array = []

var coins := 25
var eggs := 0
var feed := 5
var shells := 0
var day_num := 1
var is_night := false
var phase_t := 0.0
var upgrades := {"fence": 0, "coop": 0, "helmets": false, "turret": false, "rooster": false, "shotgun": false, "shoes": false}
var coop_hp := 300.0
var coop_broken := false
var night_theme := {}

var coop_pos := Vector3(20, 0, -12)
var coop_door := Vector3(17.6, 0, -12)
var computer_pos := Vector3(-24.2, 1.0, -12)
var turret_node: Node3D = null
var _turret_cd := 0.0

var started := false
var paused := true
var over := false
var market_open := false
var spawn_dist := 62.0
var _spawn_left := 0
var _spawn_timer := 0.0
var _spawned_boss := false
var _whisper_t := 20.0
var _ui_t := 0.0
var _test_mode := false

func _ready() -> void:
	_setup_input()
	sfx = SfxScript.new()
	add_child(sfx)
	_build_environment()
	_build_world()
	player = PlayerScript.new()
	add_child(player)
	player.setup(self)
	ui = UIScript.new()
	add_child(ui)
	ui.setup(self)
	ui.refresh()
	var shots_dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots_dir = arg.trim_prefix("--shots=")
	if shots_dir != "":
		_test_mode = true
		spawn_dist = 13.0
		_run_shot_test(shots_dir)
	else:
		ui.show_start(has_save())

func _setup_input() -> void:
	var defs := {
		"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"sprint": KEY_SHIFT, "jump": KEY_SPACE, "interact": KEY_E,
		"slot1": KEY_1, "slot2": KEY_2, "slot3": KEY_3, "slot4": KEY_4,
	}
	for action_name in defs:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
			var ev := InputEventKey.new()
			ev.physical_keycode = defs[action_name]
			InputMap.action_add_event(action_name, ev)

# ---------------- world ----------------

func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.7, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.87, 0.95)
	env.ambient_light_energy = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.8, 0.9)
	env.fog_density = 0.0008
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)
	moon = MK.sphere(self, 5.0, Color(0.93, 0.9, 0.82), Vector3(70, 55, -90), true, 2.0)
	moon_mat = moon.material_override
	moon.visible = false

func _build_world() -> void:
	# ground
	MK.static_box(self, Vector3(240, 1, 240), Vector3(0, -0.5, 0), Color(0.32, 0.52, 0.25))
	# dirt in the chicken run + path to the gate
	MK.box(self, Vector3(12, 0.04, 10), Color(0.5, 0.38, 0.24), Vector3(22, 0.02, -1))
	MK.box(self, Vector3(2.2, 0.04, 16), Color(0.62, 0.55, 0.4), Vector3(0, 0.02, 12))
	_build_house()
	_build_coop()
	_build_run_fence()
	_build_perimeter_fence()
	_build_forest()

func _build_house() -> void:
	var hx := -20.0
	var hz := -12.0
	MK.box(self, Vector3(12, 0.06, 10), Color(0.45, 0.35, 0.28), Vector3(hx, 0.03, hz))
	var wall_c := Color(0.78, 0.72, 0.6)
	MK.static_box(self, Vector3(0.3, 3.2, 10.3), Vector3(hx - 6, 1.6, hz), wall_c)
	MK.static_box(self, Vector3(0.3, 3.2, 4.3), Vector3(hx + 6, 1.6, hz - 2.85), wall_c)
	MK.static_box(self, Vector3(0.3, 3.2, 4.3), Vector3(hx + 6, 1.6, hz + 2.85), wall_c)
	MK.static_box(self, Vector3(12.3, 3.2, 0.3), Vector3(hx, 1.6, hz - 5), wall_c)
	MK.static_box(self, Vector3(12.3, 3.2, 0.3), Vector3(hx, 1.6, hz + 5), wall_c)
	MK.box(self, Vector3(13.4, 0.3, 11.4), Color(0.35, 0.22, 0.16), Vector3(hx, 3.5, hz))
	MK.box(self, Vector3(13.4, 0.5, 2.0), Color(0.35, 0.22, 0.16), Vector3(hx, 3.8, hz))
	# desk + computer
	MK.static_box(self, Vector3(1.0, 0.9, 2.2), Vector3(hx - 4.6, 0.45, hz), Color(0.5, 0.36, 0.2))
	MK.box(self, Vector3(0.12, 0.6, 0.9), Color(0.12, 0.12, 0.14), Vector3(hx - 4.8, 1.35, hz))
	MK.box(self, Vector3(0.02, 0.48, 0.75), Color(0.3, 0.9, 0.4), Vector3(hx - 4.72, 1.35, hz), true)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.8, 0.55)
	lamp.light_energy = 1.4
	lamp.omni_range = 12.0
	lamp.position = Vector3(hx, 2.8, hz)
	add_child(lamp)

func _build_coop() -> void:
	MK.static_box(self, Vector3(3.6, 2.6, 3.2), Vector3(20, 1.3, -12), Color(0.62, 0.24, 0.18))
	var roof := MK.box(self, Vector3(4.4, 0.2, 4.0), Color(0.32, 0.2, 0.13), Vector3(20, 2.85, -12))
	roof.rotation.z = 0.14
	MK.box(self, Vector3(0.06, 1.3, 0.95), Color(0.08, 0.06, 0.05), Vector3(18.18, 0.65, -12))
	MK.box(self, Vector3(0.06, 0.45, 1.5), Color(0.9, 0.88, 0.8), Vector3(18.15, 1.95, -12))

func _build_run_fence() -> void:
	var wire := Color(0.75, 0.75, 0.78, 0.4)
	MK.box(self, Vector3(12, 1.1, 0.06), wire, Vector3(22, 0.55, -6))
	MK.box(self, Vector3(12, 1.1, 0.06), wire, Vector3(22, 0.55, 4))
	MK.box(self, Vector3(0.06, 1.1, 10), wire, Vector3(28, 0.55, -1))
	MK.box(self, Vector3(0.06, 1.1, 3.6), wire, Vector3(16, 0.55, -4.2))
	MK.box(self, Vector3(0.06, 1.1, 3.6), wire, Vector3(16, 0.55, 2.2))

func _build_perimeter_fence() -> void:
	fence_mat = MK.mat(Color(0.55, 0.4, 0.24))
	var group := Node3D.new()
	add_child(group)
	# posts
	var x := YARD.min_x
	while x <= YARD.max_x:
		for z in [YARD.min_z, YARD.max_z]:
			if z == YARD.max_z and absf(x) < GATE_HALF + 0.5:
				continue
			var p := MK.box(group, Vector3(0.16, 1.3, 0.16), Color.WHITE, Vector3(x, 0.65, z))
			p.material_override = fence_mat
		x += 3.0
	var z2 := YARD.min_z
	while z2 <= YARD.max_z:
		for x2 in [YARD.min_x, YARD.max_x]:
			var p2 := MK.box(group, Vector3(0.16, 1.3, 0.16), Color.WHITE, Vector3(x2, 0.65, z2))
			p2.material_override = fence_mat
		z2 += 3.0
	# rails
	for y in [0.5, 1.0]:
		for rail_def in [
			[Vector3(60.4, 0.08, 0.08), Vector3(0, y, YARD.min_z)],
			[Vector3(0.08, 0.08, 40.4), Vector3(YARD.min_x, y, 0)],
			[Vector3(0.08, 0.08, 40.4), Vector3(YARD.max_x, y, 0)],
			[Vector3(27.0 - GATE_HALF, 0.08, 0.08), Vector3(-(YARD.max_x + GATE_HALF) / 2.0, y, YARD.max_z)],
			[Vector3(27.0 - GATE_HALF, 0.08, 0.08), Vector3((YARD.max_x + GATE_HALF) / 2.0, y, YARD.max_z)],
		]:
			var r := MK.box(group, rail_def[0], Color.WHITE, rail_def[1])
			r.material_override = fence_mat
	# invisible colliders (player-blocking); gate gap on +z side
	MK.static_box(self, Vector3(61, 1.4, 0.3), Vector3(0, 0.7, YARD.min_z))
	MK.static_box(self, Vector3(0.3, 1.4, 41), Vector3(YARD.min_x, 0.7, 0))
	MK.static_box(self, Vector3(0.3, 1.4, 41), Vector3(YARD.max_x, 0.7, 0))
	MK.static_box(self, Vector3(27.0 - GATE_HALF, 1.4, 0.3), Vector3(-(YARD.max_x + GATE_HALF) / 2.0, 0.7, YARD.max_z))
	MK.static_box(self, Vector3(27.0 - GATE_HALF, 1.4, 0.3), Vector3((YARD.max_x + GATE_HALF) / 2.0, 0.7, YARD.max_z))

func _build_forest() -> void:
	var placed := 0
	while placed < 120:
		var x := randf_range(-110.0, 110.0)
		var z := randf_range(-110.0, 110.0)
		if absf(x) < 38.0 and absf(z) < 28.0:
			continue
		var tree := Node3D.new()
		tree.position = Vector3(x, 0, z)
		add_child(tree)
		var g := Color(0.16 + randf() * 0.1, 0.4 + randf() * 0.15, 0.16)
		MK.cyl(tree, 0.22, 0.34, 1.8, Color(0.4, 0.28, 0.16), Vector3(0, 0.9, 0))
		MK.cyl(tree, 0.0, 1.6, 2.4, g, Vector3(0, 2.7, 0))
		MK.cyl(tree, 0.0, 1.1, 1.9, g.lightened(0.06), Vector3(0, 4.1, 0))
		if Vector3(x, 0, z).length() < 60.0:
			tree_spots.append(Vector3(x, 0, z))
		placed += 1
	for i in 30:
		var bx := randf_range(-100.0, 100.0)
		var bz := randf_range(-100.0, 100.0)
		if absf(bx) < 34.0 and absf(bz) < 24.0:
			continue
		var b := MK.sphere(self, randf_range(0.5, 1.0), Color(0.2, 0.42, 0.18), Vector3(bx, 0.25, bz))
		b.scale.y = 0.6
	for i in 14:
		var rx := randf_range(-90.0, 90.0)
		var rz := randf_range(-90.0, 90.0)
		if absf(rx) < 32.0 and absf(rz) < 22.0:
			continue
		MK.sphere(self, randf_range(0.3, 0.7), Color(0.5, 0.5, 0.52), Vector3(rx, 0.15, rz))

func _build_turret() -> void:
	if turret_node != null:
		return
	turret_node = Node3D.new()
	turret_node.position = Vector3(0, 0, -2)
	add_child(turret_node)
	MK.cyl(turret_node, 0.12, 0.16, 1.6, Color(0.4, 0.42, 0.45), Vector3(0, 0.8, 0))
	MK.box(turret_node, Vector3(0.5, 0.36, 0.7), Color(0.3, 0.32, 0.36), Vector3(0, 1.8, 0))
	MK.cyl(turret_node, 0.06, 0.06, 0.7, Color(0.9, 0.88, 0.8), Vector3(0, 1.8, 0.5)).rotation.x = deg_to_rad(90)

# ---------------- game flow ----------------

func start_new() -> void:
	for i in 10:
		_spawn_chicken(rand_in_yard(), false)
	_begin()

func start_continue() -> void:
	_load_game()
	_begin()

func _begin() -> void:
	started = true
	over = false
	paused = false
	ui.clear_overlay()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	ui.refresh()
	ui.announce("DAY %d" % day_num, "protect the flock")

func restart() -> void:
	get_tree().reload_current_scene()

func unpause() -> void:
	paused = false
	ui.clear_overlay()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func pause_game() -> void:
	paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	ui.show_pause()

func is_day() -> bool:
	return not is_night

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if market_open:
			close_market()
		elif started and not over:
			if paused:
				unpause()
			else:
				pause_game()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_N and started and not paused and not over and not is_night:
			phase_t = 1.0  # debug: skip to night

func _process(delta: float) -> void:
	if not started or over:
		return
	if paused:
		return
	phase_t += delta / (NIGHT_LEN if is_night else DAY_LEN)
	if phase_t >= 1.0:
		phase_t = 0.0
		if is_night:
			_start_dawn()
		else:
			_start_night()
	_update_environment()
	for c in chickens.duplicate():
		c.tick(delta)
	for e in enemies.duplicate():
		e.tick(delta)
	_update_projectiles(delta)
	_update_particles(delta)
	_update_pickups()
	if is_night:
		_update_spawning(delta)
		_update_turret(delta)
		_whisper_t -= delta
		if _whisper_t <= 0.0:
			_whisper_t = randf_range(14.0, 26.0)
			ui.whisper(WHISPERS[randi() % WHISPERS.size()])
	_ui_t -= delta
	if _ui_t <= 0.0:
		_ui_t = 0.25
		ui.refresh()

func _start_night() -> void:
	is_night = true
	coop_hp = minf(coop_hp, max_coop_hp())
	night_theme = EnemyScript.pick_theme(day_num)
	var boss: bool = night_theme.get("boss", false)
	var count: int
	if boss:
		count = 1 + int(night_theme.get("escort", 2))
	else:
		count = clampi(int(round(night_theme.base + night_theme.per * float(day_num - 1))), 3, 26)
	_spawn_left = count
	_spawned_boss = false
	_spawn_timer = 0.0 if _test_mode else 2.0
	moon.visible = true
	moon_mat.albedo_color = Color(0.85, 0.2, 0.15) if boss else Color(0.93, 0.9, 0.82)
	moon_mat.emission = moon_mat.albedo_color
	for c in chickens:
		c.night_mode()
	if market_open:
		close_market()
	ui.night_fx(true, boss)
	ui.announce(night_theme.name, "NIGHT %d  -  %s" % [day_num, night_theme.sub], true)
	sfx.play("horn")
	_whisper_t = 8.0

func _start_dawn() -> void:
	is_night = false
	day_num += 1
	for e in enemies.duplicate():
		e.ignite()
	moon.visible = false
	ui.night_fx(false)
	var laid := 0
	for c in chickens:
		c.day_mode()
		if not c.is_chick:
			laid += 1
			var egg_mesh := MK.sphere(self, 0.14, Color(0.98, 0.95, 0.85), coop_door + Vector3(randf_range(-3.5, 1.5), 0.12, randf_range(-3.5, 3.5)))
			egg_mesh.scale.y = 1.3
			egg_pickups.append(egg_mesh)
	var hatched := 0
	if upgrades.rooster:
		for c in chickens.duplicate():
			if not c.is_chick and chickens.size() + hatched < MAX_CHICKENS and randf() < 0.12:
				hatched += 1
	for i in hatched:
		_spawn_chicken(coop_door + Vector3(randf_range(-2, 0), 0, randf_range(-2, 2)), true)
	var sub := "%d eggs in the yard" % laid
	if hatched > 0:
		sub += "  -  %d chick hatched!" % hatched
	ui.announce("DAY %d" % day_num, sub)
	if not _test_mode:
		_save_game()
	ui.refresh()

# ---------------- spawning / combat ----------------

func _update_spawning(delta: float) -> void:
	if _spawn_left <= 0:
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	var boss: bool = night_theme.get("boss", false)
	var is_escort := boss and _spawned_boss
	var e = EnemyScript.new()
	add_child(e)
	e.setup(self, day_num, night_theme, is_escort)
	e.position = e.position.normalized() * spawn_dist
	if e.flying:
		e.position.y = 9.0
	enemies.append(e)
	if boss:
		_spawned_boss = true
	_spawn_left -= 1
	var count_total := maxi(_spawn_left + enemies.size(), 1)
	_spawn_timer = 1.0 if _test_mode else NIGHT_LEN * 0.5 / float(count_total)

func remove_enemy(e: Node3D, give_bounty: bool) -> void:
	if not enemies.has(e):
		return
	enemies.erase(e)
	if give_bounty:
		add_coins(int(e.theme.bounty))
		sfx.play("coin", -6.0)
		spawn_poof(e.position + Vector3(0, 1, 0), e.theme.body, 10)
	e.queue_free()

func melee_attack(origin: Vector3, dir: Vector3) -> void:
	var best = null
	var best_d := 3.1
	for e in enemies:
		var to: Vector3 = e.position + Vector3(0, 1, 0) - origin
		var d := to.length()
		if d < best_d and to.normalized().dot(dir) > 0.5:
			best = e
			best_d = d
	if best != null:
		best.damage(25.0)

func shotgun_attack(origin: Vector3, dir: Vector3) -> void:
	for i in 7:
		var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.05
		var pd := (dir + jitter).normalized()
		var best = null
		var best_t := 45.0
		for e in enemies:
			var center: Vector3 = e.position + Vector3(0, 1.0 * e.body_scale, 0)
			var to := center - origin
			var t := to.dot(pd)
			if t < 0.5 or t > best_t:
				continue
			var perp := (to - pd * t).length()
			if perp < 0.7 * maxf(1.0, e.body_scale):
				best = e
				best_t = t
		if best != null:
			best.damage(10.0)

func throw_projectile(kind: String, origin: Vector3, dir: Vector3) -> void:
	var color := Color(0.98, 0.95, 0.85) if kind == "egg" else Color(0.85, 0.7, 0.35)
	var m := MK.sphere(self, 0.11, color, origin + dir * 0.5)
	projectiles.append({"node": m, "vel": dir * 14.0 + Vector3(0, 3.5, 0), "kind": kind, "life": 4.0})

func turret_fire(target: Node3D) -> void:
	var head: Vector3 = turret_node.position + Vector3(0, 1.8, 0)
	var aim: Vector3 = (target.position + Vector3(0, 1, 0) - head).normalized()
	turret_node.rotation.y = atan2(aim.x, aim.z)
	var m := MK.sphere(self, 0.12, Color(0.98, 0.95, 0.85), head + aim * 0.8)
	projectiles.append({"node": m, "vel": aim * 22.0, "kind": "turret", "life": 2.0})
	sfx.play("egg", -8.0)

func _update_turret(delta: float) -> void:
	if not upgrades.turret or turret_node == null:
		return
	_turret_cd -= delta
	if _turret_cd > 0.0:
		return
	var target = nearest_enemy(turret_node.position, 30.0)
	if target != null:
		_turret_cd = 1.1
		turret_fire(target)

func _update_projectiles(delta: float) -> void:
	for pr in projectiles.duplicate():
		pr.life -= delta
		if pr.kind != "turret":
			pr.vel.y -= 20.0 * delta
		pr.node.position += pr.vel * delta
		var done := false
		var hit = nearest_enemy(pr.node.position, 0.9)
		match pr.kind:
			"turret":
				if hit != null:
					hit.damage(25.0)
					spawn_poof(pr.node.position, Color(0.98, 0.95, 0.85), 5)
					done = true
			"egg":
				if hit != null or pr.node.position.y <= 0.1:
					for e in enemies.duplicate():
						if e.position.distance_to(pr.node.position) < 2.0:
							e.damage(20.0)
					spawn_poof(pr.node.position, Color(0.98, 0.93, 0.7), 8)
					sfx.play("egg")
					done = true
			"feed":
				if pr.node.position.y <= 0.1:
					var pile := {"node": MK.cyl(self, 0.3, 0.4, 0.12, Color(0.85, 0.72, 0.4), Vector3(pr.node.position.x, 0.06, pr.node.position.z))}
					feed_piles.append(pile)
					var c = nearest_chicken(pile.node.position, 20.0)
					if c != null:
						c.assign_eat(pile)
					done = true
		if done or pr.life <= 0.0:
			projectiles.erase(pr)
			pr.node.queue_free()

func consume_feed_pile(pile) -> void:
	if feed_piles.has(pile):
		feed_piles.erase(pile)
		pile.node.queue_free()

func _update_particles(delta: float) -> void:
	for p in particles.duplicate():
		p.life -= delta
		p.vel.y -= 9.0 * delta
		p.node.position += p.vel * delta
		p.node.scale = Vector3.ONE * maxf(0.05, p.life / p.max_life)
		if p.life <= 0.0:
			particles.erase(p)
			p.node.queue_free()

func spawn_poof(pos: Vector3, color: Color, n: int) -> void:
	for i in n:
		var m := MK.sphere(self, randf_range(0.06, 0.14), color, pos + Vector3(randf_range(-0.3, 0.3), randf_range(0, 0.5), randf_range(-0.3, 0.3)))
		var vel := Vector3(randf_range(-2, 2), randf_range(1, 4), randf_range(-2, 2))
		particles.append({"node": m, "vel": vel, "life": 0.6, "max_life": 0.6})

func _update_pickups() -> void:
	for egg_mesh in egg_pickups.duplicate():
		if player.position.distance_to(egg_mesh.position) < 1.5:
			egg_pickups.erase(egg_mesh)
			egg_mesh.queue_free()
			eggs += 1
			sfx.play("coin", -10.0)
			ui.refresh()

# ---------------- queries ----------------

func rand_in_yard() -> Vector3:
	return Vector3(randf_range(YARD.min_x + 3.0, YARD.max_x - 3.0), 0, randf_range(YARD.min_z + 3.0, YARD.max_z - 3.0))

func in_yard(x: float, z: float) -> bool:
	return x > YARD.min_x and x < YARD.max_x and z > YARD.min_z and z < YARD.max_z

func in_gate(x: float, z: float) -> bool:
	return absf(x) < GATE_HALF and absf(z - YARD.max_z) < 2.5

func pick_tree() -> Vector3:
	if tree_spots.is_empty():
		return Vector3(0, 0, 40)
	return tree_spots[randi() % tree_spots.size()]

func nearest_enemy(pos: Vector3, radius: float):
	var best = null
	var best_d := radius
	for e in enemies:
		if e.state == "burn":
			continue
		var d: float = Vector3(e.position.x - pos.x, 0, e.position.z - pos.z).length()
		if d < best_d:
			best = e
			best_d = d
	return best

func nearest_targetable_chicken(pos: Vector3):
	var best = null
	var best_d := 9999.0
	for c in chickens:
		if not c.targetable():
			continue
		var d: float = pos.distance_to(c.position)
		if d < best_d:
			best = c
			best_d = d
	return best

func nearest_chicken(pos: Vector3, radius: float):
	var best = null
	var best_d := radius
	for c in chickens:
		if c.state == "carried" or c.state == "in_coop":
			continue
		var d: float = pos.distance_to(c.position)
		if d < best_d:
			best = c
			best_d = d
	return best

# ---------------- chicken events ----------------

func _spawn_chicken(pos: Vector3, chick: bool) -> void:
	var c = ChickenScript.new()
	add_child(c)
	c.setup(self, pos, chick)
	chickens.append(c)

func chicken_died(c: Node3D) -> void:
	if not chickens.has(c):
		return
	chickens.erase(c)
	spawn_poof(c.position + Vector3(0, 0.4, 0), Color(0.95, 0.92, 0.85), 12)
	c.queue_free()
	ui.whisper("a chicken has fallen")
	ui.refresh()
	_check_game_over()

func chicken_taken(c: Node3D) -> void:
	if c == null or not chickens.has(c):
		return
	chickens.erase(c)
	c.queue_free()
	ui.whisper("a chicken was taken into the dark")
	ui.refresh()
	_check_game_over()

func forage_deposit(_c: Node3D) -> void:
	add_coins(2)
	sfx.play("coin", -12.0)

func _check_game_over() -> void:
	if chickens.is_empty() and started and not over:
		over = true
		paused = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if FileAccess.file_exists(SAVE_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		ui.show_game_over(day_num)

# ---------------- coop / player ----------------

func max_coop_hp() -> float:
	return 300.0 + 200.0 * float(upgrades.coop)

func damage_coop(n: float) -> void:
	coop_hp -= n
	sfx.play("hit", -8.0)
	if coop_hp <= 0.0 and not coop_broken:
		coop_broken = true
		coop_hp = 0.0
		ui.announce("THE ARMORY IS BREACHED", "the chickens are exposed!", true)
		for c in chickens:
			if c.state == "in_coop":
				c.visible = true
				c.position = coop_door + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
				c.state = "panic"

func repair_coop(delta: float) -> void:
	coop_hp = minf(max_coop_hp(), coop_hp + 35.0 * delta)
	if coop_broken and coop_hp > max_coop_hp() * 0.25:
		coop_broken = false
		ui.announce("ARMORY SECURED", "the flock breathes easier")

func damage_player(n: float) -> void:
	player.take_damage(n)

func player_downed() -> void:
	if over:
		return
	paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	ui.show_downed()
	await get_tree().create_timer(2.8).timeout
	if over:
		return
	coins = int(float(coins) * 0.85)
	player.hp = player.max_hp
	player.position = Vector3(-10, 0.1, 5)
	phase_t = 0.0
	_start_dawn()
	unpause()
	ui.refresh()

# ---------------- economy ----------------

func add_coins(n: int) -> void:
	coins += n
	ui.refresh()

func sell_eggs() -> void:
	if eggs <= 0:
		return
	add_coins(eggs * 6)
	eggs = 0
	sfx.play("coin")
	ui.refresh()
	ui.market_refresh()

func market_items() -> Array:
	var items := [
		{"id": "hen", "name": "LIVE HEN", "desc": "+1 hen, delivered instantly by drone. do not ask about the drone.", "price": 35, "owned": chickens.size() >= MAX_CHICKENS},
		{"id": "rooster", "name": "ROOSTER", "desc": "enables breeding. every dawn each hen has a chance to hatch a chick.", "price": 60, "owned": upgrades.rooster},
		{"id": "feed5", "name": "CHICKEN FEED x5", "desc": "throw it. a chicken will come eat it and heal 30 hp.", "price": 12, "owned": false},
		{"id": "shotgun", "name": "PUMP SHOTGUN", "desc": "the farmer's argument. includes 8 shells.", "price": 150, "owned": upgrades.shotgun},
		{"id": "shells8", "name": "SHELLS x8", "desc": "arguments, refilled.", "price": 20, "owned": false},
		{"id": "helmets", "name": "TINY WAR HELMETS", "desc": "hens fight at night instead of hiding. they have chosen violence.", "price": 120, "owned": upgrades.helmets},
		{"id": "turret", "name": "EGG TURRET", "desc": "automated yolk-based yard defense.", "price": 250, "owned": upgrades.turret},
		{"id": "shoes", "name": "RUNNING SHOES", "desc": "+25% farmer speed. they light up. tactically.", "price": 90, "owned": upgrades.shoes},
		{"id": "medkit", "name": "FIRST AID", "desc": "patch yourself back to full.", "price": 15, "owned": false},
	]
	if upgrades.fence < 3:
		items.append({"id": "fence", "name": "FENCE TIER %d" % (upgrades.fence + 1), "desc": "attackers waste %.1fs chewing through the fence." % (1.8 * float(upgrades.fence + 1)), "price": 80 * (upgrades.fence + 1), "owned": false})
	if upgrades.coop < 3:
		items.append({"id": "coop", "name": "ARMORY PLATING TIER %d" % (upgrades.coop + 1), "desc": "+200 coop hp. the wood remembers being a tree. now it is a wall.", "price": 100 * (upgrades.coop + 1), "owned": false})
	return items

func buy(id: String) -> void:
	var price := 0
	for item in market_items():
		if item.id == id:
			price = item.price
	if coins < price:
		sfx.play("denied")
		return
	match id:
		"hen":
			if chickens.size() >= MAX_CHICKENS:
				sfx.play("denied")
				return
			_spawn_chicken(rand_in_yard(), false)
		"rooster":
			upgrades.rooster = true
		"feed5":
			feed += 5
		"shotgun":
			upgrades.shotgun = true
			shells += 8
		"shells8":
			shells += 8
		"helmets":
			upgrades.helmets = true
		"turret":
			upgrades.turret = true
			_build_turret()
		"shoes":
			upgrades.shoes = true
		"medkit":
			player.hp = player.max_hp
		"fence":
			upgrades.fence += 1
			fence_mat.albedo_color = [Color(0.55, 0.4, 0.24), Color(0.5, 0.42, 0.35), Color(0.45, 0.45, 0.48), Color(0.3, 0.32, 0.4)][upgrades.fence]
		"coop":
			upgrades.coop += 1
			coop_hp = max_coop_hp()
	coins -= price
	sfx.play("buy")
	ui.refresh()
	ui.market_refresh()

func open_market() -> void:
	if over:
		return
	market_open = true
	paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	ui.open_market()

func close_market() -> void:
	market_open = false
	ui.close_market()
	paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# ---------------- environment / clock ----------------

func _update_environment() -> void:
	if is_night:
		var boss: bool = night_theme.get("boss", false)
		env.background_color = Color(0.1, 0.02, 0.04) if boss else Color(0.03, 0.04, 0.1)
		env.ambient_light_color = Color(0.3, 0.12, 0.15) if boss else Color(0.15, 0.19, 0.3)
		env.ambient_light_energy = 0.55
		env.fog_density = 0.010
		env.fog_light_color = Color(0.1, 0.02, 0.03) if boss else Color(0.02, 0.03, 0.08)
		sun.light_energy = 0.22
		sun.light_color = Color(0.6, 0.7, 1.0)
		sun.rotation = Vector3(-1.1, 0.5, 0)
	else:
		var ang := lerpf(0.1, 0.9, phase_t) * PI
		var elev := sin(ang)
		var day_sky := Color(0.5, 0.7, 0.9)
		var dusk_sky := Color(0.85, 0.48, 0.29)
		env.background_color = dusk_sky.lerp(day_sky, clampf(elev * 1.6, 0.0, 1.0))
		env.ambient_light_color = Color(0.8, 0.87, 0.95)
		env.ambient_light_energy = lerpf(0.5, 1.0, clampf(elev * 1.5, 0.0, 1.0))
		env.fog_density = 0.0008
		env.fog_light_color = env.background_color
		sun.light_energy = maxf(0.15, elev * 1.3)
		sun.light_color = Color(1.0, lerpf(0.6, 0.95, elev), lerpf(0.4, 0.9, elev))
		sun.rotation = Vector3(-ang, 0.5, 0)

func clock_text() -> String:
	var minutes: int
	if is_night:
		minutes = int(1200.0 + phase_t * 600.0) % 1440
	else:
		minutes = int(360.0 + phase_t * 840.0)
	var h := minutes / 60
	var m := minutes % 60
	var ampm := "a.m." if h < 12 else "p.m."
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	var txt := "Day %d   %d:%02d %s" % [day_num, h12, m, ampm]
	if is_night:
		txt += "   NIGHT"
	return txt

# ---------------- save / load ----------------

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func peek_save_day() -> int:
	if not has_save():
		return 1
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	if data == null:
		return 1
	return int(data.get("day", 1))

func _save_game() -> void:
	var hens := 0
	for c in chickens:
		hens += 1
	var data := {
		"coins": coins, "day": day_num, "eggs": eggs, "feed": feed, "shells": shells,
		"hens": hens, "coop_hp": coop_hp, "upgrades": upgrades,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))

func _load_game() -> void:
	if not has_save():
		start_new()
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	if data == null:
		start_new()
		return
	coins = int(data.get("coins", 25))
	day_num = int(data.get("day", 1))
	eggs = int(data.get("eggs", 0))
	feed = int(data.get("feed", 5))
	shells = int(data.get("shells", 0))
	coop_hp = float(data.get("coop_hp", 300.0))
	var loaded_upgrades = data.get("upgrades", {})
	for k in upgrades:
		if loaded_upgrades.has(k):
			upgrades[k] = loaded_upgrades[k]
	upgrades.fence = int(upgrades.fence)
	upgrades.coop = int(upgrades.coop)
	if upgrades.turret:
		_build_turret()
	var hens := int(data.get("hens", 10))
	for i in maxi(hens, 1):
		_spawn_chicken(rand_in_yard(), false)

# ---------------- automated screenshot test ----------------

func _run_shot_test(dir: String) -> void:
	start_new()
	await get_tree().create_timer(2.0).timeout
	await _shot(dir + "/day.png")
	player.rotation.y = PI  # face the gate
	phase_t = 1.0
	await get_tree().create_timer(6.0).timeout
	await _shot(dir + "/night.png")
	get_tree().quit()

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved shot: " + path)
