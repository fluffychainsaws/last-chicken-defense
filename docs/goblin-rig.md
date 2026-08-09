# The goblin rig

To work on this model in a live Blender rather than by rendering stills, set the
bridge up first — see [blender-bridge.md](blender-bridge.md).

Reference notes for `models/goblin.glb`, a Meshy.ai goblin warrior on a
Mixamo-style biped rig with nine animation clips.

## Files

| file | what it is |
| --- | --- |
| `models/goblin.glb` | the model, prepared by the script below |
| `models/goblin_texture_0.png` | extracted on import by Godot, **gitignored** |
| `tools/prep_goblin.py` | strips the emission Meshy bakes in; run on any fresh export |

The texture is not junk. Godot's importer is set to
`gltf/embedded_image_handling=1` (Extract Textures), which writes it next to the
model and makes it a hard dependency of the imported `.scn`. Deleting it renders
every goblin untextured white. It regenerates if you clear `.godot/imported/`
and re-import, which is why it is gitignored rather than committed.

## Skeleton

24 bones, and — unlike the model this replaced — they have real names:

```
Hips
├── LeftUpLeg → LeftLeg → LeftFoot → LeftToeBase
├── RightUpLeg → RightLeg → RightFoot → RightToeBase
└── Spine02 → Spine01 → Spine
    ├── LeftShoulder → LeftArm → LeftForeArm → LeftHand
    ├── RightShoulder → RightArm → RightForeArm → RightHand
    └── neck → Head → (head_end, headfront)
```

Note the spine numbering runs *downward*: `Spine02` is the lowest, nearest the
hips, and plain `Spine` is the highest, carrying the shoulders.

Because the names are real, `enemy.gd` looks bones up with `find_bone()` instead
of hardcoding indices. Only one is needed at runtime — `RightHand`, which the
carried chicken hangs from. Godot happens to give it index 19, but nothing
depends on that, and a re-export that reorders the bones still works.

`+Z` is up in the glTF, the model faces `+Z` like the procedural enemies (so
`GOBLIN_MODEL_YAW` stays 0), and the mesh is exactly **1.7** tall, which is what
`GOBLIN_MODEL_HEIGHT` encodes.

**The skeleton is in centimetres.** The Hips rest origin sits at y≈92, and a
scale on the parent node brings it down to metres. This matters if you ever add
physics bodies to it: Godot's rigid bodies misbehave under scaled parents.

## Mesh

15,826 verts, 21,071 tris, **4 bone influences per vertex** — under Godot's
8-influence cap, so nothing is truncated on import.

One material, one colour texture. There is **no normal map**, unlike the model
this replaced; the leather and strap detail is painted into the base colour
instead. In practice it reads fine at the distance goblins are usually seen.

The model stands in a neutral A-pose, which is why its weights are clean. The
previous goblin was sculpted hunched with its claws down beside its toes, so the
auto-rigger could not tell hand from foot and bled the weights between them; see
the history section below.

## The animations, and what each drives

| clip | length | drives |
| --- | --- | --- |
| `Walking` | 1.00s | approaching the coop |
| `Running` | 0.62s | chasing the player |
| `Weapon_Combo` | 3.67s | attacking the coop or the player |
| `Male_Run_Forward_Pick_Up_Left` | 1.17s | stooping to grab a chicken |
| `Walk_with_Umbrella` | 1.33s | carrying one away |
| `Dead` | 2.96s | dying |
| `Fall_Dead_from_Abdominal_Injury` | 3.50s | dying |
| `Knock_Down` | 2.50s | dying |
| `Zombie_Scream` | 2.79s | unused; available for a spawn or taunt |

There is **no idle clip**, which turns out not to matter: a goblin is always
either moving or attacking, and both are covered.

`Walking`, `Running` and `Walk_with_Umbrella` are set to `LOOP_LINEAR` at load —
they import unlooped and would otherwise play once and freeze mid-stride.
Playback speed is scaled by how fast the body is actually moving so the feet do
not skate, and falls with body scale for the same pendulum reason the old
procedural walk used.

**The carry pose holds the bird at chest height, not overhead.** The clip was
authored for an umbrella, but at every point in the cycle the right hand sits at
y≈99-110 against a head at y≈140 — the arm folds across the body rather than
raising. The chicken therefore rides tucked under the arm. The original request
was for it held aloft; doing that would mean posing the shoulder on top of the
playing clip, which fights it.

## Two defects in the source export, and where each is fixed

**Emission — fixed in the asset, by `tools/prep_goblin.py`.** Meshy wires the
colour map in as an `emissiveTexture` at full strength and sets specular to 2.0,
which is not a physical value. Imported as-is the goblins *self-illuminate*: they
glow in the dark instead of being lit by the moon, which is exactly wrong for a
game whose threat happens at night. Run the script on any fresh export before
committing it.

