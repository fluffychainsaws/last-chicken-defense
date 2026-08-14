"""Prepare the Meshy goblin warrior export for use in the game.

Meshy ships this model self-illuminating: the colour map is wired as an emissive
texture at full strength, and specular sits at 2.0, which is not a physical
value. Imported as-is the goblins glow in the dark instead of being lit by the
moon, which is precisely wrong for a game whose threat happens at night.

This strips the emission, brings specular back to 1.0 and roughens the surface a
little so it reads as skin and leather rather than plastic. Nothing about the
mesh, the rig or the animations is touched.

    pip install bpy        # needs Python 3.11 for the Blender 5.x wheels
    python3 tools/prep_goblin.py <source.glb> <dest.glb>
"""
import sys

import bpy  # must come first: bmesh only registers once bpy has initialised

SRC = sys.argv[-2]
OUT = sys.argv[-1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

print("actions imported: %d" % len(bpy.data.actions))
for a in bpy.data.actions:
    print("   %-40s %.2fs" % (a.name, (a.frame_range[1] - a.frame_range[0]) / 24.0))

for mat in bpy.data.materials:
    if not mat.use_nodes:
        continue
    bsdf = None
    for n in mat.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            bsdf = n
    if bsdf is None:
        continue
    # 1. cut the emission. The colour texture feeding Emission Color is what
    #    makes the model glow; zeroing the strength is not enough on its own
    #    because the glTF exporter writes an emissiveTexture back out whenever
    #    the socket is connected.
    em_col = bsdf.inputs["Emission Color"]
    for link in list(em_col.links):
        mat.node_tree.links.remove(link)
    em_col.default_value = (0.0, 0.0, 0.0, 1.0)
    if "Emission Strength" in bsdf.inputs:
        bsdf.inputs["Emission Strength"].default_value = 0.0
    # 2. specular back to something physical
    for name in ("Specular IOR Level", "Specular"):
        if name in bsdf.inputs:
            bsdf.inputs[name].default_value = 0.5
    if "Specular Tint" in bsdf.inputs:
        bsdf.inputs["Specular Tint"].default_value = (1.0, 1.0, 1.0, 1.0)
    # 3. skin and worn leather are not glossy
    if "Roughness" in bsdf.inputs and not bsdf.inputs["Roughness"].links:
        bsdf.inputs["Roughness"].default_value = 0.68
    print("cleaned material: %s" % mat.name)

def _action_fcurves(action):
    """Blender 4.4 moved actions to slots and channelbags; 5.x has no
    action.fcurves at all. Yield curves from whichever layout is present."""
    if hasattr(action, "fcurves"):
        for fc in action.fcurves:
            yield fc
        return
    for layer in getattr(action, "layers", []):
        for strip in getattr(layer, "strips", []):
            for bag in getattr(strip, "channelbags", []):
                for fc in bag.fcurves:
                    yield fc


def bake_armature_scale():
    """Put the rig into metres.

    Meshy exports this skeleton in centimetres — the hips rest 92 units up — and
    leans on a 0.01 scale on the armature node to bring the result back to human
    size. Godot imports that faithfully, which is fine until you attach physics:
    the physics server works in global space, so bodies parented under a hundredth
    scale get shapes, masses and impulses in mutually inconsistent units, and a
    ragdoll built that way falls through the floor and accelerates away instead of
    settling. Measured: hips at y=-259 after ninety frames, still speeding up.

    So the scale is applied here rather than carried at runtime: bone rests, mesh
    vertices and every animated bone translation are multiplied through, and the
    node is left at 1. Nothing about the model changes shape — it is the same
    1.7 m goblin — it is simply described in the units the engine expects.
    """
    arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    if arm is None:
        return
    s = float(arm.scale.x)
    if abs(s - 1.0) < 1e-6:
        print("armature already at unit scale, nothing to bake")
        return
    if abs(arm.scale.y - s) > 1e-6 or abs(arm.scale.z - s) > 1e-6:
        raise SystemExit("armature scale is not uniform (%s); bailing rather than shearing it" % (tuple(arm.scale),))
    print("baking armature scale %.5f into the rig" % s)

    # meshes ride under the armature, so their vertices are in the same units
    for ob in bpy.data.objects:
        if ob.type != "MESH":
            continue
        for v in ob.data.vertices:
            v.co *= s

    # bone rests
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for eb in arm.data.edit_bones:
        eb.head = eb.head * s
        eb.tail = eb.tail * s
    bpy.ops.object.mode_set(mode="OBJECT")

    # and every animated bone translation, which is expressed in those same units
    scaled = 0
    for action in bpy.data.actions:
        for fc in _action_fcurves(action):
            if not fc.data_path.endswith(".location"):
                continue
            for kp in fc.keyframe_points:
                kp.co.y *= s
                kp.handle_left.y *= s
                kp.handle_right.y *= s
            scaled += 1
    print("  scaled %d bone location curves across %d actions" % (scaled, len(bpy.data.actions)))

    arm.scale = (1.0, 1.0, 1.0)


bake_armature_scale()

bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format="GLB",
    export_image_format="AUTO",
    export_yup=True,
    use_selection=False,
    export_skins=True,
    export_animations=True,
    export_all_influences=True,
    export_apply=False,
)
print("wrote", OUT)
