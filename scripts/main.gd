extends Node3D
## Last Chicken Defense - The Armaeggin
## Cozy chicken farm by day. Something comes out of the trees at night.

const MK = preload("res://scripts/meshkit.gd")
const ChickenScript = preload("res://scripts/chicken.gd")
const RoosterScript = preload("res://scripts/rooster.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const PlayerScript = preload("res://scripts/player.gd")
const UIScript = preload("res://scripts/game_ui.gd")
const SfxScript = preload("res://scripts/sfx.gd")
const CustomerScript = preload("res://scripts/customer.gd")
const CL = preload("res://scripts/classes.gd")

const DAY_LEN := 170.0
const NIGHT_LEN := 115.0
const SAVE_PATH := "user://armaeggin_save.json"
const MAX_CHICKENS := 24
## TESTING: a full purse so the coop upgrade trees can be exercised without
## grinding eggs first. Drop this back to 25 before shipping.
const STARTING_COINS := 3000

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
var moonlight: DirectionalLight3D
var moon: MeshInstance3D
var moon_mat: StandardMaterial3D
var fence_mat: StandardMaterial3D
var window_mat: StandardMaterial3D
var _ground_tex: NoiseTexture2D
var _ground_norm: NoiseTexture2D
var _wood_tex: NoiseTexture2D
var _wood_norm: NoiseTexture2D
var _plaster_tex: NoiseTexture2D

const GRASS_SHADER := "
shader_type spatial;
render_mode cull_disabled, specular_disabled;
void vertex() {
	vec3 wpos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float w = 1.0 - UV.y;
	VERTEX.x += sin(TIME * 1.7 + wpos.x * 0.6 + wpos.z * 0.8) * 0.07 * w;
	VERTEX.z += cos(TIME * 1.3 + wpos.x * 0.9) * 0.04 * w;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
}
"

var chickens: Array = []
var roosters: Array = []
var enemies: Array = []
var projectiles: Array = []
var minions: Array = []
var deliveries: Array = []
var particles: Array = []
var egg_pickups: Array = []
var feed_piles: Array = []
var tree_spots: Array = []

var coins := STARTING_COINS
var eggs := 0
var feed := 5
var shells := 0
var day_num := 1
## Chosen on the character-select screen before the first "NEW GAME"; carried
## into the save so a continued game keeps the same body.
var player_gender := "male"
var is_night := false
var phase_t := 0.0
var upgrades := {"fence": 0, "coop": 0, "helmets": false, "turret": false, "rooster": false, "shotgun": false, "shoes": false}
var coop_hp := 300.0
var coop_broken := false
var night_theme := {}
## True for the rest of the day once the player has killed a hen. The flock
## stares him down for the first kill; the rooster punishes any kill after that.
var flock_vigilant := false

## The coop sits in the middle of the yard with its run around the door, so the
## hens defend from the centre rather than from one corner. Geometry below is
## derived from these, so moving them moves the building and the run together.
var coop_pos := Vector3(4, 0, 0)
var coop_door := Vector3(1.6, 0, 0)
## The upgrade kiosk stands beside the coop rather than on it, so training the
## flock is its own place in the yard instead of a second use of the building.
var kiosk_pos := Vector3(0.4, 0.0, 3.4)
## The roadside stand sits outside the fence on the house's side of the lane,
## so passers-by can reach it without ever entering the yard.
const ROAD_Z := 27.0
var stand_pos := Vector3(-9.0, 0.0, 23.2)
## 0 = not built yet. Each tier is a bigger stand that holds more and draws
## more custom.
var stand_tier := 0
var _stand_root: Node3D = null
## Eggs left out on the counter. Sold unattended, so this is the only thing
## standing between a passer-by and an empty stand.
var stand_eggs := 0
var customers: Array = []
var _customer_t := 12.0
## The stand pays better than shipping to the market over the computer —
## that premium is the whole reason to put goods out where they can be taken.
const STAND_EGG_PRICE := 11
## Chance a given visitor helps itself instead of paying, worst to best stand.
const STAND_THEFT_LOW := 0.05
const STAND_THEFT_HIGH := 0.15
## Roughly one visitor per this many seconds, before the tier bonus. Several
## are expected to be on the lane at once — arrivals are not queued behind
## each other finishing.
const CUSTOMER_GAP := 13.0
const CUSTOMER_MAX := 8
## Full-length mirror on the bedroom's north wall. Its reflection is a second
## copy of the chosen farmer rendered into a SubViewport, so it can keep the
## hat the first-person body has to drop.
var mirror_pos := Vector3.ZERO
var _mirror_vp: SubViewport = null
var _mirror_model: Node3D = null
var _mirror_anim: AnimationPlayer = null
var _mirror_gender := ""
var computer_pos := Vector3(-24.2, 1.0, -12)
var bed_pos := Vector3(-16.6, 0.0, -14.6)
var sleeping := false
var turret_node: Node3D = null
var _turret_cd := 0.0

## Browsers run the gl_compatibility renderer, which has no volumetric fog,
## SSAO or SSIL, and far less headroom -- so the web build trims its effects.
var is_web := OS.has_feature("web")

var started := false
var paused := true
var over := false
var market_open := false
var coop_open := false
## Which bird the coop screen is currently showing. -1 is the roster list.
var coop_sel := -1
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
		"sprint": KEY_SHIFT, "jump": KEY_SPACE, "interact": KEY_E, "post": KEY_F,
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
	# PhysicalSkyMaterial renders pure black under gl_compatibility, which is what
	# browsers get — so the web build was drawing a black void behind everything,
	# and the depth fog had no horizon to blend into. ProceduralSkyMaterial works
	# on both, so web takes that.
	var sky := Sky.new()
	if is_web:
		var proc := ProceduralSkyMaterial.new()
		proc.sun_angle_max = 12.0
		sky.sky_material = proc
	else:
		var sky_mat := PhysicalSkyMaterial.new()
		sky_mat.sun_disk_scale = 3.0
		sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.3
	# Glow runs on both renderers, but the wide blur levels and the HDR threshold
	# pass only earn their cost on desktop, so web keeps the narrow cheap version.
	env.glow_enabled = true
	env.glow_intensity = 0.5 if is_web else 0.9
	env.glow_bloom = 0.05 if is_web else 0.14
	if not is_web:
		env.glow_strength = 1.0
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
		# AgX holds most of the frame under 1.0, so a threshold just below it
		# means only genuinely hot things bloom: emissive eyes, the red moon,
		# the muzzle flash, the white damage flash.
		env.glow_hdr_threshold = 0.9
		env.glow_hdr_scale = 2.0
		# weight the wider levels, so hot spots bleed across the frame instead of
		# picking up a tight halo. Named with '/' so they need set().
		env.set("glow_levels/1", 0.0)
		env.set("glow_levels/2", 0.3)
		env.set("glow_levels/3", 0.7)
		env.set("glow_levels/4", 1.0)
		env.set("glow_levels/5", 0.7)
	# SSAO and SSIL exist only under forward_plus. The compatibility renderer
	# ignores them outright, so web needs no fallback beyond leaving them off.
	env.ssao_enabled = not is_web
	env.ssao_intensity = 2.6
	env.ssao_radius = 1.1
	env.ssao_power = 2.0
	env.ssao_detail = 0.6
	env.ssao_horizon = 0.05
	# bleed a little AO into direct light too, not just ambient — the contact
	# shadows under the coop and fence read better under a low sun
	env.ssao_light_affect = 0.15
	env.ssil_enabled = not is_web
	env.ssil_intensity = 0.9
	env.ssil_radius = 3.0
	# Depth haze is most of what gives an outdoor scene a sense of scale — the
	# treeline reading as far away rather than as small. The old density was thin
	# enough to be invisible past the fence.
	env.fog_enabled = true
	env.fog_density = 0.0026
	env.fog_aerial_perspective = 0.9
	env.fog_sun_scatter = 0.22
	env.fog_sky_affect = 0.0
	# a shallow ground layer, so mist pools in the yard at dawn
	env.fog_height = 3.0
	env.fog_height_density = 0.018
	_apply_grade(false)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.light_angular_distance = 0.4
	sun.directional_shadow_max_distance = 70.0 if is_web else 150.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)
	moonlight = DirectionalLight3D.new()
	moonlight.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	moonlight.rotation = Vector3(-1.0, 2.6, 0)
	moonlight.light_color = Color(0.5, 0.62, 1.0)
	moonlight.light_energy = 0.0
	moonlight.light_angular_distance = 1.5
	moonlight.shadow_enabled = true
	add_child(moonlight)
	moon = MK.sphere(self, 5.0, Color(0.93, 0.9, 0.82), Vector3(70, 55, -90), true, 2.0)
	moon_mat = moon.material_override
	moon.visible = false

