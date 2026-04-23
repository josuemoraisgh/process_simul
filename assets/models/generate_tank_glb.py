#!/usr/bin/env python3
"""
Blender Python script – 3D process tank system (GLB).

Layout designed for clear spatial separation (no overlap):
  Tank (centre), Pump (far left), Transmitter (far right),
  piping routes at distinct heights, flow bars in front.

Usage (Blender 5.x):
  "C:\\Program Files\\Blender Foundation\\Blender 5.1\\blender.exe" ^
      --background --python generate_tank_glb.py

Output: tank.glb in the same directory.
"""

import bpy, bmesh, os, math
from mathutils import Vector, Matrix

# ─── Clean scene ──────────────────────────────────────────────────
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# ─── Materials ────────────────────────────────────────────────────

def mat(name, col, metal=0.0, rough=0.5, alpha=1.0,
        emit=None, emit_str=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.use_backface_culling = True
    ns = m.node_tree.nodes; ls = m.node_tree.links; ns.clear()
    b = ns.new('ShaderNodeBsdfPrincipled')
    b.inputs['Base Color'].default_value = (*col, 1.0)
    b.inputs['Metallic'].default_value = metal
    b.inputs['Roughness'].default_value = rough
    if alpha < 1.0:
        b.inputs['Alpha'].default_value = alpha
        try: m.blend_method = 'BLEND'; m.shadow_method = 'CLIP'
        except AttributeError: pass
    if emit and emit_str > 0:
        for n in ['Emission Color', 'Emission']:
            if n in b.inputs:
                b.inputs[n].default_value = (*emit, 1.0); break
        if 'Emission Strength' in b.inputs:
            b.inputs['Emission Strength'].default_value = emit_str
    o = ns.new('ShaderNodeOutputMaterial')
    ls.new(b.outputs['BSDF'], o.inputs['Surface'])
    return m

M_TANK     = mat('Tank_Steel',     (0.72,0.72,0.72), metal=0.85, rough=0.35)
M_CAP      = mat('Tank_Cap',       (0.60,0.60,0.62), metal=0.85, rough=0.40)
M_LEG      = mat('Tank_Leg',       (0.40,0.40,0.42), metal=0.80, rough=0.50)
M_WELD     = mat('Weld',           (0.50,0.50,0.50), metal=0.70, rough=0.60)
M_MOTOR    = mat('Motor_Blue',     (0.05,0.10,0.45), metal=0.30, rough=0.55)
M_MOTOR_DK = mat('Motor_Dark',     (0.03,0.06,0.30), metal=0.35, rough=0.50)
M_SS       = mat('Stainless',      (0.75,0.77,0.80), metal=0.95, rough=0.20)
M_SS_DK    = mat('Stainless_Dk',   (0.55,0.57,0.60), metal=0.90, rough=0.30)
M_PIPE     = mat('Pipe_Blue',      (0.15,0.45,0.90), metal=0.20, rough=0.40)
M_XMTR     = mat('Xmtr_Body',     (0.60,0.62,0.60), metal=0.50, rough=0.45)
M_XMTR_HD  = mat('Xmtr_Head',     (0.75,0.75,0.73), metal=0.40, rough=0.40)
M_DISPLAY  = mat('Display',        (0.90,0.93,0.88), metal=0.0,  rough=0.30)
M_WATER    = mat('Water',          (0.10,0.45,0.85), metal=0.0,  rough=0.05, alpha=0.55)
M_GLASS    = mat('Glass',          (0.88,0.92,1.00), metal=0.0,  rough=0.02, alpha=0.20)
M_ARROW    = mat('Red_Arrow',      (0.90,0.10,0.10), metal=0.20, rough=0.40,
                 emit=(0.9,0.1,0.1), emit_str=1.0)
M_FLOW     = mat('FlowBar',        (0.30,0.15,0.65), metal=0.20, rough=0.35,
                 emit=(0.3,0.15,0.65), emit_str=0.8)
M_GROUND   = mat('Ground',         (0.35,0.34,0.32), metal=0.0,  rough=0.90)
M_VALVE    = mat('Valve',          (0.82,0.30,0.08), metal=0.40, rough=0.45)

# ─── Helpers ──────────────────────────────────────────────────────

def smooth(obj, ang=40):
    try:
        if hasattr(obj.data, 'use_auto_smooth'):
            obj.data.use_auto_smooth = True
            obj.data.auto_smooth_angle = math.radians(ang)
    except: pass

def bevel(obj, w=0.005, s=2):
    mod = obj.modifiers.new('Bevel','BEVEL')
    mod.width = w; mod.segments = s
    mod.limit_method = 'ANGLE'; mod.angle_limit = math.radians(60)

def par(child, parent):
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()

def empty(name, loc=(0,0,0)):
    bpy.ops.object.empty_add(type='PLAIN_AXES', location=loc)
    o = bpy.context.active_object; o.name = name; return o

def cyl(name, r, d, loc, rot=(0,0,0), sg=32, mt=None, bv=True):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=d,
        location=loc, rotation=rot, vertices=sg)
    o = bpy.context.active_object; o.name = name
    if mt: o.data.materials.append(mt)
    if bv and r > 0.025: bevel(o, w=min(0.006, r*0.05))
    smooth(o); return o

