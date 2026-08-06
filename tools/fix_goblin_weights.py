"""Repair the goblin's hand/foot skin weights and export a fixed glb.

The auto-rigger weighted this model by proximity, and the goblin stands hunched
with its claws down by its toes, so ~1400 vertices came out pulled partly by an
arm bone and partly by a leg bone. Averaging two limbs that move in opposite
directions is what stretches the geometry when an arm lifts.

The mesh is 301 disconnected shells rather than one manifold, and the big ones
are anatomically coherent (torso+arm, leg, foot), so the fix decides each
contested vertex by what it is *connected to* through the mesh rather than by
whichever weight happened to be larger. A toe vertex reaches the ankle in a few
hops along the surface; the hand resting on top of it is not connected at all,
however close the two are in space.

Where geometry really is welded across the two limbs, the shared edges are
split rather than the faces deleted, so the seam can open instead of a hole
appearing in the model.

Both the reweighting and the split happen inside one bmesh and are written back
once — editing mesh.vertices[].groups alongside a live bmesh loses the weights,
because to_mesh() writes back state captured before the edit.

This has already been run and its result is what models/goblin.glb contains; it
is kept so the edit is reproducible and reviewable rather than a mystery baked
into a binary. To re-run it against a fresh export from the rigger:

    pip install bpy          # needs Python 3.11 for Blender 5.x wheels
    python3 tools/fix_goblin_weights.py out.glb

It reads models/goblin.glb, so point SRC at the raw export first — running it
twice over its own output is harmless but pointless, as there is nothing left
contested to fix.
"""
import sys
from collections import deque

import bpy  # must come first: bmesh only registers once bpy has initialised
import bmesh

SRC = "/home/user/last-chicken-defense/models/goblin.glb"
OUT = sys.argv[-1] if sys.argv[-1].endswith(".glb") else "/tmp/goblin_fixed.glb"

ARM, LEG, BODY = 1, 2, 0

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

arm_obj = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
mesh_obj = [o for o in bpy.data.objects if o.type == "MESH" and len(o.vertex_groups) > 0][0]
me = mesh_obj.data
bones = {b.name: b for b in arm_obj.data.bones}


def desc(name):
    out, q = set(), deque([bones[name]])
    while q:
        b = q.popleft()
        out.add(b.name)
        q.extend(b.children)
    return out


# the two limb families, taken from the rig hierarchy rather than index ranges
ARM_BONES = desc("Bone_023") | desc("Bone_028")   # both shoulders down to the claws
LEG_BONES = desc("Bone_010") | desc("Bone_015")   # both hips down to the toes
arm_gi = {g.index for g in mesh_obj.vertex_groups if g.name in ARM_BONES}
leg_gi = {g.index for g in mesh_obj.vertex_groups if g.name in LEG_BONES}
print("arm groups: %d  leg groups: %d  (of %d)"
      % (len(arm_gi), len(leg_gi), len(mesh_obj.vertex_groups)))

bm = bmesh.new()
bm.from_mesh(me)
bm.verts.ensure_lookup_table()
deform = bm.verts.layers.deform.active
assert deform is not None, "mesh carries no vertex weights"


def limb_weight(v):
    d = v[deform]
    a = l = 0.0
    for gidx, w in d.items():
        if gidx in arm_gi:
            a += w
        elif gidx in leg_gi:
            l += w
    return a, l


# ---- 1. label the vertices that are not in doubt ---------------------------
n = len(bm.verts)
label = [None] * n
contested = []
for v in bm.verts:
    a, l = limb_weight(v)
    if a > 0.02 and l > 0.02:
        contested.append(v.index)          # pulled by both limbs: the defect
    elif a + l < 0.02:
        label[v.index] = BODY              # spine, head, pelvis — not our business
    elif a > l:
        label[v.index] = ARM               # arm plus torso is normal and fine
    else:
        label[v.index] = LEG
print("seeds: arm=%d leg=%d body=%d   contested=%d"
      % (label.count(ARM), label.count(LEG), label.count(BODY), len(contested)))

# ---- 2. propagate along the surface: nearest confident seed by hop count ---
adj = [[] for _ in range(n)]
for e in bm.edges:
    a, b = e.verts[0].index, e.verts[1].index
    adj[a].append(b)
    adj[b].append(a)

dist = [-1] * n
q = deque()
for i in range(n):
    if label[i] in (ARM, LEG):
        dist[i] = 0
        q.append(i)
resolved = list(label)
while q:
    x = q.popleft()
    for y in adj[x]:
        if dist[y] == -1 and label[y] not in (ARM, LEG):
            dist[y] = dist[x] + 1
            resolved[y] = resolved[x]
            q.append(y)

by_graph = 0
leftover = []
for i in contested:
    if resolved[i] in (ARM, LEG):
        label[i] = resolved[i]
        by_graph += 1
    else:
        leftover.append(i)

