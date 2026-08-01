extends Node3D
## A Thing That Wants Your Chickens. Theme decides what it is tonight.

const MK = preload("res://scripts/meshkit.gd")

## Authored models, used in place of the procedural build when present.
const GOBLIN_MODEL_PATH := "res://models/goblin.glb"
## Measured from the source .glb: full height, and distance from origin down to the feet.
const GOBLIN_MODEL_HEIGHT := 1.903
const GOBLIN_MODEL_FOOT_OFFSET := 0.955
## Yaw correction so the model's face points along +Z like the procedural enemies.
const GOBLIN_MODEL_YAW := 180.0

const THEMES := [
	{"id": "zombie", "name": "THE SHUFFLING DEAD", "sub": "they smell the eggs", "body": Color(0.35, 0.49, 0.29), "eye": Color(1, 0.15, 0.15), "scale": 1.0, "speed": 2.2, "hp": 50.0, "dmg": 8.0, "bounty": 4, "base": 5.0, "per": 1.6},
	{"id": "goblin", "name": "THE GOBLIN GRAB-GANG", "sub": "quick little hands", "body": Color(0.29, 0.6, 0.25), "eye": Color(1, 0.9, 0.2), "scale": 0.75, "speed": 3.6, "hp": 30.0, "dmg": 5.0, "bounty": 3, "base": 6.0, "per": 2.0},
	{"id": "midget", "name": "FURIOUS MIDGET PEOPLE WITH STICKS", "sub": "so many sticks", "body": Color(0.54, 0.35, 0.17), "eye": Color(1, 1, 1), "scale": 0.6, "speed": 4.2, "hp": 22.0, "dmg": 4.0, "bounty": 3, "base": 8.0, "per": 2.4, "stick": true},
	{"id": "grey", "name": "THE GREY ONES", "sub": "they come for the yolk", "body": Color(0.6, 0.64, 0.68), "eye": Color(0.4, 0.88, 1), "scale": 0.9, "speed": 2.8, "hp": 45.0, "dmg": 7.0, "bounty": 5, "base": 4.0, "per": 1.4},
	{"id": "bones", "name": "THE RATTLING BONES", "sub": "calcium seeks calcium", "body": Color(0.85, 0.83, 0.75), "eye": Color(0.5, 1, 0.5), "scale": 1.0, "speed": 3.0, "hp": 35.0, "dmg": 6.0, "bounty": 4, "base": 6.0, "per": 1.8},
	{"id": "frost", "name": "THE FROST WALKERS", "sub": "winter wants chicken soup", "body": Color(0.62, 0.84, 0.91), "eye": Color(0.7, 0.95, 1), "scale": 1.15, "speed": 1.6, "hp": 120.0, "dmg": 12.0, "bounty": 8, "base": 3.0, "per": 1.0},
	{"id": "wolf", "name": "THE BIG BAD WOLF", "sub": "he huffed. he puffed.", "body": Color(0.3, 0.28, 0.3), "eye": Color(1, 0.3, 0.1), "scale": 2.2, "speed": 4.5, "hp": 400.0, "dmg": 20.0, "bounty": 60, "base": 1.0, "per": 0.0, "boss": true, "min_night": 4, "ears": true, "escort": 3},
	{"id": "bigfoot", "name": "BIGFOOT", "sub": "he is real and he is hungry", "body": Color(0.42, 0.3, 0.2), "eye": Color(1, 1, 0.6), "scale": 2.6, "speed": 3.0, "hp": 600.0, "dmg": 25.0, "bounty": 80, "base": 1.0, "per": 0.0, "boss": true, "min_night": 6},
	{"id": "dragon", "name": "A LITERAL DRAGON???", "sub": "of course it wants chicken", "body": Color(0.55, 0.15, 0.6), "eye": Color(1, 0.5, 0.1), "scale": 2.0, "speed": 5.0, "hp": 500.0, "dmg": 30.0, "bounty": 100, "base": 1.0, "per": 0.0, "boss": true, "min_night": 8, "flying": true, "wings": true},
]

static func pick_theme(night: int) -> Dictionary:
	var bosses := THEMES.filter(func(t): return t.get("boss", false) and night >= t.get("min_night", 99))
	var normals := THEMES.filter(func(t): return not t.get("boss", false))
	if night % 4 == 0 and bosses.size() > 0:
		return bosses[randi() % bosses.size()]
	return normals[randi() % normals.size()]