func _build_world() -> void:
	_ground_tex = MK.noise_tex(11, 0.06, 5, false, 0.55)
	_ground_norm = MK.noise_tex(12, 0.09, 4, true)
	_wood_tex = MK.noise_tex(21, 0.05, 3, false, 0.6)
	_wood_norm = MK.noise_tex(21, 0.05, 3, true)
	_plaster_tex = MK.noise_tex(31, 0.15, 5, false, 0.78)
	# ground: invisible collider + textured plane
	MK.static_box(self, Vector3(240, 1, 240), Vector3(0, -0.5, 0))
	var gp := PlaneMesh.new()
	gp.size = Vector2(240, 240)
	var gmi := MeshInstance3D.new()
	gmi.mesh = gp
	gmi.material_override = MK.tex_mat(Color(0.4, 0.58, 0.3), _ground_tex, 70.0, 1.0, _ground_norm)
	add_child(gmi)
	# dirt in the chicken run + path to the gate
	var dirt := MK.box(self, Vector3(12, 0.04, 10), Color.WHITE, Vector3(22, 0.02, -1))
	dirt.material_override = MK.tex_mat(Color(0.8, 0.62, 0.4), _ground_tex, 6.0, 1.0, _ground_norm)
	var path := MK.box(self, Vector3(2.2, 0.04, 23), Color.WHITE, Vector3(0, 0.02, 15.5))
	path.material_override = MK.tex_mat(Color(0.9, 0.82, 0.62), _ground_tex, 3.0, 1.0, _ground_norm)
	# the road the stand faces, running past the property beyond the fence
	var road := MK.box(self, Vector3(150, 0.04, 6.0), Color.WHITE, Vector3(0, 0.025, ROAD_Z))
	road.material_override = MK.tex_mat(Color(0.76, 0.66, 0.5), _ground_tex, 26.0, 1.0, _ground_norm)
	_build_house()
	_build_coop()
	_build_kiosk()
	_build_farm_stand()
	_build_perimeter_fence()
	_build_forest()
	_build_grass()

func _build_house() -> void:
	var hx := -20.0
	var hz := -12.0
	var wall_m := MK.tex_mat(Color(0.95, 0.88, 0.75), _plaster_tex, 2.0, 0.85)
	var roof_m := MK.tex_mat(Color(0.5, 0.32, 0.22), _wood_tex, 3.0, 0.95, _wood_norm)
	var floor_m := MK.tex_mat(Color(0.7, 0.52, 0.38), _wood_tex, 4.0, 0.9, _wood_norm)
	MK.box(self, Vector3(12, 0.06, 10), Color.WHITE, Vector3(hx, 0.03, hz)).material_override = floor_m
	_tex_wall(Vector3(0.3, 3.2, 10.3), Vector3(hx - 6, 1.6, hz), wall_m)
	_tex_wall(Vector3(0.3, 3.2, 4.3), Vector3(hx + 6, 1.6, hz - 2.85), wall_m)
	_tex_wall(Vector3(0.3, 3.2, 4.3), Vector3(hx + 6, 1.6, hz + 2.85), wall_m)
	_tex_wall(Vector3(12.3, 3.2, 0.3), Vector3(hx, 1.6, hz - 5), wall_m)
	_tex_wall(Vector3(12.3, 3.2, 0.3), Vector3(hx, 1.6, hz + 5), wall_m)
	MK.box(self, Vector3(13.4, 0.3, 11.4), Color.WHITE, Vector3(hx, 3.5, hz)).material_override = roof_m
	MK.box(self, Vector3(13.4, 0.5, 2.0), Color.WHITE, Vector3(hx, 3.8, hz)).material_override = roof_m
	# warm windows facing the yard (glow at night)
	window_mat = MK.mat(Color(1.0, 0.85, 0.5), true, 0.15)
	for wx in [hx - 3.0, hx + 3.0]:
		var w := MK.box(self, Vector3(1.1, 1.0, 0.1), Color.WHITE, Vector3(wx, 1.8, hz + 5.13))
		w.material_override = window_mat
		MK.box(self, Vector3(1.3, 0.12, 0.14), Color(0.4, 0.3, 0.2), Vector3(wx, 1.24, hz + 5.13))
	# bed: sleep here to skip to nightfall
	bed_pos = Vector3(hx + 3.4, 0.0, hz - 2.6)
	var frame_m := MK.tex_mat(Color(0.55, 0.36, 0.2), _wood_tex, 2.0, 0.9, _wood_norm)
	MK.static_box(self, Vector3(1.9, 0.45, 2.9), bed_pos + Vector3(0, 0.22, 0))
	MK.box(self, Vector3(1.9, 0.45, 2.9), Color.WHITE, bed_pos + Vector3(0, 0.22, 0)).material_override = frame_m
	MK.box(self, Vector3(1.8, 0.22, 2.7), Color(0.75, 0.3, 0.28), bed_pos + Vector3(0, 0.55, 0))
	MK.box(self, Vector3(1.8, 0.06, 1.0), Color(0.9, 0.88, 0.85), bed_pos + Vector3(0, 0.67, 0.85))
	MK.box(self, Vector3(0.9, 0.16, 0.45), Color(0.95, 0.94, 0.9), bed_pos + Vector3(0, 0.72, -1.05))
	MK.box(self, Vector3(2.0, 0.9, 0.12), Color.WHITE, bed_pos + Vector3(0, 0.6, -1.45)).material_override = frame_m
	_build_mirror(Vector3(hx - 2.0, 0.0, hz - 4.78))
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
	var coop_m := MK.tex_mat(Color(0.95, 0.38, 0.28), _wood_tex, 2.5, 0.95, _wood_norm)
	var roof_m := MK.tex_mat(Color(0.45, 0.3, 0.2), _wood_tex, 3.0, 0.95, _wood_norm)
	var cx: float = coop_pos.x
	var cz: float = coop_pos.z
	_tex_wall(Vector3(3.6, 2.6, 3.2), Vector3(cx, 1.3, cz), coop_m)
	var roof := MK.box(self, Vector3(4.4, 0.2, 4.0), Color.WHITE, Vector3(cx, 2.85, cz))
	roof.material_override = roof_m
	roof.rotation.z = 0.14
	MK.box(self, Vector3(0.06, 1.3, 0.95), Color(0.08, 0.06, 0.05), Vector3(cx - 1.82, 0.65, cz))
	MK.box(self, Vector3(0.06, 0.45, 1.5), Color(0.9, 0.88, 0.8), Vector3(cx - 1.85, 1.95, cz))

## A little roadside stand: counter, canopy and a lit screen. Deliberately
## small and separate, so the coop stays a building and this stays a shop.
func _build_kiosk() -> void:
	var post_m := MK.tex_mat(Color(0.5, 0.36, 0.22), _wood_tex, 2.0, 0.9, _wood_norm)
	var body_m := MK.tex_mat(Color(0.86, 0.72, 0.34), _wood_tex, 2.0, 0.85, _wood_norm)
	var k := Node3D.new()
	k.position = kiosk_pos
	add_child(k)
	MK.static_box(k, Vector3(1.9, 1.1, 0.7), Vector3(0, 0.55, 0))
	MK.box(k, Vector3(1.9, 1.1, 0.7), Color.WHITE, Vector3(0, 0.55, 0)).material_override = body_m
	MK.box(k, Vector3(2.1, 0.09, 0.9), Color.WHITE, Vector3(0, 1.14, 0.06)).material_override = post_m
	for side in [-1.0, 1.0]:
		MK.box(k, Vector3(0.09, 1.1, 0.09), Color.WHITE, Vector3(side * 0.9, 1.7, -0.2)).material_override = post_m
	var canopy := MK.box(k, Vector3(2.3, 0.09, 1.2), Color(0.72, 0.22, 0.2), Vector3(0, 2.24, 0.05))
	canopy.rotation.x = deg_to_rad(-9)
	# the screen glows so the stand reads at a distance and at night
	var screen := MK.box(k, Vector3(0.9, 0.5, 0.05), Color(0.45, 0.95, 0.6), Vector3(0, 1.62, -0.22), true)
	screen.material_override.emission_energy_multiplier = 1.1
	MK.box(k, Vector3(0.5, 0.12, 0.5), Color(0.6, 0.5, 0.3), Vector3(0.6, 1.24, 0.1))