def box(name, sz, loc, sc=(1,1,1), rot=(0,0,0), mt=None, bv=True):
    bpy.ops.mesh.primitive_cube_add(size=sz, location=loc, rotation=rot)
    o = bpy.context.active_object; o.name = name; o.scale = sc
    bpy.ops.object.transform_apply(scale=True)
    if mt: o.data.materials.append(mt)
    if bv: bevel(o, w=min(0.006, sz*0.03))
    smooth(o); return o

def sph(name, r, loc, mt=None, sg=24):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc,
        segments=sg, ring_count=sg//2)
    o = bpy.context.active_object; o.name = name
    if mt: o.data.materials.append(mt)
    smooth(o); return o

def tor(name, R, r, loc, rot=(0,0,0), mt=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r,
        location=loc, rotation=rot, major_segments=48, minor_segments=16)
    o = bpy.context.active_object; o.name = name
    if mt: o.data.materials.append(mt)
    smooth(o); return o

def cone(name, r1, r2, d, loc, rot=(0,0,0), sg=32, mt=None):
    bpy.ops.mesh.primitive_cone_add(radius1=r1, radius2=r2, depth=d,
        location=loc, rotation=rot, vertices=sg)
    o = bpy.context.active_object; o.name = name
    if mt: o.data.materials.append(mt)
    smooth(o); return o

def pipe_run(name, r, length, loc, horizontal=False, mt=None, parent=None):
    """Shortcut for a pipe segment (vertical or horizontal along X)."""
    rot = (0, math.pi/2, 0) if horizontal else (0, 0, 0)
    p = cyl(name, r, length, loc, rot=rot, sg=20, mt=mt, bv=False)
    if parent: par(p, parent)
    return p

def pipe_elbow(name, r, loc, mt=None, parent=None):
    """Elbow joint as a sphere."""
    e = sph(name, r*1.2, loc, mt=mt, sg=16)
    if parent: par(e, parent)
    return e

def pipe_nozzle(name, loc, rot=(0,0,0), mt_body=None, mt_fl=None, parent=None):
    """Tank nozzle stub + flange."""
    nb = cyl(f'{name}_Nzl', PIPE_R*1.4, 0.05, loc, rot=rot, sg=20, mt=mt_body, bv=False)
    if parent: par(nb, parent)
    # Flange slightly offset along nozzle axis
    dx = 0.028 * math.cos(rot[1]) if abs(rot[1]) > 0.01 else 0
    dz = 0.028 * math.cos(rot[0]) if abs(rot[0]) < 0.01 and abs(rot[1]) < 0.01 else 0
    fl = cyl(f'{name}_Fl', PIPE_R*1.9, 0.012, 
             (loc[0]+dx, loc[1], loc[2]-dz), rot=rot, sg=20, mt=mt_fl, bv=False)
    if parent: par(fl, parent)
    return nb, fl

# ═══════════════════════════════════════════════════════════════════
#  LAYOUT — wide spacing to avoid visual overlap
# ═══════════════════════════════════════════════════════════════════
TANK_R   = 0.45
TANK_H   = 1.6
TANK_CAP = 0.12
LEG_H    = 0.50
PIPE_R   = 0.035

