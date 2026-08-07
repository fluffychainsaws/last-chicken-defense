# The goblin rig

Reference notes for `models/goblin.glb`. Written down because working any of it
out again costs an afternoon of rendering candidates and parsing buffers.

The model came from Meshy.ai, auto-rigged by UniRig. It is a sculpt with
hand-painted textures and a machine-generated skeleton, and almost every
surprise below follows from that split.

## Files

| file | what it is |
| --- | --- |
| `models/goblin.glb` | the model, with the skin-weight repair baked in |
| `models/goblin_base_color.jpg` etc. | extracted on import by Godot, **gitignored** |
| `tools/fix_goblin_weights.py` | the bpy script that produced the repaired glb |

The four texture files are not junk. Godot's importer is set to
`gltf/embedded_image_handling=1` (Extract Textures), which writes them next to
the model and makes them hard dependencies of the imported `.scn`. Deleting
them renders every goblin untextured white. They regenerate if you clear
`.godot/imported/` and re-import, which is why they are gitignored rather than
committed.

## Skeleton

53 bones, generic names, no semantic naming at all — UniRig numbers them and
that is that. The hierarchy:

```
Bone_000  (root)
└── Bone_001  (hips)
    ├── Bone_005 → 004 → 003 → Bone_002   (spine up to the chest)
    │   ├── Bone_018 → 017 → 016          (neck, head)
    │   ├── Bone_023 → 022 → 021 → 020 → Bone_019   (RIGHT arm to wrist)
    │   │   └── three finger chains: 032…, 036…, 040…
    │   └── Bone_028 → 027 → 026 → 025 → Bone_024   (LEFT arm to wrist)
    │       └── three finger chains: 044…, 048…, 052…
    ├── Bone_010 → 009 → 008 → 007 → 006   (RIGHT leg to toes)
    └── Bone_015 → 014 → 013 → 012 → 011   (LEFT leg to toes)
```

`+Z` is up in this rig. Feet sit at `z ≈ -0.05`, the head at `z ≈ 1.58`.

### The indices `enemy.gd` hardcodes

**Blender's bone order and Godot's `Skeleton3D` order are identical** for this
model — verified by dumping both lists and diffing all 53. So an index means the
same bone in either tool, and these constants are safe to use from both:

| index | bone | role | constant in `enemy.gd` |
| --- | --- | --- | --- |
| 9 | `Bone_023` | right shoulder | `GOBLIN_BONE_R_SHOULDER` |
| 13 | `Bone_019` | right wrist | `GOBLIN_BONE_R_WRIST` |
| 26 | `Bone_028` | left shoulder | `GOBLIN_BONE_L_SHOULDER` |
| 30 | `Bone_024` | left wrist | `GOBLIN_BONE_L_WRIST` |
| 43 | `Bone_010` | right hip | `GOBLIN_BONE_R_HIP` |
| 48 | `Bone_015` | left hip | `GOBLIN_BONE_L_HIP` |

Do not assume this ordering holds for a *different* export. Re-check it with a
diff before trusting indices on any new file out of the rigger.

## Mesh

13,988 verts and 19,123 tris before the repair; 14,032 verts after (the seam
split duplicated some), same 19,123 tris.

**It is not a manifold.** The mesh is **301 disconnected shells**, the largest
only 896 verts. Up to 10 bone influences per vertex, which Godot truncates to 8
on import.

The big shells are anatomically coherent, which is what makes per-vertex repair
tractable:

| shell | verts | what it is |
| --- | --- | --- |
| 12 | 896 | torso + right arm |
| 37 | 659 | torso + left arm |
| 84 | 413 | right leg |
| 107 | 281 | left leg |
| 122 | 162 | right foot |

114 of the 301 shells have fewer than 10 verts — loose claw and toe plates.

## The defect, and the repair

UniRig weighted by proximity. The goblin stands hunched with its claws down
beside its toes, so **1,373 vertices** ended up pulled partly by an arm bone and
partly by a leg bone. Averaging two limbs that move in opposite directions is
what tore the model when an arm lifted.

`tools/fix_goblin_weights.py` fixes it in three moves:

1. **Decide by connectivity, not by weight.** A contested vertex goes to
   whichever limb reaches it in fewer hops *along the mesh surface*. A toe
   reaches the ankle in a few hops; the hand resting on top of it is not
   connected at all, however close in space. This disagreed with the naive
   "whichever share was larger" rule on **256 vertices**.
2. **Shells with no confident vertex anywhere** are decided as a whole from
   their summed weight — a little plate moving as one piece is right either way,
   where a split one tears. 409 vertices resolved this way.
3. **Promote the decision to whole faces, then split the seam.** A triangle with
   two arm corners and one leg corner stretches between the limbs whatever its
   corners say, so faces take their corners' majority and the edges where an arm
   face meets a leg face are *split*, not deleted. No hole appears.

Measured on the arms-up carry pose, per-edge rest length against posed length:

| | worst stretch | >2x | >5x | >10x |
| --- | --- | --- | --- | --- |
| before | 27.5x | 1352 | 501 | 184 |
| after | 3.0x | 142 | 0 | 0 |

Contested vertices went 1373 → 0. Foot vertices now move exactly 0.0 when the
arms lift, where 296 of them used to travel up to 0.998 units on a 1.7-unit
model. The residual 142 edges at up to 3x are ordinary creasing at the shoulder
and hip under a 150° rotation.

## Gotchas, all of them learned the hard way

**bpy**

- `import bpy` must come before `import bmesh`. bmesh only registers once bpy
  has initialised, so alphabetised imports fail with `ModuleNotFoundError`.
- Do not edit `mesh.vertices[].groups[].weight` while a bmesh is live over the
  same mesh. `bm.to_mesh()` writes back state captured at `from_mesh()` time and
  silently discards the weight edits. Use `bm.verts.layers.deform` so both the
  weights and the topology live in one bmesh, written back once.
- Key face lookups on the `BMFace` object, not `f.index` — `split_edges` can
  reindex faces.
- Delete off-limb deform entries rather than zeroing them, so the influence
  count actually drops. Godot truncates to 8 and this model carries up to 10.

**Godot**

- `set_bone_pose_rotation()` **replaces** the rotation including the rest pose.
  Compose with the rest: `q * get_bone_rest(b).basis.get_rotation_quaternion()`.
- Pre-multiply (`q * rest`) rotates in parent space, which is what the walk and
  the arm lift want. Post-multiply (`rest * q`) rotates in the bone's local
  space and splays the legs sideways.
- Height is exactly 1.7, which is what `GOBLIN_MODEL_HEIGHT` encodes. Re-measure
  the AABB if the mesh is ever re-exported.

**The sandbox, if you are working in the cloud container rather than locally**

- Its Godot is 4.3 while the project targets 4.7. `Environment.TONE_MAPPER_AGX`
  does not parse in 4.3, so headless runs need a temporary swap to
  `TONE_MAPPER_FILMIC` and a swap back afterwards. Never commit the FILMIC one.
- Running Godot 4.3 against the project **rewrites `project.godot`**: it
  downgrades `config/features` from 4.7 to 4.3 and deletes the whole
  `[rendering]` section, including the WebGL2 compatibility renderer the web
  build needs. Check `git diff project.godot` before every commit.