var game: Node3D
var theme := {}
var hp := 50.0
var max_hp := 50.0
var spd := 2.0
var body_scale := 1.0
var flying := false
# approach | chew | attack_coop | carry | burn
var state := "approach"
var carried = null
var entered := false
var _chew_t := 0.0
var _atk_cd := 0.0
var _retarget_t := 0.0
var _burn_t := 0.0
var _anim_t := 0.0
var _target_chicken = null
var _wings: Array = []
var _legs: Array = []
var _stride := 0.0
var _mats: Array = []

func setup(g: Node3D, night: int, thm: Dictionary, escort := false) -> void:
	game = g
	theme = thm.duplicate()
	if escort:
		theme["scale"] = thm["scale"] * 0.5
		theme["hp"] = 30.0
		theme["dmg"] = 5.0
		theme["bounty"] = 4
		theme["boss"] = false
		theme["flying"] = false
	body_scale = theme["scale"]
	var hp_mul := 1.0 + 0.13 * float(night - 1)
	hp = theme["hp"] * hp_mul
	max_hp = hp
	spd = theme["speed"] * randf_range(0.9, 1.1)
	flying = theme.get("flying", false)
	var ang := randf() * TAU
	position = Vector3(cos(ang), 0, sin(ang)) * 62.0
	if flying:
		position.y = 9.0
	_build_mesh()

func _build_mesh() -> void:
	if theme.get("id", "") == "goblin":
		_build_goblin()
		return
	if theme.get("id", "") == "dragon":
		_build_dragon()
		return
	var s: float = body_scale
	var body_c: Color = theme["body"]
	var eye_c: Color = theme["eye"]
	var body := MK.capsule(self, 0.42 * s, 1.5 * s, body_c, Vector3(0, 0.85 * s, 0))
	_mats.append(body.material_override)
	var head := MK.sphere(self, 0.3 * s, body_c.lightened(0.08), Vector3(0, 1.75 * s, 0.06 * s))
	_mats.append(head.material_override)
	MK.sphere(self, 0.06 * s, eye_c, Vector3(0.12 * s, 1.8 * s, 0.26 * s), true, 3.0)
	MK.sphere(self, 0.06 * s, eye_c, Vector3(-0.12 * s, 1.8 * s, 0.26 * s), true, 3.0)
	# arms
	MK.capsule(self, 0.1 * s, 0.8 * s, body_c.darkened(0.15), Vector3(0.5 * s, 1.1 * s, 0.1 * s)).rotation.x = deg_to_rad(-40)
	MK.capsule(self, 0.1 * s, 0.8 * s, body_c.darkened(0.15), Vector3(-0.5 * s, 1.1 * s, 0.1 * s)).rotation.x = deg_to_rad(-40)
	if theme.get("stick", false):
		MK.cyl(self, 0.03, 0.04, 1.2, Color(0.45, 0.3, 0.15), Vector3(0.55 * s, 1.3 * s, 0.4 * s)).rotation.x = deg_to_rad(-60)
	if theme.get("ears", false):
		MK.cyl(self, 0.0, 0.12 * s, 0.4 * s, body_c, Vector3(0.16 * s, 2.1 * s, 0))
		MK.cyl(self, 0.0, 0.12 * s, 0.4 * s, body_c, Vector3(-0.16 * s, 2.1 * s, 0))
	if theme.get("wings", false):
		for side in [-1.0, 1.0]:
			var w := MK.box(self, Vector3(1.8 * s, 0.06 * s, 0.7 * s), body_c.darkened(0.2), Vector3(side * 1.1 * s, 1.5 * s, -0.2 * s))
			_wings.append(w)

## A goblin: hunched, big-eared, grinning, armed with whatever it found.
## Size, skin, gear and headwear all vary per individual.
func _build_goblin() -> void:
	body_scale *= randf_range(0.85, 1.3)
	var s: float = body_scale
	# bigger goblins lumber, runts scurry
	spd *= lerpf(1.15, 0.82, clampf((s / theme["scale"] - 0.85) / 0.45, 0.0, 1.0))
	if ResourceLoader.exists(GOBLIN_MODEL_PATH):
		_build_goblin_model(s)
		return
	_build_goblin_procedural(s)

## The source .glb has no vertex normals, so lighting renders it black. Build the
## normals once with SurfaceTool and share the result across every goblin.
static var _goblin_mesh_cache: Mesh = null
static var _goblin_xform_cache := Transform3D.IDENTITY
static var _goblin_prepared := false