## A full-length mirror. Not a real planar reflection — it renders a second
## copy of the farmer into a SubViewport and paints that onto the glass. That
## costs one small viewport instead of re-rendering the whole yard, and it is
## the copy that keeps its hat, since the body worn in first person has its
## head collapsed to clear the brim.
func _build_mirror(pos: Vector3) -> void:
	mirror_pos = pos
	var frame_m := MK.tex_mat(Color(0.42, 0.28, 0.16), _wood_tex, 2.0, 0.9, _wood_norm)
	var m := Node3D.new()
	m.position = pos
	add_child(m)
	# frame: uprights, top and bottom rail
	for side in [-1.0, 1.0]:
		MK.box(m, Vector3(0.12, 2.3, 0.12), Color.WHITE, Vector3(side * 0.66, 1.2, -0.06)).material_override = frame_m
	for y in [0.06, 2.34]:
		MK.box(m, Vector3(1.44, 0.12, 0.12), Color.WHITE, Vector3(0, y, -0.06)).material_override = frame_m

	_mirror_vp = SubViewport.new()
	_mirror_vp.size = Vector2i(320, 640)
	_mirror_vp.transparent_bg = false
	_mirror_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Without this the viewport borrows the yard's World3D, and the reflected
	# farmer is a real body standing in the bedroom rather than an image on
	# the glass. Its own world also keeps the mirror's lighting to itself.
	_mirror_vp.own_world_3d = true
	add_child(_mirror_vp)
	var cam := Camera3D.new()
	_mirror_vp.add_child(cam)
	cam.fov = 42
	cam.look_at_from_position(Vector3(0, 1.15, 2.9), Vector3(0, 1.0, 0), Vector3.UP)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -28, 0)
	key.light_energy = 1.35
	_mirror_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 140, 0)
	fill.light_energy = 0.5
	_mirror_vp.add_child(fill)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.09, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.56)
	env.ambient_light_energy = 0.9
	env_node.environment = env
	_mirror_vp.add_child(env_node)

	# A QuadMesh, not a box: Godot packs a box's six faces into one UV atlas,
	# so a box front shows a crop of the texture rather than the whole frame.
	# A quad maps 0..1 across its single face, and already faces +Z.
	var glass := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.2, 2.16)
	glass.mesh = qm
	glass.position = Vector3(0, 1.2, 0.015)
	m.add_child(glass)
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = _mirror_vp.get_texture()
	# the viewport is already lit; shading it again would only muddy it
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.material_override = gm
	MK.static_box(self, Vector3(1.44, 2.4, 0.16), pos + Vector3(0, 1.2, -0.06))

## Swaps the reflected body to match the chosen farmer. Called when a game
## begins, since the house is built long before the character is picked.
func refresh_mirror() -> void:
	if _mirror_vp == null:
		return
	var want: String = player_gender if player_gender in ["male", "female"] else "male"
	if want == _mirror_gender and _mirror_model != null:
		return
	if _mirror_model != null:
		_mirror_model.queue_free()
		_mirror_model = null
		_mirror_anim = null
	var path := "res://models/farmer_male.glb" if want == "male" else "res://models/farmer_female.glb"
	if not ResourceLoader.exists(path):
		return
	_mirror_gender = want
	_mirror_model = load(path).instantiate()
	_mirror_vp.add_child(_mirror_model)
	_mirror_anim = _find_anim_in(_mirror_model)
	if _mirror_anim != null:
		for clip in [_mirror_idle(), "Walking", "Running"]:
			if _mirror_anim.has_animation(clip):
				_mirror_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		_mirror_anim.play(_mirror_idle())

func _mirror_idle() -> String:
	return "Idle_02" if _mirror_gender == "male" else "Idle_15"

static func _find_anim_in(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var f := _find_anim_in(c)
		if f != null:
			return f
	return null

## Only worth running while the player is close enough to look into it.
const MIRROR_ACTIVE_RANGE := 7.0

func _update_mirror() -> void:
	if _mirror_vp == null or _mirror_model == null:
		return
	var near: bool = player.position.distance_to(mirror_pos) < MIRROR_ACTIVE_RANGE
	_mirror_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if near else SubViewport.UPDATE_DISABLED
	if not near:
		return
	# A mirror flips only the axis along its normal, here Z. The player's own
	# forward is (-sin y, 0, -cos y) — the camera looks down -Z — so flipping
	# Z leaves a reflected forward of (-sin y, 0, cos y), which is the model
	# at yaw -y. Facing the glass square on (yaw 0) therefore shows a face.
	_mirror_model.rotation.y = -player.rotation.y
	# step sideways and the reflection steps with you, keeping the same side
	_mirror_model.position.x = clampf(player.position.x - mirror_pos.x, -0.9, 0.9)
	if _mirror_anim != null and player._body_anim != null:
		var clip: String = player._body_anim.current_animation
		if clip != "" and _mirror_anim.has_animation(clip) and _mirror_anim.current_animation != clip:
			_mirror_anim.play(clip)

## The roadside stand. Rebuilt from scratch on every upgrade rather than
## added to, so a tier is one description of a whole stand instead of a
## pile of conditional extras — much easier to keep straight as it grows.
## Tier 0 builds nothing at all: the stand does not exist until it is bought.
func _build_farm_stand() -> void:
	if _stand_root != null:
		_stand_root.queue_free()
		_stand_root = null
	if stand_tier <= 0:
		return
	var post_m := MK.tex_mat(Color(0.52, 0.4, 0.26), _wood_tex, 2.0, 0.92, _wood_norm)
	var plank_m := MK.tex_mat(Color(0.68, 0.55, 0.37), _wood_tex, 2.4, 0.9, _wood_norm)
	var tin_m := MK.mat(Color(0.74, 0.76, 0.78))
	tin_m.metallic = 0.55
	tin_m.roughness = 0.42

	var root := Node3D.new()
	root.position = stand_pos
	add_child(root)
	_stand_root = root

	# each tier is wider and deeper, and the roof grows with it
	var w: float = stand_width()
	var d: float = 1.9 + 0.35 * float(stand_tier)
	var h := 2.5

	# counter the goods sit on, facing the road (+z)
	MK.static_box(root, Vector3(w, 1.0, 0.75), Vector3(0, 0.5, d * 0.32))
	MK.box(root, Vector3(w, 1.0, 0.75), Color.WHITE, Vector3(0, 0.5, d * 0.32)).material_override = plank_m
	MK.box(root, Vector3(w + 0.3, 0.09, 0.95), Color.WHITE, Vector3(0, 1.05, d * 0.32)).material_override = post_m
	# corner posts and the tin roof over them
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			MK.box(root, Vector3(0.14, h, 0.14), Color.WHITE,
				Vector3(sx * w * 0.5, h * 0.5, sz * d * 0.5)).material_override = post_m
	var roof := MK.box(root, Vector3(w + 0.9, 0.12, d + 1.1), Color.WHITE, Vector3(0, h + 0.08, 0))
	roof.material_override = tin_m
	roof.rotation.x = deg_to_rad(-6)
	# Walled in on three sides, so it reads as a stall and not a table, and so
	# the only way to the goods is over the counter from the road. The planking
	# runs the full height the collider does — a wall you can see through but
	# not walk through is worse than no wall at all.
	MK.box(root, Vector3(w, h, 0.1), Color.WHITE, Vector3(0, h * 0.5, -d * 0.5)).material_override = plank_m
	MK.static_box(root, Vector3(w + 0.28, h, 0.24), Vector3(0, h * 0.5, -d * 0.5))
	for sx in [-1.0, 1.0]:
		MK.box(root, Vector3(0.1, h, d), Color.WHITE,
			Vector3(sx * w * 0.5, h * 0.5, 0)).material_override = plank_m
		MK.static_box(root, Vector3(0.3, h, d + 0.4), Vector3(sx * w * 0.5, h * 0.5, 0))

	# hanging sign
	# board first, then the lettering sized to sit inside it
	var board_w: float = minf(w * 0.82, 2.7)
	MK.box(root, Vector3(board_w, 0.46, 0.06), Color(0.93, 0.9, 0.82),
		Vector3(0, h - 0.42, d * 0.5 + 0.02))
	var sign := Label3D.new()
	sign.text = "HOMESTEAD"
	sign.font_size = 64
	# 9 characters at roughly 0.52 em each, fitted to the board with a margin
	sign.pixel_size = (board_w * 0.86) / (9.0 * 0.52 * 64.0)
	sign.modulate = Color(0.22, 0.17, 0.12)
	sign.outline_size = 0
	sign.position = Vector3(0, h - 0.42, d * 0.5 + 0.06)
	sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sign.double_sided = false
	root.add_child(sign)

	# tiered shelves of crates, more of them the bigger the stand gets
	var crates: int = 2 + stand_tier * 2
	var produce := [
		Color(0.85, 0.35, 0.16), Color(0.92, 0.66, 0.16), Color(0.86, 0.82, 0.3),
		Color(0.45, 0.6, 0.25), Color(0.75, 0.28, 0.3),
	]
	for i in crates:
		var t := (float(i) / maxf(1.0, float(crates - 1))) - 0.5
		var cx := t * (w - 0.9)
		var shelf: float = 1.12 if i % 2 == 0 else 1.62
		MK.box(root, Vector3(0.62, 0.34, 0.5), Color(0.6, 0.47, 0.3), Vector3(cx, shelf + 0.17, d * 0.28))
		# a heap of whatever is in season poking out of the top
		for k in 5:
			MK.sphere(root, randf_range(0.07, 0.11), produce[(i + k) % produce.size()],
				Vector3(cx + randf_range(-0.2, 0.2), shelf + 0.4, d * 0.28 + randf_range(-0.16, 0.16)))
		if i % 2 == 1:
			MK.box(root, Vector3(w * 0.9, 0.07, 0.55), Color.WHITE, Vector3(0, shelf, d * 0.28)).material_override = plank_m

	# the honesty box customers drop money into
	MK.box(root, Vector3(0.32, 0.26, 0.24), Color(0.35, 0.27, 0.18), Vector3(w * 0.5 - 0.3, 1.18, d * 0.32))

func _tex_wall(size: Vector3, pos: Vector3, m: Material) -> void:
	MK.static_box(self, size, pos)
	MK.box(self, size, Color.WHITE, pos).material_override = m

func _build_perimeter_fence() -> void:
	fence_mat = MK.tex_mat(Color(0.85, 0.62, 0.38), _wood_tex, 1.5, 0.95, _wood_norm)
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
	var bark_m := MK.tex_mat(Color(0.6, 0.44, 0.28), _wood_tex, 1.2, 1.0, _wood_norm)
	var placed := 0
	while placed < 130:
		var x := randf_range(-115.0, 115.0)
		var z := randf_range(-115.0, 115.0)
		if absf(x) < 38.0 and absf(z) < 28.0:
			continue
		var tree := Node3D.new()
		tree.position = Vector3(x, 0, z)
		tree.rotation.y = randf() * TAU
		var s := randf_range(0.75, 1.7)
		tree.scale = Vector3(s, s * randf_range(0.9, 1.3), s)
		add_child(tree)
		var far := Vector3(x, 0, z).length() > 65.0
		var g := Color(0.18 + randf() * 0.12, 0.42 + randf() * 0.2, 0.13 + randf() * 0.1)
		var canopy: Array = []
		var trunk := MK.cyl(tree, 0.2, 0.36, 2.2, Color.WHITE, Vector3(0, 1.1, 0))
		trunk.material_override = bark_m
		canopy.append(trunk)
		if randf() < 0.62:
			for i in 3:
				canopy.append(MK.cyl(tree, 0.0, 1.95 - 0.5 * float(i), 2.0, g.darkened(0.05 * float(i)), Vector3(randf_range(-0.12, 0.12), 2.3 + 1.2 * float(i), randf_range(-0.12, 0.12))))
		else:
			for i in 3:
				var blob := MK.sphere(tree, randf_range(0.9, 1.5), g, Vector3(randf_range(-0.8, 0.8), randf_range(2.6, 3.7), randf_range(-0.8, 0.8)))
				blob.scale.y = 0.82
				canopy.append(blob)
		if far:
			for c in canopy:
				c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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

func _build_grass() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.42)
	var sh := Shader.new()
	sh.code = GRASS_SHADER
	var smat := ShaderMaterial.new()
	smat.shader = sh
	quad.material = smat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	var count := 11000 if is_web else 42000
	mm.instance_count = count
	var idx := 0
	while idx < count:
		var x := randf_range(-62.0, 62.0)
		var z := randf_range(-62.0, 62.0)
		if Vector2(x, z).length() > 62.0:
			continue
		if absf(x - 22.0) < 6.5 and absf(z + 1.0) < 5.5:
			continue  # dirt run
		if absf(x) < 1.4 and z > 3.0 and z < 20.5:
			continue  # path
		if absf(x + 20.0) < 6.8 and absf(z + 12.0) < 5.8:
			continue  # house
		if absf(x - 20.0) < 2.5 and absf(z + 12.0) < 2.2:
			continue  # coop
		var tall := randf_range(0.5, 0.9) if in_yard(x, z) else randf_range(0.8, 1.4)
		var basis := Basis(Vector3.UP, randf() * TAU)
		basis = basis.rotated(Vector3.RIGHT, randf_range(-0.12, 0.12))
		basis = basis.scaled(Vector3(1, tall, 1))
		mm.set_instance_transform(idx, Transform3D(basis, Vector3(x, 0.21 * tall, z)))
		var r := randf()
		mm.set_instance_color(idx, Color(0.2 + r * 0.08, 0.42 + r * 0.14, 0.12 + r * 0.05))
		idx += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

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
	# the body and its reflection are both built before the character is
	# chosen, so settle them here — after a pick, or after a save has loaded
	player.rebuild_body()
	refresh_mirror()
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
		# The Roost and the Farmers Market are opened from separate, mutually
		# exclusive interact contexts, so only one is ever open at a time —
		# closing whichever it is takes ESC out of it. This used to only
		# check market_open, so ESC did nothing to close the Roost: paused
		# flipped back to false and the mouse recaptured, but the panel
		# itself was never hidden, leaving the game stuck showing it with no
		# way to click out.
		if market_open:
			close_market()
		elif coop_open:
			close_coop()
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
	for r in roosters.duplicate():
		r.tick(delta)
	for e in enemies.duplicate():
		e.tick(delta)
	_update_projectiles(delta)
	_update_minions(delta)
	_update_deliveries(delta)
	_update_customers(delta)
	_update_particles(delta)
	_update_pickups()
	_update_mirror()
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
	# the rooster calls the alarm as the light dies
	if roosters.size() > 0:
		await get_tree().create_timer(1.1).timeout
		sfx.crow(-7.0)
	_whisper_t = 8.0

