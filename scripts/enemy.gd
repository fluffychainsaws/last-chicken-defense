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

## Themes with a body of their own rather than the shared placeholder. The first
## few nights draw only from these, so a new player meets the ones that actually
## look like something before the generic capsules turn up.
const FEATURED := ["goblin", "midget"]
const FEATURED_NIGHTS := 3

static func pick_theme(night: int) -> Dictionary:
	var bosses := THEMES.filter(func(t): return t.get("boss", false) and night >= t.get("min_night", 99))
	var normals := THEMES.filter(func(t): return not t.get("boss", false))
	if night % 4 == 0 and bosses.size() > 0:
		return bosses[randi() % bosses.size()]
	if night <= FEATURED_NIGHTS:
		var featured := normals.filter(func(t): return t["id"] in FEATURED)
		if featured.size() > 0:
			return featured[randi() % featured.size()]
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
## Knees and shoulders, paired by index with _legs where both exist. Kept out of
## the mesh merge so they can still articulate; _arm_rest holds each shoulder's
## built-in pose so the swing is added to it rather than replacing it.
var _knees: Array = []
var _arms: Array = []
var _arm_rest: Array = []
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
	if theme.get("id", "") == "midget":
		_build_midget()
		return
	if theme.get("id", "") == "frost":
		_build_frost()
		return
	if theme.get("id", "") == "grey":
		_build_grey()
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
	# the authored mesh is ~335k verts; a browser can't carry a wave of them
	if ResourceLoader.exists(GOBLIN_MODEL_PATH) and not OS.has_feature("web"):
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

## Skin maps are identical across a whole wave, so build each set once and share
## it. The materials that use them stay per-instance — a shared material would
## make one enemy taking a shotgun blast flash every other one on the map.
static var _skin_cache := {}

## albedo_freq low = broad blotchy mottling; normal_freq higher = finer bumps.
static func skin_maps(key: String, albedo_seed: int, albedo_freq: float, normal_seed: int, normal_freq: float) -> Array:
	if not _skin_cache.has(key):
		_skin_cache[key] = [
			MK.noise_tex(albedo_seed, albedo_freq, 4, false, 0.55),
			MK.noise_tex(normal_seed, normal_freq, 4, true),
		]
	return _skin_cache[key]