static func goblin_mesh() -> Mesh:
	if _goblin_prepared:
		return _goblin_mesh_cache
	_goblin_prepared = true
	if not ResourceLoader.exists(GOBLIN_MODEL_PATH):
		return null
	var root: Node3D = load(GOBLIN_MODEL_PATH).instantiate()
	var src: MeshInstance3D = _first_mesh(root)
	if src != null:
		_goblin_xform_cache = src.transform
		var st := SurfaceTool.new()
		st.create_from(src.mesh, 0)
		st.generate_normals()
		_goblin_mesh_cache = st.commit()
	root.free()
	return _goblin_mesh_cache

static func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var found := _first_mesh(c)
		if found != null:
			return found
	return null

## Authored goblin: scaled to gameplay height, dropped so the feet meet the ground,
## with a per-instance material so the damage flash only tints the one that got hit.
func _build_goblin_model(s: float) -> void:
	var mesh := goblin_mesh()
	if mesh == null:
		_build_goblin_procedural(s)
		return
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.transform = _goblin_xform_cache
	var holder := Node3D.new()
	holder.add_child(inst)
	# theme scale 0.75 should read as a ~1.5 m goblin
	var want_h := 1.5 * (s / float(theme["scale"]))
	var ms := want_h / GOBLIN_MODEL_HEIGHT
	holder.scale = Vector3.ONE * ms
	holder.position.y = GOBLIN_MODEL_FOOT_OFFSET * ms
	holder.rotation.y = deg_to_rad(GOBLIN_MODEL_YAW)
	add_child(holder)
	# The source .glb carries no UVs, vertex colors or texture (geometry-only
	# export), so skin it here. Triplanar mapping works without UVs.
	var skins := [
		Color(0.42, 0.60, 0.24), Color(0.34, 0.52, 0.22), Color(0.52, 0.66, 0.30),
		Color(0.26, 0.47, 0.29), Color(0.28, 0.55, 0.55),
	]
	var skin: Color = skins[randi() % skins.size()]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = skin
	mat.roughness = 0.8
	inst.set_surface_override_material(0, mat)
	_mats.append(mat)

func _mesh_children(n: Node) -> Array:
	var acc := []
	if n is MeshInstance3D:
		acc.append(n)
	for c in n.get_children():
		acc += _mesh_children(c)
	return acc

