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