## Furious midget people: squat, greasy, mostly eyes and teeth. Built as a
## bottom-heavy lump — no neck, tiny arms, stubby legs — so the silhouette reads
## as a fat little monster rather than a shrunken person. Colour, horns, spikes,
## warts and wonky eye sizes all roll per individual so a wave of thirty doesn't
## look like one model stamped thirty times.
func _build_midget() -> void:
	body_scale *= randf_range(0.82, 1.22)
	var s: float = body_scale
	# runts scurry, the bloated ones waddle
	spd *= lerpf(1.18, 0.85, clampf((s / float(theme["scale"]) - 0.82) / 0.4, 0.0, 1.0))
	# A late wave is ~30 of these at once. Each one is its own pile of draw calls,
	# so the browser build drops the pea-sized details that cost a call apiece and
	# read as nothing at gameplay distance.
	var detail := not OS.has_feature("web")

	var hides := [
		Color(0.34, 0.50, 0.42), Color(0.28, 0.42, 0.48), Color(0.46, 0.48, 0.30),
		Color(0.50, 0.38, 0.28), Color(0.38, 0.34, 0.44), Color(0.53, 0.50, 0.36),
	]
	var hide: Color = hides[randi() % hides.size()]
	var horn_c := Color(0.80, 0.74, 0.58)
	var tooth_c := Color(0.94, 0.91, 0.79)
	var irises := [
		Color(0.95, 0.78, 0.15), Color(0.55, 0.85, 0.30),
		Color(0.35, 0.75, 0.95), Color(0.95, 0.55, 0.15),
	]
	var iris_c: Color = irises[randi() % irises.size()]

	var maps := skin_maps("midget", 7717, 0.05, 4242, 0.16)
	var skin := MK.oily_mat(hide, maps[0], maps[1], 2.2, 0.18, true)
	var belly := MK.oily_mat(hide.lightened(0.28), maps[0], maps[1], 2.6, 0.18, true)
	# horn and claw keratin: still wet-looking, but harder and less mottled
	var keratin := MK.oily_mat(horn_c, null, null, 1.0, 0.22)
	_mats.append(skin)
	_mats.append(belly)
	_mats.append(keratin)

	# --- legs: short, thick, splayed out under the gut ---
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.22 * s, 0.42 * s, 0)
		add_child(hip)
		_legs.append(hip)
		var thigh := MK.skinned(hip, MK.sphere_mesh(0.17 * s), skin, Vector3(0, -0.12 * s, 0))
		thigh.scale = Vector3(1.0, 1.25, 1.0)
		# everything below the knee rides its own joint so the leg can fold
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.26 * s, 0)
		hip.add_child(knee)
		_knees.append(knee)
		MK.skinned(knee, MK.sphere_mesh(0.13 * s), skin, Vector3(0, -0.06 * s, 0.01 * s))
		# splayed three-toed foot
		var foot := MK.skinned(knee, MK.sphere_mesh(0.15 * s), skin, Vector3(0, -0.16 * s, 0.05 * s))
		foot.scale = Vector3(1.1, 0.55, 1.35)
		if detail:
			for t in 3:
				var claw := MK.skinned(knee, MK.cone_mesh(0.035 * s, 0.11 * s), keratin,
					Vector3((float(t) - 1.0) * 0.075 * s, -0.18 * s, 0.19 * s))
				claw.rotation.x = deg_to_rad(72)

	# --- body: one big pear, widest low, leaning back over the legs ---
	var torso := Node3D.new()
	torso.position = Vector3(0, 0.5 * s, 0)
	torso.rotation.x = deg_to_rad(-7)
	add_child(torso)
	var gut := MK.skinned(torso, MK.sphere_mesh(0.44 * s, 24, 12), skin, Vector3(0, 0.34 * s, 0))
	gut.scale = Vector3(1.06, 0.98, 0.92)
	var chest := MK.skinned(torso, MK.sphere_mesh(0.36 * s, 24, 12), skin, Vector3(0, 0.66 * s, 0.02 * s))
	chest.scale = Vector3(1.0, 0.86, 0.9)
	# pale underbelly, pushed forward so it catches light separately from the back
	var paunch := MK.skinned(torso, MK.sphere_mesh(0.34 * s, 24, 12), belly, Vector3(0, 0.3 * s, 0.16 * s))
	paunch.scale = Vector3(0.96, 1.0, 0.72)

	# --- warts: scattered lumps that break up the silhouette ---
	# sampled on the gut ellipsoid itself, so they sit in the skin rather than
	# hovering off it
	for i in (randi_range(6, 11) if detail else 0):
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(-0.7, 1.0), randf_range(-1.0, 1.0)).normalized()
		var on_gut := Vector3(0, 0.34 * s, 0) + Vector3(dir.x * 1.06, dir.y * 0.98, dir.z * 0.92) * 0.42 * s
		var wart := MK.skinned(torso, MK.sphere_mesh(randf_range(0.02, 0.045) * s), skin, on_gut)
		wart.scale = Vector3(1.0, 0.7, 1.0)

	# --- back spines ---
	if randf() < 0.75:
		for i in randi_range(3, 5):
			var t := float(i) / 4.0
			var spike := MK.skinned(torso, MK.cone_mesh(0.045 * s, randf_range(0.12, 0.2) * s), keratin,
				Vector3(0, (0.28 + t * 0.42) * s, (-0.36 + t * 0.1) * s))
			spike.rotation.x = deg_to_rad(-28)

	# --- arms: stubby, hanging off the sides of the gut ---
	var hands := []
	for side in [-1.0, 1.0]:
		var sh := Node3D.new()
		# swung out and forward, clear of the gut, or the arms vanish behind it
		sh.position = Vector3(side * 0.44 * s, 0.62 * s, 0.08 * s)
		sh.rotation.x = deg_to_rad(-30)
		sh.rotation.z = deg_to_rad(-side * 40.0)
		torso.add_child(sh)
		_arms.append(sh)
		_arm_rest.append(sh.rotation.x)
		MK.skinned(sh, MK.sphere_mesh(0.11 * s), skin, Vector3(0, -0.1 * s, 0)).scale = Vector3(1.0, 1.3, 1.0)
		MK.skinned(sh, MK.sphere_mesh(0.085 * s), skin, Vector3(0, -0.27 * s, 0.02 * s))
		var hand := Node3D.new()
		hand.position = Vector3(0, -0.36 * s, 0.03 * s)
		sh.add_child(hand)
		MK.skinned(hand, MK.sphere_mesh(0.09 * s), skin, Vector3.ZERO)
		if detail:
			for f in 3:
				var nail := MK.skinned(hand, MK.cone_mesh(0.022 * s, 0.08 * s), keratin,
					Vector3((float(f) - 1.0) * 0.05 * s, -0.05 * s, 0.05 * s))
				nail.rotation.x = deg_to_rad(150)
		hands.append(hand)

	# --- head: sunk into the shoulders, no neck ---
	var head := Node3D.new()
	head.position = Vector3(0, 0.92 * s, 0.03 * s)
	head.rotation.x = deg_to_rad(7)  # counter the torso lean so it faces level
	torso.add_child(head)
	# skull radius drives every feature position below: anything meant to be seen
	# has to sit at or beyond the surface, or it renders buried inside the head
	var hr := 0.32 * s
	var skull := MK.skinned(head, MK.sphere_mesh(hr, 24, 12), skin, Vector3.ZERO)
	skull.scale = Vector3(1.1, 0.94, 1.0)
	# heavy brow shelf, pulled back and up so it frames the eyes without hiding them
	var brow := MK.skinned(head, MK.sphere_mesh(0.26 * s), skin, Vector3(0, 0.19 * s, 0.1 * s))
	brow.scale = Vector3(1.18, 0.38, 0.92)

	# --- eyes: enormous and bulging clear of the skull, glossy, mismatched ---
	var eye_r := randf_range(0.15, 0.185) * s
	var eye_white := MK.oily_mat(Color(0.93, 0.93, 0.88), null, null, 1.0, 0.06)
	for side in [-1.0, 1.0]:
		# a touch of asymmetry per eye keeps the face from reading as machined
		var r := eye_r * randf_range(0.88, 1.12)
		var ex: float = side * 0.155 * s
		var ey := 0.03 * s
		# centred near the surface so most of the ball stands proud of the face
		var ez := hr * 0.72
		MK.skinned(head, MK.sphere_mesh(r, 20, 10), eye_white, Vector3(ex, ey, ez))
		var iris := MK.oily_mat(iris_c, null, null, 1.0, 0.05)
		MK.skinned(head, MK.sphere_mesh(r * 0.58), iris, Vector3(ex, ey, ez + r * 0.6))
		MK.add_mesh(head, MK.sphere_mesh(r * 0.28), Color(0.03, 0.02, 0.03),
			Vector3(ex, ey, ez + r * 0.82))
		# specular catchlight — the single cheapest cue that a surface is wet
		if detail:
			MK.add_mesh(head, MK.sphere_mesh(r * 0.13), Color(1, 1, 1),
				Vector3(ex + r * 0.3, ey + r * 0.34, ez + r * 0.86), true, 2.4)
		# heavy lid sliced across the top of the eyeball
		var lid := MK.skinned(head, MK.sphere_mesh(r * 1.08), skin, Vector3(ex, ey + r * 0.62, ez - r * 0.1))
		lid.scale = Vector3(1.0, 0.5, 1.0)

	# --- mouth: a wide gash across the lower face, teeth standing proud of it ---
	var my := -0.195 * s
	# half-width of the skull at mouth height, so the maw lands on the surface
	var mz := sqrt(maxf(hr * hr - my * my, 0.0))
	# kept shallow in Z: a deep maw sphere bulges out past the teeth and eats them
	var maw := MK.add_mesh(head, MK.sphere_mesh(0.23 * s), Color(0.30, 0.07, 0.10),
		Vector3(0, my, mz * 0.75))
	maw.scale = Vector3(1.3, 0.44, 0.4)
	var n_teeth := randi_range(5, 7)
	for i in n_teeth:
		var tx := (float(i) - float(n_teeth - 1) * 0.5) * 0.082 * s
		var jitter := randf_range(0.85, 1.4)
		# teeth have to clear mz — the skull surface at mouth height — or they
		# render inside the head. Upper fangs point down, lower ones up, and
		# nothing lines up.
		var upper := MK.skinned(head, MK.cone_mesh(0.032 * s, 0.115 * s * jitter), keratin,
			Vector3(tx, my + 0.06 * s, mz * 1.15))
		upper.rotation.x = deg_to_rad(180)
		upper.rotation.z = deg_to_rad(randf_range(-10, 10))
		if randf() < 0.75:
			var lower := MK.skinned(head, MK.cone_mesh(0.027 * s, 0.09 * s * jitter), keratin,
				Vector3(tx + 0.035 * s, my - 0.07 * s, mz * 1.13))
			lower.rotation.z = deg_to_rad(randf_range(-10, 10))
	# lower lip, kept small and low so it frames the teeth instead of hiding them
	var lip := MK.skinned(head, MK.sphere_mesh(0.15 * s), belly, Vector3(0, my - 0.135 * s, mz * 0.72))
	lip.scale = Vector3(1.2, 0.45, 0.5)

	# --- horns: curved pair, or a crown of little spikes ---
	if randf() < 0.7:
		for side in [-1.0, 1.0]:
			var base := Vector3(side * 0.17 * s, 0.24 * s, -0.02 * s)
			# two tapering segments, the upper one kicked outward, reads as a curve
			var h1 := MK.skinned(head, MK.cone_mesh(0.072 * s, 0.24 * s), keratin, base)
			h1.rotation.z = deg_to_rad(-side * 18.0)
			var h2 := MK.skinned(head, MK.cone_mesh(0.05 * s, 0.26 * s), keratin,
				base + Vector3(side * 0.1 * s, 0.21 * s, 0))
			h2.rotation.z = deg_to_rad(-side * 48.0)
	else:
		for i in randi_range(4, 6):
			var ang := PI * (float(i) / 5.0) - PI * 0.5
			var spike := MK.skinned(head, MK.cone_mesh(0.028 * s, randf_range(0.07, 0.13) * s), keratin,
				Vector3(sin(ang) * 0.2 * s, 0.26 * s, cos(ang) * 0.12 * s - 0.02 * s))
			spike.rotation.x = deg_to_rad(-14)

	# --- the stick. it is their whole thing. ---
	if theme.get("stick", false):
		var wood := Color(0.34, 0.23, 0.13)
		# a holder carries the tilt, so the shaft and its knots share one local
		# axis — placing the knots in hand space leaves them floating in mid-air
		var club := Node3D.new()
		club.position = Vector3(0, -0.02 * s, 0.05 * s)
		# raised and canted forward so the stick clears the body in silhouette
		club.rotation.x = deg_to_rad(-58)
		club.rotation.z = deg_to_rad(randf_range(-14, 14))
		hands[1].add_child(club)
		var length := randf_range(0.9, 1.2) * s
		MK.cyl(club, 0.022 * s, 0.032 * s, length, wood, Vector3(0, length * 0.42, 0))
		# knots and a heavier business end, so it reads as torn off a tree
		MK.sphere(club, 0.055 * s, wood.darkened(0.1), Vector3(0, length * 0.9, 0))
		if randf() < 0.5:
			MK.sphere(club, 0.03 * s, wood.lightened(0.08), Vector3(0.02 * s, length * 0.6, 0))
	_batch_body()