func _build_goblin_procedural(s: float) -> void:
	var skins := [
		Color(0.42, 0.60, 0.24), Color(0.34, 0.52, 0.22), Color(0.52, 0.66, 0.30),
		Color(0.26, 0.47, 0.29), Color(0.28, 0.55, 0.55),
	]
	var skin: Color = skins[randi() % skins.size()]
	var leather := Color(0.26, 0.21, 0.16)
	var metal := Color(0.38, 0.38, 0.42)
	var eye_c: Color = Color(1.0, 0.45, 0.06) if randf() < 0.7 else Color(1.0, 0.2, 0.12)

	# --- legs: hip-pivoted, bandy, big flat feet ---
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.17 * s, 0.6 * s, 0)
		add_child(hip)
		_legs.append(hip)
		MK.capsule(hip, 0.1 * s, 0.34 * s, skin.darkened(0.1), Vector3(0, -0.18 * s, 0))
		MK.capsule(hip, 0.08 * s, 0.28 * s, skin, Vector3(0, -0.45 * s, 0.02 * s))
		MK.box(hip, Vector3(0.19 * s, 0.07 * s, 0.3 * s), skin.darkened(0.2), Vector3(0, -0.585 * s, 0.06 * s))
	# loincloth / tattered kilt
	MK.cyl(self, 0.24 * s, 0.3 * s, 0.3 * s, leather, Vector3(0, 0.66 * s, 0))

	# --- hunched torso ---
	var torso := Node3D.new()
	torso.position = Vector3(0, 0.78 * s, 0)
	torso.rotation.x = deg_to_rad(16)  # the hunch
	add_child(torso)
	var chest := MK.capsule(torso, 0.28 * s, 0.5 * s, skin, Vector3(0, 0.2 * s, 0))
	chest.scale = Vector3(1.15, 1.0, 0.85)
	_mats.append(chest.material_override)
	# scavenged breastplate + belt + shoulder pauldrons
	var plate := MK.box(torso, Vector3(0.44 * s, 0.36 * s, 0.3 * s), metal, Vector3(0, 0.22 * s, 0.06 * s))
	_mats.append(plate.material_override)
	MK.box(torso, Vector3(0.52 * s, 0.09 * s, 0.34 * s), leather, Vector3(0, -0.04 * s, 0.02 * s))
	MK.box(torso, Vector3(0.1 * s, 0.1 * s, 0.36 * s), Color(0.55, 0.45, 0.2), Vector3(0, -0.04 * s, 0.06 * s))
	for side in [-1.0, 1.0]:
		var pauldron := MK.sphere(torso, 0.17 * s, metal.darkened(0.15), Vector3(side * 0.32 * s, 0.36 * s, 0))
		pauldron.scale = Vector3(1.0, 0.7, 1.0)

	# --- arms: long, hanging forward ---
	var hands := []
	for side in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(side * 0.3 * s, 0.34 * s, 0)
		sh.rotation.x = deg_to_rad(-28)
		sh.rotation.z = deg_to_rad(-side * 12.0)
		torso.add_child(sh)
		MK.capsule(sh, 0.085 * s, 0.34 * s, skin, Vector3(0, -0.19 * s, 0))
		MK.capsule(sh, 0.075 * s, 0.3 * s, skin.lightened(0.04), Vector3(0, -0.46 * s, 0.05 * s))
		var hand := Node3D.new()
		hand.position = Vector3(0, -0.64 * s, 0.08 * s)
		sh.add_child(hand)
		MK.sphere(hand, 0.09 * s, skin.darkened(0.08), Vector3.ZERO)
		hands.append(hand)
	_goblin_weapon(hands[1], s, metal)
	if randf() < 0.35:
		_goblin_weapon(hands[0], s, metal)

	# --- head: oversized, wide grin, glowing eyes ---
	var head := Node3D.new()
	head.position = Vector3(0, 0.62 * s, 0.06 * s)
	head.rotation.x = deg_to_rad(-16)  # counter the hunch so it looks forward
	torso.add_child(head)
	var skull := MK.sphere(head, 0.27 * s, skin, Vector3.ZERO)
	skull.scale = Vector3(0.95, 1.0, 1.05)
	_mats.append(skull.material_override)
	# jaw
	var jaw := MK.box(head, Vector3(0.3 * s, 0.16 * s, 0.24 * s), skin.darkened(0.06), Vector3(0, -0.18 * s, 0.09 * s))
	# huge pointed ears
	for side in [-1.0, 1.0]:
		var ear := MK.cyl(head, 0.0, 0.09 * s, 0.5 * s, skin.lightened(0.06), Vector3(side * 0.3 * s, 0.1 * s, -0.02 * s))
		ear.rotation.z = deg_to_rad(-side * 58.0)
		ear.rotation.x = deg_to_rad(-18)
		ear.scale = Vector3(1.0, 1.0, 0.45)
	# brow ridge -> permanent scowl
	for side in [-1.0, 1.0]:
		var brow := MK.box(head, Vector3(0.14 * s, 0.05 * s, 0.08 * s), skin.darkened(0.28), Vector3(side * 0.11 * s, 0.11 * s, 0.2 * s))
		brow.rotation.z = deg_to_rad(side * 16.0)
	# glowing eyes, deep-set
	for side in [-1.0, 1.0]:
		MK.sphere(head, 0.052 * s, eye_c, Vector3(side * 0.11 * s, 0.04 * s, 0.21 * s), true, 3.5)
		MK.sphere(head, 0.02 * s, Color(0.05, 0.02, 0.02), Vector3(side * 0.11 * s, 0.04 * s, 0.255 * s))
	# long hooked nose
	var nose := MK.cyl(head, 0.0, 0.055 * s, 0.2 * s, skin.darkened(0.05), Vector3(0, -0.03 * s, 0.26 * s))
	nose.rotation.x = deg_to_rad(108)
	# wide grin full of teeth
	MK.box(head, Vector3(0.26 * s, 0.075 * s, 0.06 * s), Color(0.12, 0.05, 0.06), Vector3(0, -0.145 * s, 0.21 * s))
	for i in 5:
		var tx := (float(i) - 2.0) * 0.052 * s
		var up := i % 2 == 0
		var tooth := MK.cyl(head, 0.0, 0.021 * s, 0.075 * s, Color(0.94, 0.92, 0.82), Vector3(tx, -0.15 * s + (0.02 * s if up else -0.02 * s), 0.225 * s))
		tooth.rotation.x = deg_to_rad(180 if up else 0)
	# headwear: pointed hood, scrap helm, or wild hair
	var roll := randf()
	if roll < 0.3:
		var hat := MK.cyl(head, 0.0, 0.24 * s, 0.42 * s, Color(0.55, 0.15, 0.14), Vector3(0, 0.26 * s, -0.02 * s))
		hat.rotation.x = deg_to_rad(-16)
	elif roll < 0.55:
		var helm := MK.sphere(head, 0.28 * s, metal.darkened(0.1), Vector3(0, 0.06 * s, 0))
		helm.scale = Vector3(1.0, 0.62, 1.0)
	elif roll < 0.8:
		var hair_c := Color(0.72, 0.28, 0.08) if randf() < 0.6 else Color(0.15, 0.12, 0.1)
		for i in 6:
			var tuft := MK.cyl(head, 0.0, 0.035 * s, randf_range(0.14, 0.26) * s, hair_c, Vector3(randf_range(-0.1, 0.1) * s, 0.24 * s, randf_range(-0.12, 0.04) * s))
			tuft.rotation.x = randf_range(-0.5, 0.2)
			tuft.rotation.z = randf_range(-0.5, 0.5)

