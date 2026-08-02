extends RefCounted
## Hen and rooster classes, specialisations and upgrade tracks.
##
## Pure data plus the maths that reads it. Nothing here touches the scene tree,
## so the whole progression system can be reasoned about — and tested — without
## spawning a bird.
##
## Shape of progression: a plain hen is promoted into a class, invests points
## across seven tracks, and at track-total 6 picks a specialisation that bends
## the class in a direction. Rank is derived from total investment, so the title
## always reflects what has actually been spent.

## Ten rungs, deliberately shabby at the bottom and absurd at the top.
const RANKS := [
	"Fledgling", "Scrapper", "Yardhand", "Bruiser", "Veteran",
	"Champion", "Warlord", "Paragon", "Mythic", "THE ARMAEGGON",
]

## Points across all tracks needed to reach each rank index above.
const RANK_STEPS := [0, 2, 5, 9, 14, 20, 27, 35, 44, 54]

## Every track applies to every class; the class just changes what matters.
## `per` is the gain per point — a fraction for multipliers, flat for the rest.
const TRACKS := {
	"damage": {"name": "Damage", "desc": "hits harder", "max": 10, "cost": 30, "per": 0.22},
	"haste": {"name": "Haste", "desc": "attacks more often", "max": 8, "cost": 34, "per": 0.12},
	"range": {"name": "Reach", "desc": "engages from further out", "max": 8, "cost": 28, "per": 0.18},
	"vigor": {"name": "Vigor", "desc": "more health", "max": 10, "cost": 26, "per": 0.25},
	"armor": {"name": "Armor", "desc": "takes less damage", "max": 8, "cost": 32, "per": 0.05},
	"dodge": {"name": "Dodge", "desc": "chance to avoid a hit entirely", "max": 6, "cost": 38, "per": 0.045},
	"move": {"name": "Footwork", "desc": "moves faster", "max": 6, "cost": 24, "per": 0.14},
}
const TRACK_ORDER := ["damage", "haste", "range", "vigor", "armor", "dodge", "move"]

## Points invested before a specialisation can be chosen.
const SPEC_AT := 6