## Batch a finished procedural body. Each animated joint collapses on its own so
## it can still swing, then everything static collapses together. Purely a
## draw-call saving — the geometry is unchanged.
func _batch_body() -> void:
	for knee in _knees:
		MK.merge(knee)
	for hip in _legs:
		MK.merge(hip, _knees)
	for arm in _arms:
		MK.merge(arm)
	MK.merge(self, _legs + _arms)

## Frost walkers: the slow tanky wave, so they need to read as heavy. A hulking
## hunched slab, wider at the shoulders than the hips, crusted over with rime and
## sprouting ice off its back. Everything about the build says "hard to move".
func _build_frost() -> void:
	body_scale *= randf_range(0.9, 1.15)
	var s: float = body_scale
	var detail := not OS.has_feature("web")

	var hides := [
		Color(0.44, 0.66, 0.80), Color(0.52, 0.74, 0.84),
		Color(0.38, 0.58, 0.76), Color(0.58, 0.78, 0.86),
	]
	var hide: Color = hides[randi() % hides.size()]
	var rime := Color(0.88, 0.95, 0.99)
	var eye_c := Color(0.7, 0.95, 1.0)

	var maps := skin_maps("frost", 3311, 0.07, 9182, 0.24)
	# frozen hide: wet-ice specular over a cracked normal
	var skin := MK.oily_mat(hide, maps[0], maps[1], 1.6, 0.14, true)
	# ice itself is smoother and brighter than the flesh under it
	var ice := MK.oily_mat(rime, null, null, 1.0, 0.05)
	_mats.append(skin)
	_mats.append(ice)

	# --- legs: short and thick, planted wide ---
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.26 * s, 0.72 * s, 0)
		add_child(hip)
		_legs.append(hip)
		MK.skinned(hip, MK.sphere_mesh(0.19 * s, 20, 10), skin, Vector3(0, -0.2 * s, 0)).scale = Vector3(1.0, 1.5, 1.0)
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.4 * s, 0)
		hip.add_child(knee)
		_knees.append(knee)
		MK.skinned(knee, MK.sphere_mesh(0.16 * s), skin, Vector3(0, -0.1 * s, 0.01 * s)).scale = Vector3(1.0, 1.3, 1.0)
		var foot := MK.skinned(knee, MK.sphere_mesh(0.17 * s), skin, Vector3(0, -0.28 * s, 0.06 * s))
		foot.scale = Vector3(1.1, 0.5, 1.5)

	# --- torso: heavy slab, hunched forward, broad at the shoulders ---
	var torso := Node3D.new()
	torso.position = Vector3(0, 0.72 * s, 0)
	torso.rotation.x = deg_to_rad(13)
	add_child(torso)
	var gut := MK.skinned(torso, MK.sphere_mesh(0.36 * s, 24, 12), skin, Vector3(0, 0.16 * s, 0))
	gut.scale = Vector3(1.15, 1.05, 0.85)
	var chest := MK.skinned(torso, MK.sphere_mesh(0.42 * s, 24, 12), skin, Vector3(0, 0.5 * s, 0))
	chest.scale = Vector3(1.35, 1.0, 0.9)

	# --- rime: pale crust clinging to the upper surfaces ---
	if detail:
		for i in randi_range(7, 12):
			var dir := Vector3(randf_range(-1.0, 1.0), randf_range(0.0, 1.0), randf_range(-1.0, 1.0)).normalized()
			var on := Vector3(0, 0.42 * s, 0) + Vector3(dir.x * 1.3, dir.y * 1.0, dir.z * 0.88) * 0.4 * s
			var crust := MK.skinned(torso, MK.sphere_mesh(randf_range(0.05, 0.1) * s), ice, on)
			crust.scale = Vector3(1.0, 0.45, 1.0)

	# --- ice shards off the back and shoulders ---
	for i in randi_range(4, 7):
		var side := 1.0 if i % 2 == 0 else -1.0
		var shard := MK.skinned(torso, MK.cone_mesh(randf_range(0.05, 0.09) * s, randf_range(0.3, 0.55) * s), ice,
			Vector3(side * randf_range(0.1, 0.45) * s, randf_range(0.35, 0.72) * s, -0.28 * s))
		shard.rotation.x = deg_to_rad(randf_range(-42, -18))
		shard.rotation.z = deg_to_rad(-side * randf_range(10, 34))

	# --- arms: long and heavy, hanging low ---
	for side in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(side * 0.5 * s, 0.56 * s, 0)
		sh.rotation.x = deg_to_rad(-14)
		sh.rotation.z = deg_to_rad(-side * 9.0)
		torso.add_child(sh)
		_arms.append(sh)
		_arm_rest.append(sh.rotation.x)
		MK.skinned(sh, MK.sphere_mesh(0.15 * s, 20, 10), skin, Vector3(0, -0.2 * s, 0)).scale = Vector3(1.0, 1.7, 1.0)
		MK.skinned(sh, MK.sphere_mesh(0.13 * s), skin, Vector3(0, -0.56 * s, 0.03 * s)).scale = Vector3(1.0, 1.5, 1.0)
		MK.skinned(sh, MK.sphere_mesh(0.15 * s), skin, Vector3(0, -0.82 * s, 0.04 * s))
		# icicles hanging off the forearm
		if detail:
			for k in 3:
				var ic := MK.skinned(sh, MK.cone_mesh(0.028 * s, randf_range(0.12, 0.22) * s), ice,
					Vector3(side * 0.09 * s, -0.6 * s + float(k) * 0.09 * s, 0))
				ic.rotation.x = deg_to_rad(180)

	# --- head: sunk between the shoulders, brow heavy with ice ---
	var head := Node3D.new()
	head.position = Vector3(0, 0.86 * s, 0.04 * s)
	head.rotation.x = deg_to_rad(-13)
	torso.add_child(head)
	var hr := 0.26 * s
	var skull := MK.skinned(head, MK.sphere_mesh(hr, 24, 12), skin, Vector3.ZERO)
	skull.scale = Vector3(1.0, 1.05, 1.05)
	# A ridge over the eyes, not a cap on the crown — sat forward and low, or it
	# reads as a hat perched on a blue lump.
	# Hide-coloured, not ice: a white disc across the face reads as a visor no
	# matter where it sits. The rime on top of it does the "frozen" work instead.
	var brow := MK.skinned(head, MK.sphere_mesh(0.19 * s), skin, Vector3(0, 0.06 * s, hr * 0.46))
	brow.scale = Vector3(1.2, 0.42, 0.72)
	if detail:
		for i in 3:
			var frost_bit := MK.skinned(head, MK.sphere_mesh(randf_range(0.03, 0.055) * s), ice,
				Vector3((float(i) - 1.0) * 0.09 * s, 0.15 * s, hr * 0.36))
			frost_bit.scale = Vector3(1.0, 0.5, 1.0)
	# eyes: glowing slits set deep under that ridge, proud of the skull surface
	for side in [-1.0, 1.0]:
		var ex: float = side * 0.11 * s
		var eye := MK.add_mesh(head, MK.sphere_mesh(0.062 * s), eye_c, Vector3(ex, -0.03 * s, hr * 0.92), true, 5.0)
		eye.scale = Vector3(1.6, 0.7, 1.0)
	# jaw crusted with frozen teeth
	var jaw := MK.skinned(head, MK.sphere_mesh(0.19 * s), skin, Vector3(0, -0.17 * s, hr * 0.5))
	jaw.scale = Vector3(1.05, 0.6, 0.9)
	if detail:
		for i in 4:
			var tx := (float(i) - 1.5) * 0.06 * s
			var fang := MK.skinned(head, MK.cone_mesh(0.022 * s, 0.09 * s), ice, Vector3(tx, -0.11 * s, hr * 0.95))
			fang.rotation.x = deg_to_rad(180)
	_batch_body()