## A proper dragon: serpentine neck, horned skull, membrane wings with finger
## struts, four clawed legs, spined back and a long spade-tipped tail.
func _build_dragon() -> void:
	var s: float = body_scale
	var schemes := [
		[Color(0.62, 0.11, 0.08), Color(0.88, 0.52, 0.14)],  # crimson / gold belly
		[Color(0.3, 0.09, 0.36), Color(0.62, 0.3, 0.7)],     # violet / orchid
		[Color(0.16, 0.16, 0.2), Color(0.55, 0.5, 0.35)],    # obsidian / bronze
	]
	var scheme: Array = schemes[randi() % schemes.size()]
	var hide: Color = scheme[0]
	var belly: Color = scheme[1]
	var horn := Color(0.22, 0.19, 0.2)
	var membrane: Color = hide.darkened(0.25)
	var eye_c: Color = Color(1.0, 0.78, 0.12)

	# --- barrel body ---
	var body := MK.sphere(self, 0.62 * s, hide, Vector3(0, 1.35 * s, 0))
	body.scale = Vector3(0.92, 0.86, 1.5)
	_mats.append(body.material_override)
	var chest := MK.sphere(self, 0.5 * s, hide, Vector3(0, 1.4 * s, 0.62 * s))
	chest.scale = Vector3(0.95, 0.9, 1.05)
	_mats.append(chest.material_override)
	# plated belly
	for i in 5:
		var bp := MK.box(self, Vector3(0.42 * s, 0.05 * s, 0.22 * s), belly, Vector3(0, 0.85 * s, (float(i) - 2.0) * 0.28 * s))
		bp.rotation.x = deg_to_rad(3)

	# --- serpentine neck: segments curving up and forward ---
	var neck_pts := []
	for i in 5:
		var t := float(i) / 4.0
		var p := Vector3(0, 1.55 * s + t * 0.95 * s, 0.95 * s + t * 0.95 * s)
		neck_pts.append(p)
		var seg := MK.sphere(self, lerpf(0.34, 0.19, t) * s, hide, p)
		seg.scale = Vector3(0.9, 0.9, 1.2)
		if i == 0:
			_mats.append(seg.material_override)
		# throat plates
		MK.box(self, Vector3(0.2 * s, 0.04 * s, 0.14 * s), belly, p + Vector3(0, -lerpf(0.28, 0.16, t) * s, 0.04 * s))

	# --- head ---
	var head := Node3D.new()
	head.position = Vector3(0, 2.55 * s, 1.98 * s)
	head.rotation.x = deg_to_rad(-14)
	add_child(head)
	var skull := MK.sphere(head, 0.24 * s, hide, Vector3.ZERO)
	skull.scale = Vector3(0.85, 0.85, 1.15)
	_mats.append(skull.material_override)
	# snout + lower jaw
	var snout := MK.box(head, Vector3(0.24 * s, 0.17 * s, 0.44 * s), hide, Vector3(0, -0.04 * s, 0.32 * s))
	snout.rotation.x = deg_to_rad(4)
	MK.box(head, Vector3(0.21 * s, 0.09 * s, 0.4 * s), hide.darkened(0.12), Vector3(0, -0.16 * s, 0.3 * s))
	MK.sphere(head, 0.03 * s, Color(0.1, 0.06, 0.06), Vector3(0.07 * s, 0.02 * s, 0.53 * s))
	MK.sphere(head, 0.03 * s, Color(0.1, 0.06, 0.06), Vector3(-0.07 * s, 0.02 * s, 0.53 * s))
	# fangs
	for i in 4:
		var fx := (0.075 if i % 2 == 0 else -0.075) * s
		var fz := (0.28 + float(i / 2) * 0.14) * s
		var fang := MK.cyl(head, 0.0, 0.028 * s, 0.13 * s, Color(0.95, 0.93, 0.85), Vector3(fx, -0.13 * s, fz))
		fang.rotation.x = deg_to_rad(180)
	# swept-back horns
	for side in [-1.0, 1.0]:
		var h1 := MK.cyl(head, 0.0, 0.06 * s, 0.62 * s, horn, Vector3(side * 0.15 * s, 0.18 * s, -0.22 * s))
		h1.rotation.x = deg_to_rad(52)
		h1.rotation.z = deg_to_rad(-side * 20.0)
		var h2 := MK.cyl(head, 0.0, 0.04 * s, 0.34 * s, horn.lightened(0.1), Vector3(side * 0.2 * s, 0.02 * s, -0.16 * s))
		h2.rotation.x = deg_to_rad(68)
		h2.rotation.z = deg_to_rad(-side * 42.0)
		# jaw frill spikes
		var jf := MK.cyl(head, 0.0, 0.03 * s, 0.2 * s, horn, Vector3(side * 0.19 * s, -0.1 * s, 0.02 * s))
		jf.rotation.z = deg_to_rad(-side * 65.0)
	# slit glowing eyes under a heavy brow
	for side in [-1.0, 1.0]:
		MK.sphere(head, 0.06 * s, eye_c, Vector3(side * 0.14 * s, 0.06 * s, 0.16 * s), true, 4.0)
		var pupil := MK.box(head, Vector3(0.012 * s, 0.07 * s, 0.02 * s), Color(0.06, 0.03, 0.02), Vector3(side * 0.14 * s, 0.06 * s, 0.215 * s))
		var brow := MK.box(head, Vector3(0.14 * s, 0.05 * s, 0.16 * s), hide.darkened(0.3), Vector3(side * 0.14 * s, 0.14 * s, 0.14 * s))
		brow.rotation.z = deg_to_rad(side * 12.0)

	# --- wings: shoulder pivots so the flap animation drives them ---
	for side in [-1.0, 1.0]:
		var wing := Node3D.new()
		wing.position = Vector3(side * 0.5 * s, 1.75 * s, 0.25 * s)
		add_child(wing)
		_wings.append(wing)
		# arm bone out to the wrist
		var arm := MK.capsule(wing, 0.08 * s, 1.0 * s, hide.darkened(0.1), Vector3(side * 0.5 * s, 0.18 * s, 0))
		arm.rotation.z = deg_to_rad(side * 78.0)
		arm.rotation.x = deg_to_rad(-8)
		# finger struts fanning back, with membrane panels between them
		var spread := [10.0, 34.0, 58.0, 82.0]
		for i in spread.size():
			var fl := lerpf(2.5, 1.5, float(i) / 3.0) * s
			var finger := MK.capsule(wing, 0.045 * s, fl, horn.lightened(0.05), Vector3.ZERO)
			finger.rotation.y = deg_to_rad(-side * spread[i])
			finger.rotation.z = deg_to_rad(side * 86.0)
			finger.position = Vector3(side * (0.95 + cos(deg_to_rad(spread[i])) * fl * 0.5) * s, 0.2 * s, -sin(deg_to_rad(spread[i])) * fl * 0.5 * s)
			if i > 0:
				var prev: float = spread[i - 1]
				var cur: float = spread[i]
				var mid: float = (prev + cur) * 0.5
				var ml := lerpf(2.4, 1.6, float(i) / 3.0) * s
				var panel := MK.box(wing, Vector3(ml * 1.05, 0.035 * s, ml * 0.95), membrane, Vector3.ZERO)
				panel.rotation.y = deg_to_rad(-side * mid)
				panel.rotation.z = deg_to_rad(side * 9.0)  # slight dihedral so it catches light
				panel.position = Vector3(side * (0.95 + cos(deg_to_rad(mid)) * ml * 0.45) * s, 0.2 * s, -sin(deg_to_rad(mid)) * ml * 0.45 * s)
		# leading-edge claw
		MK.cyl(wing, 0.0, 0.05 * s, 0.24 * s, horn, Vector3(side * 1.0 * s, 0.34 * s, 0.1 * s)).rotation.x = deg_to_rad(-30)

	# --- four clawed legs ---
	for pair in [[0.62, 0.42, 0.62], [-0.7, 0.5, 0.72]]:
		var lz: float = pair[0]
		var lx: float = pair[1]
		var thick: float = pair[2]
		for side in [-1.0, 1.0]:
			var hipn := Node3D.new()
			hipn.position = Vector3(side * lx * s, 1.05 * s, lz * s)
			add_child(hipn)
			_legs.append(hipn)
			MK.capsule(hipn, 0.16 * thick * s, 0.5 * s, hide, Vector3(side * 0.06 * s, -0.24 * s, 0))
			MK.capsule(hipn, 0.12 * thick * s, 0.46 * s, hide.darkened(0.08), Vector3(side * 0.1 * s, -0.7 * s, -0.04 * s))
			MK.box(hipn, Vector3(0.28 * s, 0.1 * s, 0.4 * s), hide.darkened(0.15), Vector3(side * 0.1 * s, -0.98 * s, 0.1 * s))
			for c in 3:
				var claw := MK.cyl(hipn, 0.0, 0.035 * s, 0.18 * s, horn.lightened(0.15), Vector3(side * 0.1 * s + (float(c) - 1.0) * 0.09 * s, -1.0 * s, 0.3 * s))
				claw.rotation.x = deg_to_rad(115)

	# --- tail: tapering segments with a spade tip ---
	var tail_n := 8
	for i in tail_n:
		var t := float(i) / float(tail_n - 1)
		var tz := -0.85 * s - t * 2.6 * s
		var ty := 1.3 * s - t * t * 0.75 * s
		var seg := MK.sphere(self, lerpf(0.4, 0.09, t) * s, hide, Vector3(0, ty, tz))
		seg.scale = Vector3(0.9, 0.9, 1.25)
		if i == tail_n - 1:
			var spade := MK.cyl(self, 0.0, 0.22 * s, 0.5 * s, membrane, Vector3(0, ty - 0.02 * s, tz - 0.3 * s))
			spade.rotation.x = deg_to_rad(-84)
			spade.scale = Vector3(1.0, 1.0, 0.35)

	# --- dorsal spines from skull to tail tip ---
	for i in 16:
		var t := float(i) / 15.0
		var sz: float
		var sy: float
		if t < 0.45:
			var u := t / 0.45
			sz = 1.9 * s - u * 1.05 * s
			sy = 2.4 * s - u * 0.55 * s
		else:
			var u2 := (t - 0.45) / 0.55
			sz = 0.85 * s - u2 * 3.4 * s
			sy = 1.85 * s - u2 * u2 * 0.72 * s
		var spike := MK.cyl(self, 0.0, lerpf(0.075, 0.03, absf(t - 0.35) * 1.4) * s, lerpf(0.34, 0.12, t) * s, horn.lightened(0.08), Vector3(0, sy, sz))
		spike.rotation.x = deg_to_rad(-18)