func _start_dawn() -> void:
	is_night = false
	day_num += 1
	flock_vigilant = false
	for e in enemies.duplicate():
		e.ignite()
	moon.visible = false
	ui.night_fx(false)
	if roosters.size() > 0:
		sfx.crow(-5.0)
	var laid := 0
	for c in chickens:
		c.days_survived += 1
		c.day_mode()
		if not c.is_chick:
			laid += 1
			var egg_mesh := MK.sphere(self, 0.14, Color(0.98, 0.95, 0.85), coop_door + Vector3(randf_range(-3.5, 1.5), 0.12, randf_range(-3.5, 3.5)))
			egg_mesh.scale.y = 1.3
			egg_pickups.append(egg_mesh)
	var hatched := 0
	if roosters.size() > 0:
		# more roosters = better fertility, with diminishing returns
		var rate := 0.12 + 0.05 * float(roosters.size() - 1)
		for c in chickens.duplicate():
			if not c.is_chick and chickens.size() + hatched < MAX_CHICKENS and randf() < rate:
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
		_try_raise(e.position)
	e.queue_free()

## A necromancer in range of a fresh corpse gets it back on its feet, fighting
## for the yard this time. One raise per kill, whoever is nearest.
func _try_raise(pos: Vector3) -> void:
	var best = null
	var best_d := 1e9
	for c in chickens:
		if not bool(c.stats.get("raise", false)):
			continue
		if c.state != "guard" and c.state != "perch":
			continue
		var d: float = c.position.distance_to(pos)
		if d < float(c.stats.get("range", 12.0)) and d < best_d:
			best = c
			best_d = d
	if best != null:
		summon_minion(pos, "risen", float(best.stats.get("dmg", 8.0)) * 0.5)

func melee_attack(origin: Vector3, dir: Vector3) -> void:
	var best = null
	var best_d := 3.1
	for e in enemies:
		var to: Vector3 = e.position + Vector3(0, 1, 0) - origin
		var d := to.length()
		if d < best_d and to.normalized().dot(dir) > 0.5:
			best = e
			best_d = d
	# anything loitering at the stand is hittable too, which is the only way
	# to see off a buyer that turned up for the birds
	for v in customers:
		var tov: Vector3 = v.position + Vector3(0, 1.2, 0) - origin
		var dv := tov.length()
		if dv < best_d and tov.normalized().dot(dir) > 0.5:
			best = v
			best_d = dv
	# friendly fire is a day-only mistake — at night the flock is either
	# hidden or already fighting for its life
	if is_day():
		for c in chickens:
			if not c.targetable():
				continue
			var to: Vector3 = c.position + Vector3(0, 0.5, 0) - origin
			var d := to.length()
			if d < best_d and to.normalized().dot(dir) > 0.5:
				best = c
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
		for v in customers:
			var vc: Vector3 = v.position + Vector3(0, 1.2, 0)
			var tov := vc - origin
			var tv := tov.dot(pd)
			if tv >= 0.5 and tv <= best_t and (tov - pd * tv).length() < 0.6:
				best = v
				best_t = tv
		if is_day():
			for c in chickens:
				if not c.targetable():
					continue
				var center: Vector3 = c.position + Vector3(0, 0.5, 0)
				var to := center - origin
				var t := to.dot(pd)
				if t < 0.5 or t > best_t:
					continue
				var perp := (to - pd * t).length()
				if perp < 0.55:
					best = c
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
	var m := MK.add_mesh(self, MK.sphere_mesh(0.12, 10, 5), Color(0.98, 0.95, 0.85), head + aim * 0.8)
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