## ranged: fires projectiles. perch: fights from the coop roof instead of the yard.
const CLASSES := {
	"hen": {
		"name": "Hen", "desc": "hides in the coop and hopes for the best.",
		"price": 0, "dmg": 4.0, "range": 1.6, "cd": 0.8, "hp": 25.0,
		"speed": 1.0, "armor": 0.0, "dodge": 0.0, "ranged": false, "perch": false,
		"colour": Color(0.92, 0.9, 0.86), "specs": [],
	},
	"battle": {
		"name": "Battle Hen", "desc": "has decided the yard is hers.",
		"price": 140, "dmg": 9.0, "range": 1.9, "cd": 0.62, "hp": 40.0,
		"speed": 1.15, "armor": 0.05, "dodge": 0.05, "ranged": false, "perch": false,
		"colour": Color(0.78, 0.36, 0.24),
		"specs": {
			"brawler": {"name": "Brawler", "desc": "slower swings, ruinous ones.", "dmg": 1.6, "cd": 1.35, "range": 1.0, "hp": 1.1},
			"duelist": {"name": "Duelist", "desc": "a flurry, and hard to pin down.", "dmg": 0.75, "cd": 0.55, "range": 1.0, "dodge": 0.12},
			"gladiator": {"name": "Gladiator", "desc": "built to be hit and keep going.", "dmg": 1.15, "cd": 1.0, "range": 1.1, "hp": 1.5, "armor": 0.12},
		},
	},
	"archer": {
		"name": "Archer Hen", "desc": "quills, drawn and loosed.",
		"price": 190, "dmg": 7.0, "range": 14.0, "cd": 1.05, "hp": 26.0,
		"speed": 1.05, "armor": 0.0, "dodge": 0.08, "ranged": true, "perch": false,
		"colour": Color(0.38, 0.55, 0.32),
		"specs": {
			"ranger": {"name": "Ranger", "desc": "quick, mobile, endlessly nocking.", "dmg": 0.85, "cd": 0.6, "range": 1.0, "speed": 1.2},
			"sniper": {"name": "Sniper", "desc": "one quill, one goblin, most of the yard away.", "dmg": 2.4, "cd": 2.0, "range": 1.7},
			"hunter": {"name": "Hunter", "desc": "shoots a spread; nothing gets past cleanly.", "dmg": 0.7, "cd": 0.9, "range": 0.85, "shots": 3},
		},
	},
	"mage": {
		"name": "Mage Hen", "desc": "she has read things a chicken should not.",
		"price": 240, "dmg": 11.0, "range": 12.0, "cd": 1.4, "hp": 22.0,
		"speed": 0.95, "armor": 0.0, "dodge": 0.05, "ranged": true, "perch": false,
		"colour": Color(0.42, 0.32, 0.66),
		"specs": {
			"pyromancer": {"name": "Pyromancer", "desc": "sets them alight and lets it spread.", "dmg": 1.5, "cd": 1.1, "range": 0.95, "burn": true, "shot": Color(1.0, 0.45, 0.12)},
			"hydromancer": {"name": "Hydromancer", "desc": "a cold jet, relentless and quick.", "dmg": 0.7, "cd": 0.5, "range": 1.1, "shot": Color(0.3, 0.7, 1.0)},
			"geomancer": {"name": "Geomancer", "desc": "hurls the yard itself. splashes.", "dmg": 1.3, "cd": 1.5, "range": 0.85, "splash": 3.2, "shot": Color(0.62, 0.46, 0.28)},
			"aeromancer": {"name": "Aeromancer", "desc": "thin, fast, and it never misses far.", "dmg": 0.9, "cd": 0.55, "range": 1.45, "shot": Color(0.75, 0.95, 1.0)},
			"summoner": {"name": "Summoner", "desc": "calls up a chick to fight beside her.", "dmg": 0.9, "cd": 1.2, "range": 1.0, "summon": true, "shot": Color(0.55, 1.0, 0.6)},
			"necromancer": {"name": "Necromancer", "desc": "the yard's dead do not stay retired.", "dmg": 1.1, "cd": 1.3, "range": 1.05, "raise": true, "shot": Color(0.45, 0.9, 0.45)},
		},
	},
	"knight": {
		"name": "Knight Hen", "desc": "plate, and the conviction to wear it.",
		"price": 260, "dmg": 10.0, "range": 2.1, "cd": 0.95, "hp": 70.0,
		"speed": 0.82, "armor": 0.25, "dodge": 0.0, "ranged": false, "perch": false,
		"colour": Color(0.62, 0.64, 0.7),
		"specs": {
			"paladin": {"name": "Paladin", "desc": "unkillable, and mends the flock nearby.", "dmg": 0.9, "cd": 1.0, "range": 1.0, "hp": 1.4, "armor": 0.15, "aura_heal": 3.0},
			"berserker": {"name": "Berserker", "desc": "drops the shield. hits like a barn door.", "dmg": 2.2, "cd": 0.7, "range": 1.0, "armor": -0.15, "speed": 1.3},
			"templar": {"name": "Templar", "desc": "holds the line and blunts what strikes it.", "dmg": 1.05, "cd": 1.0, "range": 1.3, "armor": 0.22, "hp": 1.25},
		},
	},
	"military": {
		"name": "Military Hen", "desc": "sits on the coop roof with a gun. do not ask.",
		"price": 320, "dmg": 8.0, "range": 22.0, "cd": 0.5, "hp": 30.0,
		"speed": 0.9, "armor": 0.1, "dodge": 0.0, "ranged": true, "perch": true,
		"colour": Color(0.36, 0.42, 0.3),
		"specs": {
			"gunner": {"name": "Gunner", "desc": "suppressing fire, all night, no questions.", "dmg": 0.7, "cd": 0.4, "range": 1.0},
			"grenadier": {"name": "Grenadier", "desc": "lobs. everything near it regrets that.", "dmg": 1.4, "cd": 2.0, "range": 0.9, "splash": 4.0},
			"sharpshooter": {"name": "Sharpshooter", "desc": "reaches the treeline from the roof.", "dmg": 2.0, "cd": 1.6, "range": 1.5},
		},
	},
}

## The rooster gets his own line — he already divebombs, so his upgrades sharpen
## that rather than turning him into something else.
const ROOSTER := {
	"name": "Rooster", "desc": "the yard's furious little air force.",
	"dmg": 12.0, "range": 18.0, "cd": 1.6, "hp": 45.0,
	"speed": 1.0, "armor": 0.05, "dodge": 0.1, "ranged": false, "perch": false,
	"colour": Color(0.15, 0.13, 0.16),
	"specs": {
		"warcock": {"name": "War Rooster", "desc": "heavier dives, and he lands them.", "dmg": 1.6, "cd": 1.1, "range": 1.0, "hp": 1.3},
		"herald": {"name": "Herald", "desc": "his crow drives the flock into a fury.", "dmg": 0.9, "cd": 1.0, "range": 1.2, "aura_dmg": 0.2},
		"tyrant": {"name": "Tyrant", "desc": "nothing in the yard outranks him.", "dmg": 2.1, "cd": 1.4, "range": 1.1, "hp": 1.6, "armor": 0.15},
	},
}