## The grey ones: the classic abductor build — spindly limbs, no bulk anywhere,
## and a cranium far too big for the body, so the whole silhouette is top-heavy.
## Waxy rather than wet: same low roughness as the others but no mottling.
func _build_grey() -> void:
	body_scale *= randf_range(0.92, 1.1)
	var s: float = body_scale
	var detail := not OS.has_feature("web")

	var hides := [
		Color(0.60, 0.64, 0.68), Color(0.66, 0.68, 0.66),
		Color(0.55, 0.60, 0.66), Color(0.70, 0.72, 0.70),
	]
	var hide: Color = hides[randi() % hides.size()]
	var eye_c := Color(0.4, 0.88, 1.0)

	# no texture: their whole look is smooth, featureless and slightly waxy
	var skin := MK.oily_mat(hide, null, null, 1.0, 0.32, true)
	var eye_mat := MK.oily_mat(Color(0.03, 0.03, 0.05), null, null, 1.0, 0.04)
	_mats.append(skin)

	# --- legs: thin, slightly bowed ---
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.11 * s, 0.78 * s, 0)
		add_child(hip)
		_legs.append(hip)
		MK.skinned(hip, MK.sphere_mesh(0.07 * s), skin, Vector3(0, -0.2 * s, 0)).scale = Vector3(1.0, 2.8, 1.0)
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.4 * s, 0)
		hip.add_child(knee)
		_knees.append(knee)
		MK.skinned(knee, MK.sphere_mesh(0.055 * s), skin, Vector3(0, -0.16 * s, 0.01 * s)).scale = Vector3(1.0, 2.6, 1.0)
		var foot := MK.skinned(knee, MK.sphere_mesh(0.07 * s), skin, Vector3(0, -0.36 * s, 0.04 * s))
		foot.scale = Vector3(0.9, 0.5, 1.6)

	# --- torso: narrow, slight ribcage taper, no mass ---
	var torso := Node3D.new()
	torso.position = Vector3(0, 0.78 * s, 0)
	torso.rotation.x = deg_to_rad(5)
	add_child(torso)
	var belly := MK.skinned(torso, MK.sphere_mesh(0.15 * s, 20, 10), skin, Vector3(0, 0.1 * s, 0))
	belly.scale = Vector3(1.15, 1.35, 0.8)
	var chest := MK.skinned(torso, MK.sphere_mesh(0.17 * s, 20, 10), skin, Vector3(0, 0.36 * s, 0))
	chest.scale = Vector3(1.3, 1.2, 0.78)

	# --- arms: very long, reaching past the knee ---
	for side in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(side * 0.19 * s, 0.44 * s, 0)
		sh.rotation.x = deg_to_rad(-10)
		sh.rotation.z = deg_to_rad(-side * 7.0)
		torso.add_child(sh)
		_arms.append(sh)
		_arm_rest.append(sh.rotation.x)
		MK.skinned(sh, MK.sphere_mesh(0.055 * s), skin, Vector3(0, -0.2 * s, 0)).scale = Vector3(1.0, 3.2, 1.0)
		MK.skinned(sh, MK.sphere_mesh(0.045 * s), skin, Vector3(0, -0.58 * s, 0.02 * s)).scale = Vector3(1.0, 3.0, 1.0)
		var hand := Node3D.new()
		hand.position = Vector3(0, -0.82 * s, 0.02 * s)
		sh.add_child(hand)
		MK.skinned(hand, MK.sphere_mesh(0.05 * s), skin, Vector3.ZERO).scale = Vector3(0.8, 1.1, 0.5)
		# three long fingers
		if detail:
			for f in 3:
				var fin := MK.skinned(hand, MK.sphere_mesh(0.018 * s), skin,
					Vector3((float(f) - 1.0) * 0.035 * s, -0.09 * s, 0))
				fin.scale = Vector3(1.0, 3.4, 1.0)

	# --- head: the whole point. Huge swollen cranium on a thin neck. ---
	MK.skinned(torso, MK.sphere_mesh(0.045 * s), skin, Vector3(0, 0.54 * s, 0)).scale = Vector3(1.0, 1.8, 1.0)
	var head := Node3D.new()
	head.position = Vector3(0, 0.78 * s, 0.01 * s)
	head.rotation.x = deg_to_rad(-5)
	torso.add_child(head)
	var hr := 0.26 * s
	var skull := MK.skinned(head, MK.sphere_mesh(hr, 24, 12), skin, Vector3.ZERO)
	# wide and tall at the back, tapering to a small chin
	skull.scale = Vector3(1.12, 1.15, 1.0)
	var jaw := MK.skinned(head, MK.sphere_mesh(0.17 * s, 20, 10), skin, Vector3(0, -0.19 * s, 0.05 * s))
	jaw.scale = Vector3(0.85, 0.9, 0.9)

	# --- eyes: enormous black almonds, wrapped around the front of the skull ---
	for side in [-1.0, 1.0]:
		var ex: float = side * 0.13 * s
		var eye := MK.skinned(head, MK.sphere_mesh(0.12 * s, 20, 10), eye_mat,
			Vector3(ex, -0.02 * s, hr * 0.78))
		eye.scale = Vector3(1.25, 0.8, 0.7)
		# tilted inward and down: the angle is what makes them read as almonds
		eye.rotation.z = deg_to_rad(side * 26.0)
		# faint wet catchlight so they aren't flat black voids
		if detail:
			MK.add_mesh(head, MK.sphere_mesh(0.02 * s), eye_c,
				Vector3(ex + side * 0.03 * s, 0.03 * s, hr * 0.95), true, 1.6)
	# vestigial nostrils and a thin mouth line
	if detail:
		for side in [-1.0, 1.0]:
			MK.add_mesh(head, MK.sphere_mesh(0.012 * s), hide.darkened(0.45),
				Vector3(side * 0.025 * s, -0.14 * s, hr * 0.83))
	var mouth := MK.add_mesh(head, MK.sphere_mesh(0.05 * s), hide.darkened(0.5),
		Vector3(0, -0.23 * s, hr * 0.66))
	mouth.scale = Vector3(1.5, 0.22, 0.5)
	_batch_body()

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
	elif _legs.is_empty():
		# no legs to walk on: the old free-running bob is all there is
		position.y = absf(sin(_anim_t * 8.0)) * 0.06 * body_scale