## Crude scavenged weapon in the given hand.
func _goblin_weapon(hand: Node3D, s: float, metal: Color) -> void:
	var wood := Color(0.34, 0.24, 0.15)
	match randi() % 4:
		0:  # notched cleaver
			MK.cyl(hand, 0.022 * s, 0.022 * s, 0.24 * s, wood, Vector3(0, -0.08 * s, 0))
			var blade := MK.box(hand, Vector3(0.045 * s, 0.5 * s, 0.13 * s), metal.lightened(0.2), Vector3(0, -0.42 * s, 0.02 * s))
			blade.rotation.x = deg_to_rad(-8)
		1:  # spear
			MK.cyl(hand, 0.02 * s, 0.024 * s, 1.15 * s, wood, Vector3(0, -0.3 * s, 0.1 * s)).rotation.x = deg_to_rad(24)
			var tip := MK.cyl(hand, 0.0, 0.05 * s, 0.24 * s, metal.lightened(0.25), Vector3(0, -0.78 * s, 0.42 * s))
			tip.rotation.x = deg_to_rad(204)
		2:  # hand axe
			MK.cyl(hand, 0.022 * s, 0.026 * s, 0.36 * s, wood, Vector3(0, -0.14 * s, 0))
			var head_a := MK.box(hand, Vector3(0.07 * s, 0.19 * s, 0.2 * s), metal, Vector3(0.02 * s, -0.3 * s, 0.06 * s))
			head_a.rotation.x = deg_to_rad(-12)
		3:  # rusty dagger
			MK.cyl(hand, 0.02 * s, 0.02 * s, 0.13 * s, leather_col(), Vector3(0, -0.05 * s, 0))
			MK.box(hand, Vector3(0.03 * s, 0.3 * s, 0.09 * s), metal.lightened(0.1), Vector3(0, -0.26 * s, 0.01 * s))