Note that `enemy.gd` then re-enables the emission *channel* with its energy at
zero, because `damage()` flashes a hit by setting emission and that does nothing
on a material where the channel is switched off.

**Root motion — fixed at load, in `enemy.gd`.** The clips were authored to travel:

| clip | forward travel |
| --- | --- |
| `Male_Run_Forward_Pick_Up_Left` | 5.0 m |
| `Weapon_Combo` | 2.2 m |
| `Walk_with_Umbrella` | 1.2 m |
| `Dead` / `Fall_Dead` | 1.0–1.3 m |
| `Walking` / `Running` | ~5 cm (in-place already) |

Here the body's position belongs to the game — code decides where a goblin is and
the clip only says what shape it makes — so that translation slid the mesh clean
off the creature it belonged to and out of reach of the coop it was attacking.
`_pin_root()` pins the Hips' horizontal position to its rest value and leaves the
vertical alone, since that Y is the bob on a walk and the fall on a death. It
costs a few centimetres of hip sway, because one channel cannot distinguish sway
from drift.

`Weapon_Combo` also turns the hips through **165°** — it was authored as a
spinning combo for a character who picks their own facing. Ours is planted in
front of the coop, already turned to face it by code, so left alone it swung
away from the thing it was hitting. `_pin_yaw()` flattens that yaw while keeping
pitch and roll, which are the windup and the lean and most of what sells a blow.
The gait clips keep their 15-23° — that is hip sway, and removing it would make
the walk read as a mannequin on rails.

Both fixes live in code rather than the asset deliberately, so a fresh export
from Meshy gets them automatically.

## Gotchas

**Godot**

- `set_bone_pose_rotation()` **replaces** the rotation including the rest pose.
  Compose with it: `q * get_bone_rest(b).basis.get_rotation_quaternion()`.
  Pre-multiplying rotates in parent space, which is usually what you want;
  post-multiplying rotates in the bone's local space and splays limbs sideways.
  Little of this is needed now that clips drive the rig, but it still applies to
  anything posed by hand.
- Animation resources are **shared** between every instance loaded from the same
  scene, so a fix applied to one applies to all. Both fixes above check whether
  the work is already done rather than using a static flag, which would lie if
  the resource cache ever dropped the clips and handed a later spawn a fresh
  unmodified copy.

**bpy**, if you are running `tools/prep_goblin.py`

- `import bpy` must come before `import bmesh`; bmesh only registers once bpy has
  initialised, so alphabetised imports fail with `ModuleNotFoundError`.
- Zeroing Emission Strength is not enough to remove emission. The glTF exporter
  writes an `emissiveTexture` back out whenever the socket is *connected*, so the
  link itself has to go.

**The sandbox**, if you are working in the cloud container rather than locally

- Its Godot is 4.3 while the project targets 4.7. `Environment.TONE_MAPPER_AGX`
  does not parse in 4.3, so headless runs need a temporary swap to
  `TONE_MAPPER_FILMIC` and a swap back. Never commit the FILMIC one.
- Running Godot 4.3 against the project **rewrites `project.godot`**: it
  downgrades `config/features` from 4.7 to 4.3 and deletes the whole
  `[rendering]` section, including the WebGL2 compatibility renderer the web
  build needs. Check `git diff project.godot` before every commit.

## History: the goblin this replaced

The first goblin was a feral, hunched creature on a 53-bone UniRig auto-rig with
generic names (`Bone_023`), no animations at all, and four textures including a
normal map. Everything it did was posed frame by frame in code.

Its mesh was **301 disconnected shells** rather than one manifold, and because it
stood with its claws beside its toes the rigger — which weights by proximity —
could not tell the two apart. 1,373 vertices ended up pulled partly by an arm
bone and partly by a leg, so raising an arm dragged the feet and tore the
geometry between them: the worst edge stretched to **27.5×** its rest length.

`tools/fix_goblin_weights.py` repaired it, and the method is worth keeping in
mind for any future auto-rigged model: decide each contested vertex by what it is
*connected to* through the mesh rather than by whichever weight is larger — a toe
reaches the ankle in a few hops across the surface, while a hand resting on top
of it is not connected at all, however close in space. Then promote the decision
to whole faces, because a triangle with two arm corners and one leg corner
stretches whatever its corners say, and split the seam rather than deleting the
faces so no hole appears. That took the worst stretch from 27.5× to 3.0× with
zero faces removed.

The current model needs none of this: it is A-posed, so no limb is anywhere near
another, and its weights came out clean.