# Tank centre
TX, TY = 0.0, 0.0
TZ = LEG_H + TANK_H / 2                    # 1.30  (bottom 0.50, top 2.10)

# Pump — far left, near ground
PX, PY, PZ = -2.5, 0.0, 0.25

# Transmitter — far right, mid-height on a stand
SX, SY, SZ = 2.0, 0.0, 0.50

# Pump housing centre-X
HX = PX + 0.40                              # -2.10

# ═══════════════════════════════════════════════════════════════════
#  BUILD
# ═══════════════════════════════════════════════════════════════════
root = empty('Tank_System')

# ── TANK ──────────────────────────────────────────────────────────
tk = empty('Tank', (TX, TY, 0)); par(tk, root)

# Body
par(cyl('Tank_Body', TANK_R, TANK_H, (TX,TY,TZ), sg=64, mt=M_TANK), tk)

# Caps (flattened spheres)
for lbl, sgn in [('Top',1),('Bot',-1)]:
    c = sph(f'Tank_{lbl}Cap', TANK_R, (TX,TY, TZ + sgn*TANK_H/2), mt=M_CAP, sg=48)
    c.scale = (1, 1, TANK_CAP/TANK_R)
    bpy.context.view_layer.objects.active = c
    bpy.ops.object.transform_apply(scale=True)
    par(c, tk)

# Top ring
par(tor('Tank_TopRing', TANK_R, 0.016, (TX,TY, TZ+TANK_H/2), mt=M_SS_DK), tk)

# 4 Legs
for i in range(4):
    a = (2*math.pi/4)*i + math.pi/4
    lx = TX + TANK_R*0.7*math.cos(a)
    ly = TY + TANK_R*0.7*math.sin(a)
    par(box(f'Leg_{i}', 0.06, (lx,ly, LEG_H/2),
            sc=(1,0.5, LEG_H/0.06), mt=M_LEG), tk)
    par(box(f'Foot_{i}', 0.09, (lx,ly, 0.012),
            sc=(1.3,1.0, 0.025/0.09), mt=M_LEG), tk)

# Weld lines
for i in range(3):
    wz = TZ - TANK_H/2 + (i+1)*(TANK_H/4)
    par(tor(f'Weld_{i}', TANK_R+0.002, 0.003, (TX,TY,wz), mt=M_WELD), tk)

# Level gauge (+X face) — thick for visibility
gx = TX + TANK_R + 0.045
gh = TANK_H * 0.55
par(box('Gauge_Frame', 0.022, (gx,TY,TZ),
        sc=(0.6,0.6, gh/0.022), mt=M_SS_DK), tk)
par(cyl('Gauge_Glass', 0.030, gh, (gx,TY,TZ), sg=20, mt=M_GLASS, bv=False), tk)
par(cyl('WaterLevel', 0.026, gh*0.5,
        (gx,TY, TZ - gh*0.25), sg=20, mt=M_WATER, bv=False), tk)
for lbl, gz in [('Top', TZ+gh/2), ('Bot', TZ-gh/2)]:
    par(cyl(f'Gauge_{lbl}', 0.038, 0.028, (gx,TY,gz),
            sg=20, mt=M_SS, bv=False), tk)

# Manhole
mhz = TZ + TANK_H/2 + TANK_CAP*0.5
par(tor('Manhole_Ring', 0.12, 0.015, (TX,TY,mhz), mt=M_SS), tk)
par(cyl('Manhole_Lid', 0.11, 0.015, (TX,TY, mhz+0.010), sg=32, mt=M_SS_DK), tk)


# ── PUMP ──────────────────────────────────────────────────────────
pm = empty('Pump', (PX,PY,PZ)); par(pm, root)

# Motor
par(cyl('Motor', 0.14, 0.40, (PX,PY,PZ),
        rot=(0,math.pi/2,0), sg=48, mt=M_MOTOR), pm)
# Cooling fins
for i in range(7):
    fx = PX - 0.16 + i*0.043
    par(tor(f'Fin_{i}', 0.14, 0.006, (fx,PY,PZ),
            rot=(0,math.pi/2,0), mt=M_MOTOR_DK), pm)