func leather_col() -> Color:
	return Color(0.26, 0.21, 0.16)

func tick(delta: float) -> void:
	_anim_t += delta
	_atk_cd -= delta
	for i in _wings.size():
		_wings[i].rotation.z = sin(_anim_t * 9.0) * 0.5 * (1 if i == 0 else -1)
	match state:
		"pose":
			return  # test-only: hold still for a portrait
		"burn":
			_burn_t -= delta
			scale = Vector3.ONE * maxf(0.01, _burn_t / 1.2)
			position.y -= delta * 0.5
			if _burn_t <= 0.0:
				game.remove_enemy(self, false)
			return
		"chew":
			_chew_t -= delta
			position += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.02
			if _chew_t <= 0.0:
				entered = true
				state = "approach"
			return
		"carry":
			var out := Vector3(position.x, 0, position.z).normalized()
			_move(out, spd * 1.15, delta)
			if carried != null and is_instance_valid(carried):
				carried.position = position + Vector3(0, 2.2 * body_scale, 0)
			if Vector3(position.x, 0, position.z).length() > 70.0:
				game.chicken_taken(carried)
				carried = null
				game.remove_enemy(self, false)
			return
	# --- approach / attack ---
	_retarget_t -= delta
	if _retarget_t <= 0.0:
		_retarget_t = 0.5
		_target_chicken = game.nearest_targetable_chicken(position)
	var dest: Vector3
	var attacking_coop := false
	if _target_chicken != null and is_instance_valid(_target_chicken) and _target_chicken.targetable():
		dest = _target_chicken.position
	else:
		_target_chicken = null
		dest = game.coop_door
		attacking_coop = true
	var flat_d := Vector3(dest.x - position.x, 0, dest.z - position.z)
	var dist := flat_d.length()
	# player swipe
	var pp: Vector3 = game.player.global_position
	if _atk_cd <= 0.0 and Vector3(pp.x - position.x, 0, pp.z - position.z).length() < 1.8 * body_scale:
		_atk_cd = 1.2
		game.damage_player(theme["dmg"])
	if attacking_coop:
		if dist < 2.6:
			if _atk_cd <= 0.0:
				_atk_cd = 1.0
				game.damage_coop(theme["dmg"] * 0.6)
				position += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.05
			return
	else:
		if dist < 1.2 * maxf(1.0, body_scale) and (not flying or position.y < 1.5):
			carried = _target_chicken
			carried.state = "carried"
			carried.visible = true
			state = "carry"
			game.sfx.play("grab")
			game.ui.whisper("IT HAS ONE OF YOUR CHICKENS")
			return
	var dir := flat_d.normalized()
	# fence pause: crossing into the yard costs time based on fence tier
	if not entered and not flying:
		var next := position + dir * spd * delta
		if game.in_yard(next.x, next.z):
			if game.in_gate(next.x, next.z) or game.upgrades.fence <= 0:
				entered = true
			else:
				state = "chew"
				_chew_t = 1.8 * float(game.upgrades.fence)
				return
	_move(dir, spd, delta)
	if flying:
		var want_y := 9.0
		if dist < 6.0:
			want_y = 1.0
		position.y = lerpf(position.y, want_y, delta * 2.0)
	else:
		position.y = absf(sin(_anim_t * 8.0)) * 0.06 * body_scale