# Whatever is left sits in a shell with no confident vertex anywhere in it — a
# loose claw or toe plate that is contested end to end. There is no surface path
# to a seed, so decide the shell as a whole from its summed weight instead of
# vertex by vertex: one little island moving as a piece is right either way,
# where a split one tears.
island_of = [-1] * n
islands = []
for s in range(n):
    if island_of[s] != -1:
        continue
    comp, q2 = [], deque([s])
    island_of[s] = len(islands)
    while q2:
        x = q2.popleft()
        comp.append(x)
        for y in adj[x]:
            if island_of[y] == -1:
                island_of[y] = len(islands)
                q2.append(y)
    islands.append(comp)

by_island = 0
for isl in {island_of[i] for i in leftover}:
    a_sum = l_sum = 0.0
    for vi in islands[isl]:
        a, l = limb_weight(bm.verts[vi])
        a_sum += a
        l_sum += l
    lab = ARM if a_sum >= l_sum else LEG
    for vi in islands[isl]:
        if label[vi] is None:
            label[vi] = lab
            by_island += 1
print("contested resolved: %d by mesh connectivity, %d by whole-shell vote"
      % (by_graph, by_island))
assert None not in label, "every vertex must end up labelled"

disagreed = 0
for i in contested:
    a, l = limb_weight(bm.verts[i])
    if (ARM if a >= l else LEG) != label[i]:
        disagreed += 1
print("this disagreed with the old bigger-share rule on %d of %d contested"
      % (disagreed, len(contested)))

# ---- 3. move the decision up to whole faces --------------------------------
# A vertex label is not enough on its own. A triangle with two arm corners and
# one leg corner still stretches between the limbs whatever its corners say, so
# each face has to belong to one limb outright. Faces take the majority of their
# corners; ties go to the arm, which is the limb that actually moves.
face_label = {}
for f in bm.faces:
    votes = [label[v.index] for v in f.verts]
    a = votes.count(ARM)
    l = votes.count(LEG)
    # keyed by the face object, not its index: split_edges may reindex
    if a == 0 and l == 0:
        face_label[f] = BODY
    else:
        face_label[f] = ARM if a >= l else LEG

# ---- 4. cut the two limbs apart along the boundary between them ------------
# Split every edge with an arm face on one side and a leg face on the other, so
# the arm surface and the leg surface stop sharing vertices. Nothing is deleted
# — the seam simply becomes free to open instead of a hole appearing.
# ARM<->BODY is the shoulder and LEG<->BODY is the hip; both stay attached.
seam = []
for e in bm.edges:
    labs = {face_label[f] for f in e.link_faces}
    if ARM in labs and LEG in labs:
        seam.append(e)
before_v, before_f = len(bm.verts), len(bm.faces)
if seam:
    bmesh.ops.split_edges(bm, edges=seam)
bm.verts.ensure_lookup_table()
bm.faces.ensure_lookup_table()
print("seam edges between an arm face and a leg face: %d" % len(seam))
print("split: verts %d -> %d, faces %d -> %d (no faces removed)"
      % (before_v, len(bm.verts), before_f, len(bm.faces)))

# ---- 5. rewrite the weights from the face labels ---------------------------
# After the split almost every vertex is used only by faces of one limb, so the
# limb a vertex belongs to is now unambiguous. Whatever is still shared (faces
# meeting at a single corner rather than along an edge) takes the majority.
vert_label = {}
mixed_corner = 0
for v in bm.verts:
    labs = [face_label[f] for f in v.link_faces if face_label[f] != BODY]
    if not labs:
        vert_label[v.index] = BODY
        continue
    a = labs.count(ARM)
    l = labs.count(LEG)
    if a > 0 and l > 0:
        mixed_corner += 1
    vert_label[v.index] = ARM if a >= l else LEG
print("vertices still touching both limbs at a corner: %d" % mixed_corner)

# Off-limb entries are deleted rather than zeroed, so the influence count per
# vertex actually drops — Godot truncates the skin to 8 influences on import
# and this model carries up to 10, so every entry removed is one less lost.
stripped = 0
for v in bm.verts:
    lab = vert_label[v.index]
    if lab == BODY:
        continue
    drop = leg_gi if lab == ARM else arm_gi
    d = v[deform]
    gone = [g for g in d.keys() if g in drop]
    if gone:
        for g in gone:
            del d[g]
        stripped += 1
    total = sum(d.values())
    if total > 0.0001:
        for g in list(d.keys()):
            d[g] = d[g] / total
print("vertices whose off-limb weight was removed: %d" % stripped)

bm.to_mesh(me)
bm.free()
me.update()

# ---- 5. export -------------------------------------------------------------
bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format="GLB",
    export_image_format="AUTO",   # keep the source jpg/png encodings
    export_yup=True,
    use_selection=False,
    export_skins=True,
    export_all_influences=True,   # do not silently truncate on the way out
    export_apply=False,
)
print("wrote", OUT)