# End caps
for lbl, dx in [('Fr',0.21),('Rr',-0.21)]:
    par(cyl(f'Motor_{lbl}', 0.14, 0.012, (PX+dx,PY,PZ),
            rot=(0,math.pi/2,0), sg=48, mt=M_MOTOR_DK), pm)
# Fan cover
par(cyl('FanCover', 0.12, 0.06, (PX-0.24,PY,PZ),
        rot=(0,math.pi/2,0), sg=32, mt=M_MOTOR_DK), pm)
# Motor feet
for lbl, fy in [('L',-0.10),('R',0.10)]:
    par(box(f'MFoot_{lbl}', 0.03, (PX,fy, PZ-0.14),
            sc=(7,1.2,0.4), mt=M_MOTOR_DK), pm)
# Shaft coupling
par(cyl('Shaft', 0.032, 0.08, (PX+0.25,PY,PZ),
        rot=(0,math.pi/2,0), sg=24, mt=M_SS), pm)
# Housing (volute)
par(cyl('Housing', 0.11, 0.11, (HX,PY,PZ),
        rot=(0,math.pi/2,0), sg=48, mt=M_SS), pm)
par(cyl('HousCover', 0.12, 0.012, (HX+0.06,PY,PZ),
        rot=(0,math.pi/2,0), sg=48, mt=M_SS_DK), pm)
# Suction inlet (+X)
par(cyl('P_Inlet', 0.038, 0.06, (HX+0.09,PY,PZ),
        rot=(0,math.pi/2,0), sg=24, mt=M_SS), pm)
par(cyl('P_Inlet_Fl', 0.055, 0.010, (HX+0.12,PY,PZ),
        rot=(0,math.pi/2,0), sg=24, mt=M_SS_DK), pm)
# Discharge (+Z)
par(cyl('P_Disch', 0.035, 0.08, (HX,PY, PZ+0.13),
        sg=24, mt=M_SS), pm)
par(cyl('P_Disch_Fl', 0.050, 0.010, (HX,PY, PZ+0.17),
        sg=24, mt=M_SS_DK), pm)
# Base plate
par(box('Pump_Base', 0.035, (PX+0.06,PY, PZ-0.17),
        sc=(15,3.5,0.35), mt=M_LEG), pm)


# ── TRANSMITTER ───────────────────────────────────────────────────
xm = empty('Transmitter', (SX,SY,SZ)); par(xm, root)

par(cyl('Xmtr_Body', 0.08, 0.17, (SX,SY,SZ), sg=32, mt=M_XMTR), xm)
par(box('Xmtr_Head', 0.09, (SX,SY, SZ+0.15),
        sc=(1,0.8,0.7), mt=M_XMTR_HD), xm)
par(box('Xmtr_Disp', 0.045, (SX+0.050,SY, SZ+0.16),
        sc=(0.10,0.70,0.40), mt=M_DISPLAY, bv=False), xm)
par(cyl('Xmtr_Cond', 0.016, 0.06, (SX,SY, SZ+0.25), sg=16, mt=M_XMTR), xm)
# HP/LP nozzles
for lbl, dy in [('HP',-0.05),('LP',0.05)]:
    par(cyl(f'Xmtr_{lbl}', 0.020, 0.045, (SX, SY+dy, SZ-0.10),
            rot=(math.pi/2,0,0), sg=16, mt=M_SS), xm)
    par(cyl(f'Xmtr_{lbl}_Fl', 0.028, 0.008, (SX, SY+dy, SZ-0.13),
            rot=(math.pi/2,0,0), sg=16, mt=M_SS_DK), xm)
# Bracket
par(box('Xmtr_Brk', 0.030, (SX-0.06,SY,SZ),
        sc=(0.4,1.6,2.5), mt=M_LEG), xm)
# Stand from ground
stand_h = SZ - 0.08
par(cyl('Xmtr_Stand', 0.025, stand_h, (SX-0.06,SY, stand_h/2),
        sg=16, mt=M_LEG, bv=False), xm)
par(box('Xmtr_Base', 0.09, (SX-0.06,SY, 0.012),
        sc=(1.2,1.2, 0.025/0.09), mt=M_LEG), xm)


# ── PIPING ────────────────────────────────────────────────────────
pp = empty('Piping'); par(pp, root)