static func base_of(class_id: String) -> Dictionary:
	if class_id == "rooster":
		return ROOSTER
	return CLASSES.get(class_id, CLASSES["hen"])

static func specs_of(class_id: String) -> Dictionary:
	var b := base_of(class_id)
	var s = b.get("specs", {})
	return s if s is Dictionary else {}

static func points_spent(tracks: Dictionary) -> int:
	var n := 0
	for k in tracks:
		n += int(tracks[k])
	return n

static func rank_index(tracks: Dictionary) -> int:
	var p := points_spent(tracks)
	var idx := 0
	for i in RANK_STEPS.size():
		if p >= RANK_STEPS[i]:
			idx = i
	return idx

static func rank_name(tracks: Dictionary) -> String:
	return RANKS[rank_index(tracks)]

## Level reads as 1..10 so the screen can show something friendlier than points.
static func level(tracks: Dictionary) -> int:
	return rank_index(tracks) + 1

## Cost rises with the rank already bought in that track, so the last point in a
## line always hurts more than the first.
static func track_cost(track: String, owned: int) -> int:
	var base: int = TRACKS[track]["cost"]
	return int(round(base * (1.0 + 0.55 * float(owned))))

static func can_spec(tracks: Dictionary) -> bool:
	return points_spent(tracks) >= SPEC_AT

## Final numbers for a bird: class base, bent by its specialisation, then scaled
## by whatever has been poured into the tracks.
static func stats(class_id: String, spec_id: String, tracks: Dictionary) -> Dictionary:
	var b := base_of(class_id)
	var sp: Dictionary = specs_of(class_id).get(spec_id, {})
	var t := func(k: String) -> float:
		return float(tracks.get(k, 0)) * float(TRACKS[k]["per"])
	var dmg: float = float(b["dmg"]) * float(sp.get("dmg", 1.0)) * (1.0 + t.call("damage"))
	# a spec's cd is a multiplier on the interval, so >1 is slower and hits harder
	var cd: float = float(b["cd"]) * float(sp.get("cd", 1.0)) / (1.0 + t.call("haste"))
	var rng: float = float(b["range"]) * float(sp.get("range", 1.0)) * (1.0 + t.call("range"))
	var hp: float = float(b["hp"]) * float(sp.get("hp", 1.0)) * (1.0 + t.call("vigor"))
	var armor: float = clampf(float(b["armor"]) + float(sp.get("armor", 0.0)) + t.call("armor"), 0.0, 0.85)
	var dodge: float = clampf(float(b["dodge"]) + float(sp.get("dodge", 0.0)) + t.call("dodge"), 0.0, 0.6)
	var speed: float = float(b["speed"]) * float(sp.get("speed", 1.0)) * (1.0 + t.call("move"))
	return {
		"dmg": dmg, "cd": maxf(cd, 0.08), "range": rng, "hp": hp,
		"armor": armor, "dodge": dodge, "speed": speed,
		"ranged": bool(b.get("ranged", false)),
		"perch": bool(b.get("perch", false)),
		"shots": int(sp.get("shots", 1)),
		"splash": float(sp.get("splash", 0.0)),
		"burn": bool(sp.get("burn", false)),
		"summon": bool(sp.get("summon", false)),
		"aura_heal": float(sp.get("aura_heal", 0.0)),
		"aura_dmg": float(sp.get("aura_dmg", 0.0)),
		"shot_colour": sp.get("shot", Color(0.95, 0.95, 0.8)),
		"colour": b["colour"],
	}

## Human-readable title, e.g. "Veteran Pyromancer" or "Scrapper Battle Hen".
static func title(class_id: String, spec_id: String, tracks: Dictionary) -> String:
	var b := base_of(class_id)
	var nm: String = b["name"]
	var sp: Dictionary = specs_of(class_id).get(spec_id, {})
	if not sp.is_empty():
		nm = sp["name"]
	return "%s %s" % [rank_name(tracks), nm]

static func new_tracks() -> Dictionary:
	var d := {}
	for k in TRACK_ORDER:
		d[k] = 0
	return d