func _move(dir: Vector3, speed: float, delta: float) -> void:
	position += dir * speed * delta
	if dir.length() > 0.01:
		rotation.y = atan2(dir.x, dir.z)
	_walk(speed, delta)

## One phase drives the whole gait — legs, knees, bob, roll and arms — so the
## parts can't drift against each other. The old bob ran off its own fixed 8Hz
## clock regardless of speed, which is why footfalls never lined up with it.
##
## Cadence falls as the creature grows: a pendulum's period goes with the square
## root of its length, so a bigger body takes slower, longer strides while a
## small one scurries. That single term is most of why the sizes feel different.
func _walk(speed: float, delta: float) -> void:
	if flying or _legs.is_empty():
		return
	_stride += delta * speed * 3.4 / sqrt(maxf(body_scale, 0.3))
	var swing := sin(_stride)
	for i in _legs.size():
		var side := 1.0 if i % 2 == 0 else -1.0
		_legs[i].rotation.x = swing * 0.55 * side
	for i in _knees.size():
		var side := 1.0 if i % 2 == 0 else -1.0
		# a knee folds one way only. Bend peaks while the leg swings through and
		# is zero while it carries weight, so the creature doesn't sink mid-step.
		var bend := maxf(0.0, -sin(_stride + 0.7) * side)
		_knees[i].rotation.x = bend * 0.85
	for i in _arms.size():
		var side := 1.0 if i % 2 == 0 else -1.0
		# arms counter-swing against the legs on the same side
		_arms[i].rotation.x = _arm_rest[i] - swing * 0.3 * side
	# The body rises on every footfall — twice per stride cycle, hence 2x — and
	# rolls onto whichever leg is planted. Both are small; overdone they read as
	# a limp rather than a walk.
	position.y = (1.0 - cos(_stride * 2.0)) * 0.022 * body_scale
	rotation.z = swing * 0.03

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