# --- Route heights ---
ROUTE_P2T = 1.0        # pump-to-tank horizontal run height
ROUTE_T2X = SZ          # tank-to-transmitter at transmitter height

# --- 1. Pump → Tank ---
p_top_z = PZ + 0.18     # top of pump discharge flange
tk_in_x = TX - TANK_R   # left wall of tank
tk_in_z = ROUTE_P2T     # where pipe enters tank

# Vertical from pump discharge up to routing height
v1 = ROUTE_P2T - p_top_z
pipe_run('P2T_V', PIPE_R, v1, (HX, PY, p_top_z + v1/2), mt=M_PIPE, parent=pp)

# Horizontal from above pump to tank left wall
h1 = abs(tk_in_x - HX)
pipe_run('P2T_H', PIPE_R, h1, (HX + (tk_in_x - HX)/2, PY, ROUTE_P2T),
         horizontal=True, mt=M_PIPE, parent=pp)

# Elbow at corner
pipe_elbow('Elb_P2T', PIPE_R, (HX, PY, ROUTE_P2T), mt=M_PIPE, parent=pp)

# Tank inlet nozzle + flange (left wall)
par(cyl('TkIn_Nzl', PIPE_R*1.4, 0.05, (tk_in_x, TY, tk_in_z),
        rot=(0,math.pi/2,0), sg=20, mt=M_SS, bv=False), pp)
par(cyl('TkIn_Fl', PIPE_R*1.9, 0.012, (tk_in_x - 0.028, TY, tk_in_z),
        rot=(0,math.pi/2,0), sg=20, mt=M_SS_DK, bv=False), pp)

# Valve on pump-to-tank piping (at midpoint)
valve_x = (HX + tk_in_x) / 2
par(box('Valve_P2T', 0.06, (valve_x, PY, ROUTE_P2T),
        sc=(0.8, 0.8, 1.0), mt=M_VALVE), pp)
par(cyl('Valve_P2T_Hw', 0.012, 0.10, (valve_x, PY, ROUTE_P2T + 0.08),
        sg=12, mt=M_VALVE, bv=False), pp)
par(sph('Valve_P2T_Knob', 0.018, (valve_x, PY, ROUTE_P2T + 0.13),
        mt=M_ARROW, sg=12), pp)


# --- 2. Tank → Transmitter ---
# Route: tank right wall → horizontal at z=0.85 ABOVE everything
# (stand top ≈ 0.42, bracket ≈ 0.54, body ≈ 0.58, head ≈ 0.68)
# → drop on far side of transmitter → short horizontal back to nozzle.
tk_out_x = TX + TANK_R    # right wall of tank
tk_out_z = 0.85            # connection point on tank right side
drop_x   = SX + 0.12      # drop point past transmitter body (r=0.08)
nozzle_z = SZ - 0.13      # transmitter HP/LP nozzle Z (0.37)

# Long horizontal at z=0.85 from tank wall to past transmitter
h2 = drop_x - tk_out_x
pipe_run('T2X_H', PIPE_R, h2,
         (tk_out_x + h2/2, SY, tk_out_z),
         horizontal=True, mt=M_PIPE, parent=pp)

# Vertical drop from z=0.85 to nozzle height at x=drop_x
v2 = tk_out_z - nozzle_z
pipe_run('T2X_V', PIPE_R, v2,
         (drop_x, SY, nozzle_z + v2/2), mt=M_PIPE, parent=pp)

# Short horizontal from drop_x back to transmitter centre
h3 = drop_x - SX
pipe_run('T2X_H2', PIPE_R, h3,
         (SX + h3/2, SY, nozzle_z),
         horizontal=True, mt=M_PIPE, parent=pp)

# Elbows
pipe_elbow('Elb_T2X_1', PIPE_R, (drop_x, SY, tk_out_z), mt=M_PIPE, parent=pp)
pipe_elbow('Elb_T2X_2', PIPE_R, (drop_x, SY, nozzle_z), mt=M_PIPE, parent=pp)

# Tank outlet nozzle + flange (right wall)
par(cyl('TkOut_Nzl', PIPE_R*1.4, 0.05, (tk_out_x, TY, tk_out_z),
        rot=(0,math.pi/2,0), sg=20, mt=M_SS, bv=False), pp)
