"""UV-маска лица и волос по геометрии исходной модели (вершины головы и косы), растеризация треугольников."""
import bpy, sys, numpy as np
from PIL import Image, ImageDraw, ImageFilter
argv=sys.argv[sys.argv.index('--')+1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=argv[0])
o=[o for o in bpy.data.objects if o.type=='MESH'][0]; me=o.data
n=len(me.vertices); co=np.zeros(n*3); me.vertices.foreach_get('co',co); co=co.reshape(-1,3)
co=(np.array(o.matrix_world)[:3,:3]@co.T).T
base=np.asarray(Image.open(argv[1]).convert('RGB').filter(ImageFilter.GaussianBlur(6))).astype(np.float32)/255  # исходный basecolor (PNG сверху вниз)
me.calc_loop_triangles()
T=len(me.loop_triangles); tv=np.zeros(T*3,dtype=int); me.loop_triangles.foreach_get('vertices',tv); tv=tv.reshape(-1,3)
tl=np.zeros(T*3,dtype=int); me.loop_triangles.foreach_get('loops',tl); tl=tl.reshape(-1,3)
uv=np.zeros(len(me.loops)*2); me.uv_layers.active.data.foreach_get('uv',uv); uv=uv.reshape(-1,2)
S=base.shape[0]
c=co[tv].mean(1)
tuv=uv[tl]; px=np.stack([tuv[...,0]*S,(1-tuv[...,1])*S],-1)
cen=px.mean(1).astype(int).clip(0,S-1); col=base[cen[:,1],cen[:,0]]
lum=col.mean(1); sat=col.max(1)-col.min(1)
x,y,z=c[:,0],c[:,1],c[:,2]
neck_z=float(argv[3]) if len(argv)>3 else 1.43
skin_c=(col[:,0]>0.62)&(col[:,0]-col[:,2]>0.10)&(lum>0.5)
hair_c=(lum<0.26)
head=(z>neck_z+0.04)&(skin_c|hair_c)
skin=skin_c&(z>neck_z-0.08)&(np.abs(x)<0.1)
braid=(y>0.0)&(z>1.05)&(np.abs(x)<0.10)&hair_c
m=head|skin|braid
print('tris head',head.sum(),'skin',skin.sum(),'braid',braid.sum(),'total',m.sum())
mask=Image.new('L',(S,S),0); dr=ImageDraw.Draw(mask)
for p in px[m]:
    dr.polygon([tuple(q) for q in p],fill=255)
mask=mask.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(3))
mask.save(argv[2])
