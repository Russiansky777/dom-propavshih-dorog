import bpy, sys
argv=sys.argv[sys.argv.index('--')+1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=argv[0])
mat=bpy.data.materials[0]
bsdf=[n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'][0]
def src(inp):
    for l in mat.node_tree.links:
        if l.to_socket==inp: return l.from_node
for name in ['Base Color','Roughness','Normal','Metallic']:
    n=src(bsdf.inputs[name]); 
    while n is not None and n.type!='TEX_IMAGE':
        ins=[i for i in n.inputs if i.is_linked]; n=src(ins[0]) if ins else None
    if n is not None:
        img=n.image; print(name, img.name, img.size[:])
        img.filepath_raw=f"{argv[1]}_{name.replace(' ','')}.png"; img.file_format='PNG'; img.save()
