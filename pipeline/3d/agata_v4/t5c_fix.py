"""T5c (24.10): правки GLB Агаты v4 после ИИ-проверки спрайтов (Docs/ai_checks/sprite_qa_2026-10-24_2.md), 0 кредитов.
  1) сумка — веса без разрывов (t5c_bag.py): «солома» из клапана была вытянутыми треугольниками;
  2) pick — присед мельче (t5c_pick.py): низ (таз, ноги) 0,6 от глубины Collect_Object, верх полностью + наклон спины
     15°; подошвы на полу; голова в нижней точке 1,06 м (было 0,88) — юбка не сминается в ком, колени не выходят;
  3) sit — фигура в середине кадра (t5c_sit.py): таз сдвинут так, что середина силуэта сидя = середина стойки.
Запуск (bpy 5.2.2 как модуль, Python 3.13):
  python3.13 pipeline/3d/agata_v4/t5c_fix.py <вход agata_v4_animations.glb> <выход.glb> <отчёт.json>
"""
import bpy, sys, json, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from t5c_bag import fix_bag
from t5c_pick import build
from t5c_sit import center_sit
PICK = {"w_low": 0.6, "w_up": 1.0, "spine_deg": 15.0}
src, dst, rep_p = sys.argv[1], sys.argv[2], sys.argv[3]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src, disable_bone_shape=True)
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
o = max([o for o in bpy.data.objects if o.type == "MESH"], key=lambda m: len(m.data.vertices))
rep = {"src": os.path.basename(src)}
rep["bag"] = fix_bag(o)
old = bpy.data.actions["Collect_Object_pick"]; old.name = "Collect_Object_pick_T5b"
build(arm, "Collect_Object_pick_T5b", "Collect_Object_pick", PICK["w_low"], PICK["w_up"], PICK["spine_deg"])
bpy.data.actions.remove(old)
rep["pick"] = PICK
rep["sit"] = center_sit(arm, o, "Chair_Sit_F_sit", "Idle_T2M_idle")
# высоты в нижней точке pick (м): голова, кисти, таз
act = bpy.data.actions["Collect_Object_pick"]; arm.animation_data.action = act
f0, f1 = map(int, act.frame_range); sc = bpy.context.scene
low = None
for f in range(f0, f1 + 1):
    sc.frame_set(f)
    P = lambda b: (arm.matrix_world @ arm.pose.bones[b].head).z
    if low is None or P("Hips") < low["hips"]:
        low = {"frame": f, "hips": round(P("Hips"), 3), "head": round(P("Head"), 3), "knee": round(max(P("LeftLeg"), P("RightLeg")), 3),
               "hand_min": round(min(P("LeftHand"), P("RightHand")), 3)}
rep["pick_low"] = low
for a in bpy.data.actions:
    a.use_fake_user = True
arm.animation_data.action = bpy.data.actions["Idle_T2M_idle"]
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_animations=True, export_animation_mode="ACTIONS")
json.dump(rep, open(rep_p, "w"), ensure_ascii=False, indent=1)
print(json.dumps(rep, ensure_ascii=False))