## A shot from a ranged hen. Damage and any splash ride along on the
## projectile, so one pooled update handles arrows, bolts and every element a
## mage can throw without a branch per class.
func hen_shot(from: Node3D, target: Node3D, dmg: float, st: Dictionary) -> void:
	var head: Vector3 = from.position + Vector3(0, 0.55, 0)
	var aim: Vector3 = (target.position + Vector3(0, 0.8, 0) - head).normalized()
	var shots: int = maxi(int(st.get("shots", 1)), 1)
	# a green military hen starts wide of the mark; rank (any track) tightens it
	var wob: float = 1.0 - float(st.get("accuracy", 1.0))
	for i in shots:
		var spread := Vector3.ZERO
		if shots > 1:
			spread = Vector3(randf_range(-0.12, 0.12), randf_range(-0.05, 0.05), randf_range(-0.12, 0.12))
		if wob > 0.0:
			spread += Vector3(randf_range(-wob, wob), randf_range(-wob, wob) * 0.4, randf_range(-wob, wob)) * 0.4
		var col: Color = st.get("shot_colour", Color(0.95, 0.95, 0.8))
		var m := MK.add_mesh(self, MK.sphere_mesh(0.09, 8, 4), col, head + aim * 0.6, true, 1.6)
		projectiles.append({
			"node": m, "vel": (aim + spread).normalized() * 26.0, "kind": "hen",
			"life": 2.0, "dmg": dmg, "splash": float(st.get("splash", 0.0)),
			"colour": col, "burn": bool(st.get("burn", false)),
		})
	sfx.play("egg", -14.0)

func _update_projectiles(delta: float) -> void:
	for pr in projectiles.duplicate():
		pr.life -= delta
		if pr.kind != "turret" and pr.kind != "hen":
			pr.vel.y -= 20.0 * delta
		pr.node.position += pr.vel * delta
		var done := false
		var hit = nearest_enemy(pr.node.position, 0.9)
		match pr.kind:
			"hen":
				if hit != null:
					if pr.splash > 0.0:
						for e in enemies.duplicate():
							if e.position.distance_to(pr.node.position) < pr.splash:
								e.damage(pr.dmg)
					else:
						hit.damage(pr.dmg)
					if pr.burn:
						hit.ignite()
					spawn_poof(pr.node.position, pr.colour, 4)
					done = true
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

## Summoned and raised helpers. Deliberately dicts in a pool rather than full
## Chicken nodes: they exist for a few seconds, want none of the day/night or
## foraging machinery, and a wave can hold a dozen at once.
const MINION_CAP := 14

var _minion_meshes := {}
var _minion_mats := {}

func minion_count(kind: String) -> int:
	var n := 0
	for m in minions:
		if m.kind == kind:
			n += 1
	return n

func summon_minion(pos: Vector3, kind: String, dmg: float) -> void:
	if minions.size() >= MINION_CAP:
		return
	# meshes and materials are built once and shared — building them per summon
	# is exactly the mistake that made combat stutter
	if not _minion_meshes.has(kind):
		_minion_meshes[kind] = MK.sphere_mesh(0.16, 10, 6)
		var col := Color(0.55, 1.0, 0.62) if kind == "spirit" else Color(0.82, 0.8, 0.7)
		var mm := MK.mat(col)
		if kind == "spirit":
			mm.emission = col
			mm.emission_energy_multiplier = 1.4
			mm.albedo_color = Color(col.r, col.g, col.b, 0.75)
			mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_minion_mats[kind] = mm
	var root := Node3D.new()
	root.position = pos + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
	add_child(root)
	var body := MeshInstance3D.new()
	body.mesh = _minion_meshes[kind]
	body.material_override = _minion_mats[kind]
	body.position = Vector3(0, 0.3, 0)
	root.add_child(body)
	var head := MeshInstance3D.new()
	head.mesh = _minion_meshes[kind]
	head.material_override = _minion_mats[kind]
	head.position = Vector3(0, 0.52, 0.1)
	head.scale = Vector3.ONE * 0.6
	root.add_child(head)
	minions.append({
		"node": root, "kind": kind, "life": 14.0 if kind == "spirit" else 20.0,
		"dmg": dmg, "cd": 0.0, "bob": randf() * TAU,
	})
	spawn_poof(pos, Color(0.55, 1.0, 0.62) if kind == "spirit" else Color(0.6, 0.9, 0.6), 6)

func _update_minions(delta: float) -> void:
	for m in minions.duplicate():
		m.life -= delta
		m.cd -= delta
		if m.life <= 0.0 or not is_instance_valid(m.node):
			if is_instance_valid(m.node):
				spawn_poof(m.node.position, Color(0.5, 0.8, 0.55), 4)
				m.node.queue_free()
			minions.erase(m)
			continue
		m.bob += delta * 6.0
		var target = nearest_enemy(m.node.position, 26.0)
		if target == null:
			# nothing to chase: drift back toward the coop and wait
			var home: Vector3 = coop_door + Vector3(0, 0, 2.0)
			if m.node.position.distance_to(home) > 2.5:
				m.node.position += (home - m.node.position).normalized() * 2.0 * delta
		else:
			var to: Vector3 = target.position - m.node.position
			to.y = 0.0
			if to.length() > 1.3:
				m.node.position += to.normalized() * 3.4 * delta
				m.node.rotation.y = atan2(to.x, to.z)
			elif m.cd <= 0.0:
				m.cd = 1.0
				target.damage(m.dmg)
		m.node.position.y = absf(sin(m.bob)) * 0.12

func _update_particles(delta: float) -> void:
	for p in particles.duplicate():
		p.life -= delta
		p.vel.y -= 9.0 * delta
		p.node.position += p.vel * delta
		p.node.scale = Vector3.ONE * maxf(0.05, p.life / p.max_life)
		if p.life <= 0.0:
			particles.erase(p)
			p.node.queue_free()

## One shared low-poly sphere and one material per colour, reused forever.
## This used to build a fresh SphereMesh at Godot's default 64x32 tessellation —
## about 2,000 triangles of CPU mesh generation — plus a fresh material, for
## every single particle, a dozen of them per hit. That was the combat stutter.
var _poof_mesh: SphereMesh = null
var _poof_mats := {}

func spawn_poof(pos: Vector3, color: Color, n: int) -> void:
	if _poof_mesh == null:
		_poof_mesh = MK.sphere_mesh(0.1, 8, 4)
	var key := color.to_html(false)
	if not _poof_mats.has(key):
		_poof_mats[key] = MK.mat(color)
	for i in n:
		var m := MeshInstance3D.new()
		m.mesh = _poof_mesh
		m.material_override = _poof_mats[key]
		m.position = pos + Vector3(randf_range(-0.3, 0.3), randf_range(0, 0.5), randf_range(-0.3, 0.3))
		m.scale = Vector3.ONE * randf_range(0.6, 1.4)
		add_child(m)
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

## Uniform across the yard, but rerolled off the coop and kiosk footprints so
## wandering birds spread through the fence line instead of piling up on the
## buildings they'd otherwise walk straight through.
func rand_in_yard() -> Vector3:
	var p := Vector3.ZERO
	for i in 8:
		p = Vector3(randf_range(YARD.min_x + 3.0, YARD.max_x - 3.0), 0, randf_range(YARD.min_z + 3.0, YARD.max_z - 3.0))
		if p.distance_to(coop_pos) > 5.0 and p.distance_to(kiosk_pos) > 3.0:
			break
	return p

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

# ---------------- the farm stand ----------------

const STAND_TIER_MAX := 3
const STAND_PRICES := [180, 420, 900]

## One market row that covers buying the stand and every upgrade after it.
func _stand_listing() -> Dictionary:
	if stand_tier >= STAND_TIER_MAX:
		return {"id": "stand", "name": "FARM STAND", "desc": "as big as the lane will take.", "price": 0, "owned": true}
	var price: int = STAND_PRICES[stand_tier]
	if stand_tier == 0:
		return {
			"id": "stand", "name": "ROADSIDE FARM STAND",
			"desc": "a counter by the lane. leave eggs on it and passers-by pay $%d each, against $6 shipping them from here. nobody minds the till, so a few will help themselves." % STAND_EGG_PRICE,
			"price": price, "owned": false,
		}
	return {
		"id": "stand", "name": "ENLARGE THE STAND (tier %d)" % (stand_tier + 1),
		"desc": "holds %d eggs instead of %d, is seen from further down the lane, and looks tended enough that fewer people chance it." % [8 * (stand_tier + 1), stand_capacity()],
		"price": price, "owned": false,
	}


## Frontage of the counter at each tier. Customers space themselves along it,
## so the widths have to be readable from outside the builder.
const STAND_WIDTHS := [0.0, 3.0, 4.4, 6.0]

func stand_width() -> float:
	return STAND_WIDTHS[stand_tier]

## How many eggs the counter holds. A bigger stand is worth buying mostly
## because it can carry more between visits to it.
func stand_capacity() -> int:
	return 8 * stand_tier