func _move(dir: Vector3, speed: float, delta: float) -> void:
	position += dir * speed * delta
	if dir.length() > 0.01:
		rotation.y = atan2(dir.x, dir.z)
	# walkers with jointed legs stride; everything else keeps the simple bob
	if not _legs.is_empty() and not flying:
		_stride += delta * speed * 3.4
		var swing := sin(_stride) * 0.5
		for i in _legs.size():
			_legs[i].rotation.x = swing * (1.0 if i % 2 == 0 else -1.0)

func ignite() -> void:
	if state == "burn":
		return
	state = "burn"
	_burn_t = 1.2
	for m in _mats:
		m.emission_enabled = true
		m.emission = Color(1.0, 0.45, 0.1)
		m.emission_energy_multiplier = 2.0
	if carried != null and is_instance_valid(carried):
		carried.state = "to_coop"
		carried = null

func damage(n: float) -> void:
	if state == "burn":
		return
	hp -= n
	for m in _mats:
		m.emission_enabled = true
		m.emission = Color(1, 1, 1)
		m.emission_energy_multiplier = 1.2
	var tw := create_tween()
	tw.tween_interval(0.08)
	tw.tween_callback(func():
		for m in _mats:
			m.emission_enabled = false)
	game.sfx.play("hit", -6.0)
	if hp <= 0.0:
		if carried != null and is_instance_valid(carried):
			carried.state = "to_coop"
			carried.position.y = 0.0
			carried = null
		game.remove_enemy(self, true)