par(cyl('TkOut_Fl', PIPE_R*1.9, 0.012, (tk_out_x + 0.028, TY, tk_out_z),
        rot=(0,math.pi/2,0), sg=20, mt=M_SS_DK, bv=False), pp)


# --- 3. Bottom outlet (drain / process out) ---
tk_bot_z = LEG_H          # bottom of tank
drain_z  = 0.15           # horizontal drain run height
drain_end_x = 2.8         # end of drain pipe

# Vertical from tank bottom down
v3 = tk_bot_z - drain_z
pipe_run('Out_V', PIPE_R, v3,
         (TX, TY, drain_z + v3/2), mt=M_PIPE, parent=pp)

# Tank bottom nozzle
par(cyl('TkBot_Nzl', PIPE_R*1.4, 0.04,
        (TX, TY, tk_bot_z - 0.02), sg=20, mt=M_SS, bv=False), pp)

# Horizontal drain going right
h3 = drain_end_x - TX
pipe_run('Out_H', PIPE_R, h3,
         (TX + h3/2, TY, drain_z),
         horizontal=True, mt=M_PIPE, parent=pp)

# Elbow at corner
pipe_elbow('Elb_Out', PIPE_R, (TX, TY, drain_z), mt=M_PIPE, parent=pp)

# Red arrow at drain end
ax = drain_end_x
par(cyl('Arrow_Shaft', 0.008, 0.18, (ax+0.09, TY, drain_z),
        rot=(0,math.pi/2,0), sg=8, mt=M_ARROW, bv=False), pp)
par(cone('Arrow_Head', 0.035, 0.0, 0.09, (ax+0.23, TY, drain_z),
         rot=(0,math.pi/2,0), sg=12, mt=M_ARROW), pp)


# ── FLOW INDICATOR BARS ──────────────────────────────────────────
fl = empty('FlowIndicators'); par(fl, root)

# Inlet bar (front-left, Y offset so it's visible)
ib_h = 1.2
par(cyl('FlowIn', 0.020, ib_h,
        (PX - 0.35, -0.55, 0.5 + ib_h/2),
        sg=12, mt=M_FLOW, bv=False), fl)
par(sph('FlowIn_Top', 0.030,
        (PX - 0.35, -0.55, 0.5 + ib_h), mt=M_FLOW, sg=12), fl)

# Outlet bar (front-right)
ob_h = 0.8
par(cyl('FlowOut', 0.020, ob_h,
        (SX + 0.40, -0.55, 0.5 + ob_h/2),
        sg=12, mt=M_FLOW, bv=False), fl)
par(sph('FlowOut_Top', 0.030,
        (SX + 0.40, -0.55, 0.5 + ob_h), mt=M_FLOW, sg=12), fl)


# ── GROUND PLANE ──────────────────────────────────────────────────
par(box('Ground', 1.0, (0.2, 0, -0.015),
        sc=(8, 5, 0.015), mt=M_GROUND, bv=False), root)


# ═══════════════════════════════════════════════════════════════════
#  FINALIZE & EXPORT
# ═══════════════════════════════════════════════════════════════════

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

for obj in bpy.data.objects:
    if obj.type == 'MESH':
        bpy.context.view_layer.objects.active = obj
        for mod in obj.modifiers:
            try: bpy.ops.object.modifier_apply(modifier=mod.name)
            except: pass

for obj in bpy.data.objects:
    if obj.type == 'MESH':
        for p in obj.data.polygons: p.use_smooth = True
        smooth(obj, 40)

output_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'tank.glb')
args = dict(filepath=output_path, export_format='GLB', use_selection=False,
            export_apply=True, export_cameras=False, export_lights=False,
            export_materials='EXPORT', export_normals=True)
try:
    bpy.ops.export_scene.gltf(**args, export_animations=True,
        export_tangentials=False, export_draco_mesh_compression_enable=False)
except TypeError:
    bpy.ops.export_scene.gltf(**args)

print(f'\n✅ tank.glb exported to: {output_path}')
print(f'   Objects: {len(bpy.data.objects)}')
print(f'   Materials: {len(bpy.data.materials)}')