## Better stands look tended, and tended stands get robbed less.
func stand_theft_chance() -> float:
	if stand_tier <= 1:
		return STAND_THEFT_HIGH
	return lerpf(STAND_THEFT_HIGH, STAND_THEFT_LOW, float(stand_tier - 1) / 2.0)

## Move eggs from the player's basket onto the counter. Returns how many
## actually fitted, so the caller can say something useful about the rest.
func stock_stand(n: int) -> int:
	var room := stand_capacity() - stand_eggs
	var moved := mini(mini(n, eggs), room)
	if moved <= 0:
		return 0
	eggs -= moved
	stand_eggs += moved
	sfx.play("grab", -10.0)
	ui.refresh()
	return moved

## A customer taking goods off the counter, paid for or not.
func take_from_stand(n: int) -> int:
	var got := mini(n, stand_eggs)
	stand_eggs -= got
	ui.refresh()
	return got

## Any grown bird out in the yard is fair game for something that walked up
## and asked. Ones shut in the coop or already being carried off are not.
func nearest_stealable_chicken(from: Vector3):
	var best = null
	var best_d := 1e9
	for c in chickens:
		if not c.targetable() or c.is_chick:
			continue
		var d: float = from.distance_to(c.position)
		if d < best_d:
			best = c
			best_d = d
	return best

func chicken_stolen_by_buyer(c: Node3D) -> void:
	if c == null or not chickens.has(c):
		return
	chickens.erase(c)
	spawn_poof(c.position + Vector3(0, 0.5, 0), Color(0.4, 0.7, 0.35), 10)
	c.queue_free()
	ui.announce("YOU HAVE BEEN ROBBED", "it was never here to buy anything", true)
	ui.refresh()
	_check_game_over()

func chicken_sold_to_buyer(c: Node3D, price: int) -> void:
	if c == null or not chickens.has(c):
		return
	chickens.erase(c)
	add_coins(price)
	sfx.play("coin")
	spawn_poof(c.position + Vector3(0, 0.5, 0), Color(0.9, 0.85, 0.6), 8)
	c.queue_free()
	ui.whisper("sold, for $%d" % price)
	ui.refresh()
	_check_game_over()

## Anyone loitering at the counter with an offer open.
func waiting_buyer():
	for v in customers:
		if v.disguised and v.state == "offer":
			return v
	return null

func customer_gone(v: Node3D) -> void:
	if not customers.has(v):
		return
	customers.erase(v)
	v.queue_free()

func nearest_customer(pos: Vector3, radius: float):
	var best = null
	var best_d := radius
	for v in customers:
		var d: float = pos.distance_to(v.position)
		if d < best_d:
			best = v
			best_d = d
	return best

## Trade only happens in daylight; after dark the road belongs to whatever
## comes out of the trees.
func _update_customers(delta: float) -> void:
	for v in customers.duplicate():
		if is_instance_valid(v):
			v.tick(delta)
	if stand_tier <= 0 or is_night:
		return
	_customer_t -= delta
	if _customer_t > 0.0:
		return
	# a bigger stand is seen from further down the road, so custom picks up
	_customer_t = CUSTOMER_GAP / (1.0 + 0.45 * float(stand_tier - 1))
	_customer_t *= randf_range(0.7, 1.4)
	if customers.size() >= CUSTOMER_MAX:
		return
	# nothing to sell and nothing worth stealing means nobody bothers, unless
	# it is one of the ones that came for the birds
	var pretender := randf() < 0.22 and chickens.size() > 2
	if stand_eggs <= 0 and not pretender:
		return
	var v = CustomerScript.new()
	add_child(v)
	v.setup(self, pretender)
	customers.append(v)

# ---------------- helmet deliveries ----------------

## Each helmet is bought for one hen, and the next one costs more. Escalating
## rather than a single flock-wide switch, so kitting everyone out is a campaign.
const HELMET_BASE := 120
const HELMET_STEP := 50

func helmets_owned() -> int:
	var n := 0
	for c in chickens:
		if c.helmeted:
			n += 1
	return n

func helmet_price() -> int:
	return HELMET_BASE + HELMET_STEP * helmets_owned()

## Picks a bare-headed hen and calls in the drop. Returns false if there is
## nobody left to kit out, so buy() can refund the intent.
func _deliver_helmet() -> bool:
	var candidates := []
	for c in chickens:
		if not c.helmeted and not c.is_chick:
			candidates.append(c)
	if candidates.is_empty():
		sfx.play("denied")
		return false
	var hen = candidates[randi() % candidates.size()]
	var drop: Vector3 = hen.position + Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2))
	# drone enters from the treeline so the delivery reads as arriving
	var from := Vector3(drop.x - 26.0, 11.0, drop.z - 14.0)
	var body := MK.box(self, Vector3(0.5, 0.14, 0.5), Color(0.22, 0.23, 0.26), Vector3.ZERO)
	var drone := Node3D.new()
	drone.position = from
	add_child(drone)
	body.reparent(drone)
	body.position = Vector3.ZERO
	for dx in [-0.3, 0.3]:
		for dz in [-0.3, 0.3]:
			MK.cyl(drone, 0.22, 0.22, 0.03, Color(0.35, 0.36, 0.4, 0.55), Vector3(dx, 0.1, dz))
	MK.box(drone, Vector3(0.12, 0.05, 0.12), Color(0.9, 0.3, 0.25), Vector3(0, -0.1, 0), true)
	deliveries.append({"drone": drone, "hen": hen, "drop": drop, "phase": "in", "pkg": null, "t": 0.0})
	ui.announce("INCOMING DELIVERY", "one tiny war helmet")
	return true

func _update_deliveries(delta: float) -> void:
	for d in deliveries.duplicate():
		d.t += delta
		match d.phase:
			"in":
				var over: Vector3 = d.drop + Vector3(0, 6.0, 0)
				d.drone.position = d.drone.position.move_toward(over, 14.0 * delta)
				d.drone.rotation.y += delta * 3.0
				if d.drone.position.distance_to(over) < 0.4:
					var pkg := MK.box(self, Vector3(0.34, 0.3, 0.34), Color(0.55, 0.45, 0.3), d.drone.position)
					MK.box(pkg, Vector3(0.36, 0.06, 0.36), Color(0.8, 0.2, 0.18), Vector3(0, 0.02, 0))
					d.pkg = pkg
					d.phase = "drop"
					sfx.play("grab", -10.0)
			"drop":
				d.pkg.position.y = maxf(0.18, d.pkg.position.y - 9.0 * delta)
				d.drone.position.y += delta * 1.5
				if d.pkg.position.y <= 0.19:
					spawn_poof(d.pkg.position, Color(0.7, 0.65, 0.5), 6)
					if is_instance_valid(d.hen):
						d.hen.await_package(d.pkg.position)
					d.phase = "out"
			"out":
				# drone leaves under its own power; the package waits to be claimed
				d.drone.position += Vector3(1.0, 0.55, 0.6) * 11.0 * delta
				var claimed: bool = not is_instance_valid(d.hen) or d.hen.helmeted
				if claimed or d.t > 26.0:
					if is_instance_valid(d.pkg):
						d.pkg.queue_free()
					if is_instance_valid(d.drone):
						d.drone.queue_free()
					deliveries.erase(d)

func _spawn_chicken(pos: Vector3, chick: bool) -> void:
	var c = ChickenScript.new()
	add_child(c)
	c.setup(self, pos, chick)
	c.refresh_class()
	chickens.append(c)

func _spawn_rooster(pos: Vector3) -> void:
	var r = RoosterScript.new()
	add_child(r)
	r.setup(self, pos)
	# stagger perches along the coop ridge so multiple roosters don't overlap
	var i := roosters.size()
	# derived from coop_pos — this was still pointing at the coop's old corner
	r.perch = coop_pos + Vector3((float(i) - 0.5) * 1.1, 3.15, 0)
	r.refresh_class()
	roosters.append(r)

func chicken_died(c: Node3D) -> void:
	if not chickens.has(c):
		return
	# only the player's own weapons can kill a chicken outright — anything an
	# enemy does to one is a carry-off, handled by chicken_taken() instead
	var was_vigilant := flock_vigilant and is_day()
	chickens.erase(c)
	spawn_poof(c.position + Vector3(0, 0.4, 0), Color(0.95, 0.92, 0.85), 12)
	c.queue_free()
	if is_day():
		if was_vigilant:
			if roosters.size() > 0:
				roosters[0].punish_player()
			ui.announce("THE ROOSTER REMEMBERS", "he warned you")
		else:
			flock_vigilant = true
			for other in chickens:
				other.start_judging()
			ui.whisper("the flock has noticed")
	else:
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

## How many roosters the flock is allowed: 1 per 10 hens.
func rooster_cap() -> int:
	return hen_count() / 10

func hen_count() -> int:
	var n := 0
	for c in chickens:
		if not c.is_chick:
			n += 1
	return n

func _rooster_listing() -> Dictionary:
	var cap := rooster_cap()
	var have := roosters.size()
	var base := {"id": "rooster", "name": "AYAM CEMANI ROOSTER", "price": 60 + 90 * have, "owned": false}
	if have >= cap:
		var needed := (have + 1) * 10 - hen_count()
		base.name += "  [LOCKED]"
		base.desc = "all-black, iridescent, deeply serious. one rooster per 10 hens - you need %d more hen%s." % [needed, "" if needed == 1 else "s"]
		base.owned = true  # renders as unavailable
	else:
		base.desc = "all-black, iridescent, deeply serious. enables breeding, and roosts on the Armory at night to divebomb intruders.  (%d/%d owned)" % [have, cap]
	return base

func market_items() -> Array:
	var items := [
		{"id": "hen", "name": "LIVE HEN", "desc": "+1 hen, delivered instantly by drone. do not ask about the drone.", "price": 35, "owned": chickens.size() >= MAX_CHICKENS},
		_rooster_listing(),
		{"id": "feed5", "name": "CHICKEN FEED x5", "desc": "throw it. a chicken will come eat it and heal 30 hp.", "price": 12, "owned": false},
		{"id": "shotgun", "name": "PUMP SHOTGUN", "desc": "the farmer's argument. includes 8 shells.", "price": 150, "owned": upgrades.shotgun},
		{"id": "shells8", "name": "SHELLS x8", "desc": "arguments, refilled.", "price": 20, "owned": false},
		_stand_listing(),
		{"id": "helmets", "name": "TINY WAR HELMET", "desc": "fits one hen. she fights at night instead of hiding. air-dropped, because the supplier insists. (%d of %d kitted)" % [helmets_owned(), chickens.size()], "price": helmet_price(), "owned": helmets_owned() >= chickens.size()},
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
			if roosters.size() >= rooster_cap():
				sfx.play("denied")
				return
			_spawn_rooster(rand_in_yard())
			upgrades.rooster = true
		"feed5":
			feed += 5
		"shotgun":
			upgrades.shotgun = true
			shells += 8
		"shells8":
			shells += 8
		"stand":
			stand_tier += 1
			_build_farm_stand()
			if stand_tier == 1:
				ui.announce("THE STAND IS OPEN", "put eggs out and people will come")
		"helmets":
			if not _deliver_helmet():
				return
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

## Sleep until nightfall. Costs the rest of the day's foraging income, so it's
## a real choice: rest early and go in prepared, or squeeze the daylight.
func sleep_until_night() -> void:
	if sleeping or is_night or over:
		return
	sleeping = true
	player.hp = minf(player.max_hp, player.hp + 25.0)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	ui.set_prompt(null)
	await ui.fade_to_black(1.1)
	phase_t = 0.999
	await get_tree().create_timer(0.7).timeout
	await ui.fade_from_black(1.4)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	sleeping = false

# ---------------- coop upgrades ----------------

## Everything purchasable at the coop goes through here so one place owns the
## "can you afford it" check, the deduction and the UI refresh.
func _spend(cost: int) -> bool:
	if coins < cost:
		sfx.play("denied", -6.0)
		return false
	coins -= cost
	sfx.play("buy", -6.0)
	ui.refresh()
	ui.coop_refresh()
	return true

func birds() -> Array:
	var a: Array = []
	a.append_array(chickens)
	a.append_array(roosters)
	return a

func promote(bird, class_id: String) -> void:
	var price: int = int(CL.CLASSES[class_id]["price"])
	if bird.class_id != "hen" or not _spend(price):
		return
	bird.class_id = class_id
	bird.spec_id = ""
	bird.refresh_class()

## Specialisations cost a flat premium and are permanent — the point of the
## choice is that it closes the others off.
const SPEC_PRICE := 220

func specialise(bird, spec_id: String) -> void:
	if bird.spec_id != "" or not CL.can_spec(bird.tracks):
		return
	if not _spend(SPEC_PRICE):
		return
	bird.spec_id = spec_id
	bird.refresh_class()

func buy_track(bird, track: String) -> void:
	var owned: int = int(bird.tracks.get(track, 0))
	if owned >= int(CL.TRACKS[track]["max"]):
		return
	if not _spend(CL.track_cost(track, owned)):
		return
	bird.tracks[track] = owned + 1
	bird.refresh_class()

func open_coop() -> void:
	if over or is_night:
		return
	coop_open = true
	coop_sel = -1
	paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	ui.open_coop()

func close_coop() -> void:
	coop_open = false
	ui.close_coop()
	paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

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

## Colour grading. Lights set what the scene *is*; the grade sets how it reads,
## and no amount of light tuning substitutes for it — a warm cast over a whole
## frame is a grade, not a lamp.
##
## Two of them, because the game is two games. Day is warm and slightly lifted;
## night is cold, desaturated and crushed. The 1D ramp maps luminance to colour,
## which is what splits the tone: cool shadows against warm highlights by day,
## and the reverse after dark.
static var _grade_day: GradientTexture1D = null
static var _grade_night: GradientTexture1D = null

static func _ramp(shadow: Color, mid: Color, high: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([shadow, mid, high])
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	return t

func _apply_grade(night: bool) -> void:
	if _grade_day == null:
		_grade_day = _ramp(Color(0.05, 0.07, 0.10), Color(0.52, 0.51, 0.45), Color(1.0, 0.97, 0.86))
		_grade_night = _ramp(Color(0.015, 0.02, 0.05), Color(0.34, 0.39, 0.50), Color(0.86, 0.92, 1.0))
	env.adjustment_enabled = true
	if night:
		env.adjustment_brightness = 0.94
		env.adjustment_contrast = 1.18
		env.adjustment_saturation = 0.72
		env.adjustment_color_correction = _grade_night
	else:
		env.adjustment_brightness = 1.02
		env.adjustment_contrast = 1.07
		env.adjustment_saturation = 1.14
		env.adjustment_color_correction = _grade_day

func _update_environment() -> void:
	if is_night:
		var boss: bool = night_theme.get("boss", false)
		sun.light_energy = 0.0
		sun.rotation = Vector3(0.5, 0.4, 0)  # below horizon -> physical sky goes dark
		moonlight.light_energy = 0.5
		moonlight.light_color = Color(1.0, 0.4, 0.32) if boss else Color(0.5, 0.62, 1.0)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.28, 0.1, 0.12) if boss else Color(0.12, 0.15, 0.25)
		env.ambient_light_energy = 0.5
		_apply_grade(true)
		if is_web:
			# no volumetric fog in gl_compatibility; fall back to depth fog
			env.fog_enabled = true
			env.fog_density = 0.03 if boss else 0.018
			env.fog_light_color = Color(0.16, 0.03, 0.05) if boss else Color(0.05, 0.07, 0.14)
		else:
			env.fog_enabled = false
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = 0.028 if boss else 0.012
			env.volumetric_fog_albedo = Color(0.55, 0.15, 0.15) if boss else Color(0.35, 0.45, 0.7)
	else:
		var ang := lerpf(0.10, 0.90, phase_t) * PI
		var elev := sin(ang)
		var warm := clampf(elev * 2.0, 0.0, 1.0)
		sun.rotation = Vector3(-ang, 0.4, 0)
		sun.light_energy = maxf(0.3, elev) * 1.55
		sun.light_color = Color(1.0, lerpf(0.55, 0.98, warm), lerpf(0.3, 0.95, warm))
		moonlight.light_energy = 0.0
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = lerpf(0.6, 1.0, elev)
		_apply_grade(false)
		if not is_web:
			env.volumetric_fog_enabled = false
		env.fog_enabled = true
		env.fog_density = 0.0026
		env.fog_light_color = Color(0.7, 0.8, 0.95)
	if window_mat != null:
		window_mat.emission_energy_multiplier = 2.2 if is_night else 0.15

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
	# progression is per bird, so the roster is stored, not just a count
	var flock := []
	for c in chickens:
		flock.append({"class": c.class_id, "spec": c.spec_id, "tracks": c.tracks, "helm": c.helmeted, "days": c.days_survived})
	var crew := []
	for r in roosters:
		crew.append({"class": "rooster", "spec": r.spec_id, "tracks": r.tracks})
	var data := {
		"coins": coins, "day": day_num, "eggs": eggs, "feed": feed, "shells": shells,
		"hens": hens, "roosters": roosters.size(), "coop_hp": coop_hp, "upgrades": upgrades,
		"flock": flock, "crew": crew, "gender": player_gender,
		"stand_tier": stand_tier, "stand_eggs": stand_eggs,
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
	coins = int(data.get("coins", STARTING_COINS))
	day_num = int(data.get("day", 1))
	eggs = int(data.get("eggs", 0))
	feed = int(data.get("feed", 5))
	shells = int(data.get("shells", 0))
	coop_hp = float(data.get("coop_hp", 300.0))
	player_gender = str(data.get("gender", "male"))
	stand_tier = clampi(int(data.get("stand_tier", 0)), 0, STAND_TIER_MAX)
	stand_eggs = int(data.get("stand_eggs", 0))
	_build_farm_stand()
	var loaded_upgrades = data.get("upgrades", {})
	for k in upgrades:
		if loaded_upgrades.has(k):
			upgrades[k] = loaded_upgrades[k]
	upgrades.fence = int(upgrades.fence)
	upgrades.coop = int(upgrades.coop)
	# the helmet upgrade used to be a single flock-wide switch; an old save
	# carrying it should not silently kit out the entire yard
	upgrades.helmets = false
	if upgrades.turret:
		_build_turret()
	var hens := int(data.get("hens", 10))
	for i in maxi(hens, 1):
		_spawn_chicken(rand_in_yard(), false)
	for i in int(data.get("roosters", 1 if upgrades.rooster else 0)):
		_spawn_rooster(rand_in_yard())
	_restore_progression(chickens, data.get("flock", []))
	_restore_progression(roosters, data.get("crew", []))

## Saved rosters are matched to spawned birds by index. A shorter list leaves
## the remainder as fresh recruits, which is what a grown flock should do.
func _restore_progression(birds: Array, saved) -> void:
	if not (saved is Array):
		return
	for i in mini(birds.size(), saved.size()):
		var row = saved[i]
		if not (row is Dictionary):
			continue
		birds[i].class_id = str(row.get("class", birds[i].class_id))
		if "helm" in row and "helmeted" in birds[i]:
			birds[i].helmeted = bool(row["helm"])
		birds[i].spec_id = str(row.get("spec", ""))
		if "days" in row and "days_survived" in birds[i]:
			birds[i].days_survived = int(row["days"])
		var tr = row.get("tracks", {})
		if tr is Dictionary:
			var clean := CL.new_tracks()
			for k in clean:
				clean[k] = int(tr.get(k, 0))
			birds[i].tracks = clean
		birds[i].refresh_class()

# ---------------- automated screenshot test ----------------

func _run_shot_test(dir: String) -> void:
	start_new()
	phase_t = 0.35  # mid-morning light for the day shot
	# pose a few chickens in front of the camera, facing it, frozen
	for i in mini(5, chickens.size()):
		chickens[i].position = Vector3(-11.5 + float(i) * 0.9, 0, 1.6 - absf(float(i) - 2.0) * 0.5)
		chickens[i].rotation.y = 0.0
		chickens[i].state = "carried"  # test-only: freezes the AI for the photo
	await get_tree().create_timer(2.0).timeout
	# regression check: synthetic mouse motion must rotate the camera
	var rot_before: float = player.rotation.y
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(200, 0)
	Input.parse_input_event(ev)
	await get_tree().process_frame
	print("TEST mouselook: %s" % ("OK" if absf(player.rotation.y - rot_before) > 0.01 else "FAILED"))
	# walk cycle: a moving chicken's legs must actually swing
	var walker = chickens[9]
	walker.state = "wander"
	walker.position = Vector3(-6, 0, 6)
	walker._target = Vector3(6, 0, 6)
	walker._timer = 9.0
	var leg_swing := 0.0
	for i in 30:
		walker.tick(0.05)
		leg_swing = maxf(leg_swing, absf(walker._legs[0].rotation.x))
	print("TEST walkcycle: %s (max swing %.2f rad)" % ["OK" if leg_swing > 0.15 else "FAILED", leg_swing])
	# rooster gate: 10 hens -> cap 1
	print("TEST rooster_cap(10 hens): %s (cap=%d)" % ["OK" if rooster_cap() == 1 else "FAILED", rooster_cap()])
	_spawn_rooster(Vector3(-8, 0, 4))
	var roo = roosters[0]
	# with 10 hens and 1 rooster owned, the listing must now read LOCKED
	var listing := _rooster_listing()
	print("TEST rooster gate at cap: %s" % ["OK" if listing.owned and "LOCKED" in listing.name else "FAILED"])
	# 11th hen still isn't enough; the 20th unlocks rooster #2
	for i in 10:
		_spawn_chicken(rand_in_yard(), false)
	print("TEST rooster unlock at 20 hens: %s (cap=%d)" % ["OK" if not _rooster_listing().owned and rooster_cap() == 2 else "FAILED", rooster_cap()])
	print("TEST audio loaded: cluck=%s crow=%s shotgun=%s" % [sfx._streams.has("real_cluck"), sfx._streams.has("real_crow"), sfx._streams["shot"] is AudioStreamMP3])
	# rate limiter: from a clear cooldown, 20 rapid cluck() calls must fire exactly once
	sfx._cluck_cd = 0.0
	var played := 0
	for i in 20:
		var before: float = sfx._cluck_cd
		sfx.cluck()
		if sfx._cluck_cd > before:
			played += 1
	print("TEST cluck ratelimit: %s (%d/20 fired)" % ["OK" if played == 1 else "FAILED", played])
	await _shot(dir + "/day.png")
	# bed: sleeping carries the clock all the way to nightfall
	player.rotation.y = PI  # face the gate
	var was_night := is_night
	sleep_until_night()
	await get_tree().create_timer(4.0).timeout
	print("TEST bed sleep: %s (night %s -> %s)" % ["OK" if is_night and not was_night else "FAILED", was_night, is_night])
	# ...and is refused once it's dark
	var t_before := phase_t
	sleep_until_night()
	print("TEST bed blocked at night: %s" % ["OK" if is_equal_approx(phase_t, t_before) and not sleeping else "FAILED"])
	await get_tree().create_timer(4.0).timeout
	await _shot(dir + "/night.png")
	# freeze the wave so the yard stays empty for a deterministic check
	_spawn_left = 0
	var kept = enemies[0] if enemies.size() > 0 else null
	for e in enemies.duplicate():
		if e != kept:
			enemies.erase(e)
			e.queue_free()
	if kept != null:
		kept.position = Vector3(0, 0, 300)
	for i in 60:
		roo.tick(0.05)
	print("TEST rooster perch: %s (state=%s, y=%.2f)" % ["OK" if roo.state == "perch" and roo.position.y > 3.0 else "FAILED", roo.state, roo.position.y])
	# bring it back near the coop: he must launch off the roof and land a hit
	if kept != null:
		kept.position = coop_pos + Vector3(3, 0, 0)
		kept.entered = true
		var hp_before: float = kept.hp
		for i in 40:
			roo.tick(0.05)
		print("TEST rooster swoop: %s (state=%s, enemy hp %.0f -> %.0f)" % ["OK" if roo.state == "swoop" and kept.hp < hp_before else "FAILED", roo.state, hp_before, kept.hp])
	# pose the rooster for his portrait
	player.position = Vector3(-9.5, 0.1, 5)
	player.rotation.y = 0.0
	player.cam.rotation.x = -0.1
	roo.state = "strut"
	roo.position = Vector3(-9.5, 0, 2.4)  # in front of the camera (-Z)
	roo.rotation.y = deg_to_rad(48)       # three-quarter view
	phase_t = 0.4
	is_night = false
	moon.visible = false
	_update_environment()
	await get_tree().create_timer(0.4).timeout
	await _shot(dir + "/rooster.png")
	await _portrait(dir + "/goblins.png", "goblin", 5, 3.4)
	await _portrait(dir + "/dragon.png", "dragon", 1, 19.0)
	get_tree().quit()

## Spawn a lineup of one enemy type in daylight and photograph it.
func _portrait(path: String, theme_id: String, count: int, dist: float) -> void:
	for e in enemies.duplicate():
		enemies.erase(e)
		e.queue_free()
	var thm := {}
	for t in EnemyScript.THEMES:
		if t.id == theme_id:
			thm = t
	# the camera looks down -Z, so the lineup goes in front at negative z
	for i in count:
		var e = EnemyScript.new()
		add_child(e)
		e.setup(self, 6, thm, false)
		var spread := (float(i) - float(count - 1) * 0.5)
		e.position = Vector3(spread * 1.6, 0, -dist - absf(spread) * 0.8)
		# +Z faces the camera; the dragon turns for a three-quarter wing view
		e.rotation.y = deg_to_rad(52) if theme_id == "dragon" else spread * 0.14
		e.state = "pose"
		enemies.append(e)
	# clear the flock out of frame
	for c in chickens:
		c.position = Vector3(26, 0, -2)
		c.state = "carried"
	for r in roosters:
		r.position = Vector3(26, 0, 2)
		r.state = "perch"
	player.position = Vector3(0, 0.1, 0)
	player.rotation.y = 0.0
	player.cam.rotation.x = -0.12 if theme_id == "goblin" else 0.02
	is_night = false
	moon.visible = false
	phase_t = 0.4
	_update_environment()
	await get_tree().create_timer(0.5).timeout
	await _shot(path)

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved shot: " + path)
