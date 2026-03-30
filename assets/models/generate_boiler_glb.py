#!/usr/bin/env python3
"""
Blender Python script to generate an aquatubular boiler GLB model.

Usage:
  blender --background --python generate_boiler_glb.py

Or run from Blender's scripting tab.

Output: boiler.glb in the same directory as this script.

Hierarchy (all objects named for SCADA / digital twin binding):
  Boiler_System
  ├── StructuralFrame
  ├── SteamDrum
  │   ├── WaterLevel
  │   ├── LevelGauge
  │   ├── LevelSensor_High
  │   └── LevelSensor_Low
  ├── MudDrum
  ├── WaterWallTubes
  ├── Furnace
  │   ├── Burner
  │   └── Flame
  ├── FuelSystem
  │   ├── FuelValve
  │   └── FuelPipe
  ├── AirSystem
  │   ├── PrimaryAirFan
  │   ├── SecondaryAirFan
  │   └── AirDamper
  ├── DraftSystem
  │   ├── InducedDraftFan
  │   ├── ForcedDraftFan
  │   └── FlueGasDamper
  ├── GasDucts
  ├── Economizer
  └── FlowIndicators
"""

import bpy
import bmesh
import os
import math
from mathutils import Vector, Matrix

# ─── Clean scene ──────────────────────────────────────────────────────────────
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# ─── Materials ────────────────────────────────────────────────────────────────

def create_pbr_material(name, base_color, metallic=0.9, roughness=0.35, alpha=1.0,
                        emission_color=None, emission_strength=0.0):
    """Create a PBR material (Principled BSDF) compatible with glTF 2.0 export."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.use_backface_culling = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    bsdf.inputs['Base Color'].default_value = (*base_color, 1.0)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    if alpha < 1.0:
        bsdf.inputs['Alpha'].default_value = alpha
        # Blender 4.x removed blend_method; use try/except for compatibility
        try:
            mat.blend_method = 'BLEND'
            mat.shadow_method = 'CLIP'
        except AttributeError:
            pass  # Blender 4.x+: alpha mode is inferred by glTF exporter
    if emission_color and emission_strength > 0:
        # Emission input name varies by Blender version
        for em_name in ['Emission Color', 'Emission']:
            if em_name in bsdf.inputs:
                bsdf.inputs[em_name].default_value = (*emission_color, 1.0)
                break
        if 'Emission Strength' in bsdf.inputs:
            bsdf.inputs['Emission Strength'].default_value = emission_strength
    output = nodes.new('ShaderNodeOutputMaterial')
    mat.node_tree.links.new(bsdf.outputs['BSDF'], output.inputs['Surface'])
    return mat

# Steel materials
mat_steel = create_pbr_material('Steel_Brushed', (0.7, 0.72, 0.74), metallic=0.95, roughness=0.3)
mat_steel_dark = create_pbr_material('Steel_Dark', (0.3, 0.32, 0.34), metallic=0.9, roughness=0.4)
mat_steel_worn = create_pbr_material('Steel_Worn', (0.55, 0.52, 0.48), metallic=0.8, roughness=0.5)
mat_refractory = create_pbr_material('Refractory_Brick', (0.25, 0.12, 0.08), metallic=0.0, roughness=0.9)
mat_water = create_pbr_material('Water', (0.15, 0.55, 0.85), metallic=0.0, roughness=0.1, alpha=0.6)
mat_flame_orange = create_pbr_material('Flame_Orange', (1.0, 0.5, 0.0), metallic=0.0, roughness=0.9,
                                       emission_color=(1.0, 0.4, 0.0), emission_strength=5.0)
mat_glass = create_pbr_material('Glass', (0.8, 0.9, 1.0), metallic=0.0, roughness=0.05, alpha=0.3)
mat_copper = create_pbr_material('Copper_Pipe', (0.72, 0.45, 0.2), metallic=0.95, roughness=0.35)
mat_red_sensor = create_pbr_material('Sensor_Red', (0.8, 0.1, 0.1), metallic=0.5, roughness=0.4)
mat_green_sensor = create_pbr_material('Sensor_Green', (0.1, 0.8, 0.2), metallic=0.5, roughness=0.4)
mat_flow_blue = create_pbr_material('Flow_Blue', (0.2, 0.6, 1.0), metallic=0.0, roughness=0.5, alpha=0.7)
mat_flow_red = create_pbr_material('Flow_Red', (1.0, 0.2, 0.1), metallic=0.0, roughness=0.5, alpha=0.7)
mat_flow_orange = create_pbr_material('Flow_Orange', (1.0, 0.6, 0.1), metallic=0.0, roughness=0.5, alpha=0.7)
mat_fan_blade = create_pbr_material('Fan_Blade', (0.5, 0.52, 0.55), metallic=0.9, roughness=0.25)

# ─── Helper functions ─────────────────────────────────────────────────────────

def set_parent(child_obj, parent_obj):
    child_obj.parent = parent_obj
    child_obj.matrix_parent_inverse = parent_obj.matrix_world.inverted()

def add_cylinder(name, radius, depth, location, rotation=(0,0,0), segments=32, material=None):
    bpy.ops.mesh.primitive_cylinder_add(
        radius=radius, depth=depth,
        location=location, rotation=rotation,
        vertices=segments
    )
    obj = bpy.context.active_object
    obj.name = name
    if material:
        obj.data.materials.append(material)
    return obj

def add_cube(name, size, location, scale=(1,1,1), rotation=(0,0,0), material=None):
    bpy.ops.mesh.primitive_cube_add(size=size, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    if material:
        obj.data.materials.append(material)
    return obj

def add_sphere(name, radius, location, material=None, segments=16):
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=radius, location=location,
        segments=segments, ring_count=segments//2
    )
    obj = bpy.context.active_object
    obj.name = name
    if material:
        obj.data.materials.append(material)
    return obj

def add_torus(name, major_r, minor_r, location, rotation=(0,0,0), material=None):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_r, minor_radius=minor_r,
        location=location, rotation=rotation,
        major_segments=32, minor_segments=12
    )
    obj = bpy.context.active_object
    obj.name = name
    if material:
        obj.data.materials.append(material)
    return obj

def add_empty(name, location=(0,0,0)):
    bpy.ops.object.empty_add(type='PLAIN_AXES', location=location)
    obj = bpy.context.active_object
    obj.name = name
    return obj

def create_fan_blades(name, radius, n_blades, location, rotation=(0,0,0), material=None):
    """Create a fan with n_blades."""
    fan_empty = add_empty(name, location)
    fan_empty.rotation_euler = rotation
    
    for i in range(n_blades):
        angle = (2 * math.pi / n_blades) * i
        bx = location[0] + radius * 0.4 * math.cos(angle)
        by = location[1] + radius * 0.4 * math.sin(angle)
        bz = location[2]
        blade = add_cube(
            f'{name}_Blade_{i}', 0.1,
            (bx, by, bz),
            scale=(radius * 0.8, 0.15, 0.02),
            rotation=(0, 0, angle),
            material=material
        )
        set_parent(blade, fan_empty)
    
    # Hub
    hub = add_cylinder(f'{name}_Hub', radius * 0.15, 0.08, location, material=mat_steel_dark)
    set_parent(hub, fan_empty)
    
    return fan_empty

def create_pipe(name, start, end, radius=0.04, material=None):
    """Create a pipe between two points."""
    dx = end[0] - start[0]
    dy = end[1] - start[1]
    dz = end[2] - start[2]
    length = math.sqrt(dx*dx + dy*dy + dz*dz)
    cx = (start[0] + end[0]) / 2
    cy = (start[1] + end[1]) / 2
    cz = (start[2] + end[2]) / 2
    
    # Rotation to align Z-axis with the pipe direction
    phi = math.atan2(dy, dx)
    theta = math.acos(dz / length) if length > 0 else 0
    
    pipe = add_cylinder(name, radius, length, (cx, cy, cz),
                        rotation=(theta, 0, phi), material=material)
    return pipe


# ═══════════════════════════════════════════════════════════════════════════════
#  BUILD THE BOILER
# ═══════════════════════════════════════════════════════════════════════════════

# Root empty
boiler_root = add_empty('Boiler_System', (0, 0, 0))

# ── StructuralFrame ───────────────────────────────────────────────────────────
frame = add_cube('StructuralFrame', 1.0, (0, 0, 1.5),
                 scale=(3.0, 1.8, 3.0), material=mat_steel_dark)
# Make it wireframe-ish by scaling. Actually, let's create a cage.
# Remove the cube and create beams instead.
bpy.data.objects.remove(frame, do_unlink=True)

frame_empty = add_empty('StructuralFrame', (0, 0, 0))
set_parent(frame_empty, boiler_root)

# Vertical beams (4 corners)
beam_positions = [(-1.4, -0.8), (-1.4, 0.8), (1.4, -0.8), (1.4, 0.8)]
for i, (bx, by) in enumerate(beam_positions):
    beam = add_cube(f'Frame_VBeam_{i}', 0.1, (bx, by, 1.5),
                    scale=(1, 1, 30), material=mat_steel_dark)
    set_parent(beam, frame_empty)

# Horizontal beams top
for i, (bx, by) in enumerate(beam_positions):
    for j, (bx2, by2) in enumerate(beam_positions):
        if j > i:
            if abs(bx - bx2) < 0.01 or abs(by - by2) < 0.01:
                cx = (bx + bx2) / 2
                cy = (by + by2) / 2
                length = math.sqrt((bx2-bx)**2 + (by2-by)**2)
                hbeam = add_cube(f'Frame_HBeam_Top_{i}_{j}', 0.08,
                                 (cx, cy, 3.0),
                                 scale=(max(length/0.08, 1), 1, 1),
                                 rotation=(0, 0, math.atan2(by2-by, bx2-bx)),
                                 material=mat_steel_dark)
                set_parent(hbeam, frame_empty)

# ── Furnace ───────────────────────────────────────────────────────────────────
furnace_empty = add_empty('Furnace', (-0.4, 0, 0.8))
set_parent(furnace_empty, boiler_root)

furnace_body = add_cube('Furnace_Body', 1.0, (-0.4, 0, 0.8),
                        scale=(1.4, 1.2, 1.4), material=mat_refractory)
set_parent(furnace_body, furnace_empty)

# Burner
burner = add_cylinder('Burner', 0.12, 0.3, (-1.1, 0, 0.5),
                       rotation=(0, math.pi/2, 0), material=mat_steel)
set_parent(burner, furnace_empty)

# Flame (mesh animável)
flame = add_sphere('Flame', 0.25, (-0.7, 0, 0.5), material=mat_flame_orange)
flame.scale = (2.0, 0.8, 0.8)
bpy.context.view_layer.objects.active = flame
bpy.ops.object.transform_apply(scale=True)
set_parent(flame, furnace_empty)

# ── FuelSystem ────────────────────────────────────────────────────────────────
fuel_empty = add_empty('FuelSystem', (-1.5, 0, 0.5))
set_parent(fuel_empty, boiler_root)

fuel_pipe = add_cylinder('FuelPipe', 0.04, 0.8, (-1.5, 0, 0.5),
                          rotation=(0, math.pi/2, 0), material=mat_copper)
set_parent(fuel_pipe, fuel_empty)

fuel_valve = add_cylinder('FuelValve', 0.08, 0.12, (-1.7, 0, 0.5),
                           material=mat_steel)
set_parent(fuel_valve, fuel_empty)

# ── SteamDrum (Tubulão Superior) ──────────────────────────────────────────────
steam_drum_empty = add_empty('SteamDrum', (0.2, 0, 2.5))
set_parent(steam_drum_empty, boiler_root)

steam_drum_body = add_cylinder('SteamDrum_Body', 0.3, 1.8, (0.2, 0, 2.5),
                                rotation=(0, math.pi/2, 0),
                                segments=48, material=mat_steel)
set_parent(steam_drum_body, steam_drum_empty)

# Caps (hemispheres)
for side, sx in [('Left', -0.7), ('Right', 1.1)]:
    cap = add_sphere(f'SteamDrum_Cap_{side}', 0.3, (sx, 0, 2.5),
                     material=mat_steel, segments=24)
    cap.scale = (0.5, 1, 1)
    bpy.context.view_layer.objects.active = cap
    bpy.ops.object.transform_apply(scale=True)
    set_parent(cap, steam_drum_empty)

# WaterLevel (fluido interno animável - escalável em Y)
water_level = add_cylinder('WaterLevel', 0.25, 1.6, (0.2, 0, 2.35),
                            rotation=(0, math.pi/2, 0),
                            segments=32, material=mat_water)
set_parent(water_level, steam_drum_empty)

# LevelGauge (visor externo - tubo transparente lateral)
level_gauge = add_cylinder('LevelGauge', 0.03, 0.6, (0.6, 0.35, 2.5),
                            material=mat_glass)
set_parent(level_gauge, steam_drum_empty)

# Level gauge frame
for gz in [2.8, 2.2]:
    gframe = add_cylinder(f'LevelGauge_Frame_{int(gz*10)}', 0.04, 0.05,
                           (0.6, 0.35, gz), material=mat_steel)
    set_parent(gframe, steam_drum_empty)

# Level Sensors
sensor_high = add_sphere('LevelSensor_High', 0.04, (0.6, -0.33, 2.7),
                          material=mat_red_sensor)
set_parent(sensor_high, steam_drum_empty)

sensor_low = add_sphere('LevelSensor_Low', 0.04, (0.6, -0.33, 2.3),
                         material=mat_green_sensor)
set_parent(sensor_low, steam_drum_empty)

# ── MudDrum (Tubulão Inferior) ────────────────────────────────────────────────
mud_drum = add_cylinder('MudDrum', 0.2, 1.4, (0.2, 0, 0.2),
                         rotation=(0, math.pi/2, 0),
                         segments=48, material=mat_steel_worn)
set_parent(mud_drum, boiler_root)

# Mud drum caps
for side, sx in [('Left', -0.5), ('Right', 0.9)]:
    cap = add_sphere(f'MudDrum_Cap_{side}', 0.2, (sx, 0, 0.2),
                     material=mat_steel_worn, segments=24)
    cap.scale = (0.5, 1, 1)
    bpy.context.view_layer.objects.active = cap
    bpy.ops.object.transform_apply(scale=True)
    set_parent(cap, mud_drum)

# ── WaterWallTubes (paredes de tubos verticais) ──────────────────────────────
ww_empty = add_empty('WaterWallTubes', (0, 0, 1.35))
set_parent(ww_empty, boiler_root)

# Front and back rows of tubes connecting drums
n_tubes = 12
for i in range(n_tubes):
    x = -0.5 + i * (1.4 / (n_tubes - 1))
    # Front tubes
    tube_f = add_cylinder(f'WWT_Front_{i}', 0.025, 2.0,
                           (x, -0.55, 1.35), material=mat_steel)
    set_parent(tube_f, ww_empty)
    # Back tubes
    tube_b = add_cylinder(f'WWT_Back_{i}', 0.025, 2.0,
                           (x, 0.55, 1.35), material=mat_steel)
    set_parent(tube_b, ww_empty)

# Side tubes
n_side = 6
for i in range(n_side):
    y = -0.4 + i * (0.8 / (n_side - 1))
    tube_l = add_cylinder(f'WWT_Left_{i}', 0.025, 2.0,
                           (-0.6, y, 1.35), material=mat_steel)
    set_parent(tube_l, ww_empty)

# ── AirSystem ─────────────────────────────────────────────────────────────────
air_empty = add_empty('AirSystem', (-1.5, 0, 1.2))
set_parent(air_empty, boiler_root)

# Primary Air Fan (FD Fan)
primary_fan = create_fan_blades('PrimaryAirFan', 0.25, 6,
                                 (-1.6, -0.4, 0.5), material=mat_fan_blade)
set_parent(primary_fan, air_empty)

# Secondary Air Fan
secondary_fan = create_fan_blades('SecondaryAirFan', 0.2, 6,
                                   (-1.6, 0.4, 0.5), material=mat_fan_blade)
set_parent(secondary_fan, air_empty)

# Air Damper
air_damper = add_cube('AirDamper', 0.1, (-1.3, 0, 0.8),
                       scale=(0.3, 1.5, 0.05), material=mat_steel)
set_parent(air_damper, air_empty)

# Air duct
air_duct = add_cube('AirDuct', 0.5, (-1.2, 0, 0.6),
                     scale=(0.6, 1.5, 0.8), material=mat_steel_dark)
set_parent(air_duct, air_empty)

# ── DraftSystem ───────────────────────────────────────────────────────────────
draft_empty = add_empty('DraftSystem', (1.3, 0, 2.0))
set_parent(draft_empty, boiler_root)

# Induced Draft Fan (ID Fan - exaustão)
id_fan = create_fan_blades('InducedDraftFan', 0.3, 8,
                            (1.5, 0, 2.8), material=mat_fan_blade)
set_parent(id_fan, draft_empty)

# Forced Draft Fan (FD Fan)
fd_fan = create_fan_blades('ForcedDraftFan', 0.25, 6,
                            (1.5, 0, 1.2), material=mat_fan_blade)
set_parent(fd_fan, draft_empty)

# Flue Gas Damper
flue_damper = add_cube('FlueGasDamper', 0.1, (1.3, 0, 2.5),
                        scale=(0.3, 1.2, 0.05), material=mat_steel)
set_parent(flue_damper, draft_empty)

# Stack / chimney
stack = add_cylinder('Stack', 0.2, 1.5, (1.5, 0, 3.5),
                      segments=24, material=mat_steel_dark)
set_parent(stack, draft_empty)

# ── GasDucts ──────────────────────────────────────────────────────────────────
gas_ducts_empty = add_empty('GasDucts', (0.8, 0, 2.0))
set_parent(gas_ducts_empty, boiler_root)

# Horizontal duct from furnace to economizer area
duct1 = add_cube('GasDuct_Horizontal', 0.4, (0.5, 0, 1.8),
                  scale=(2.0, 1.0, 0.6), material=mat_steel_dark)
set_parent(duct1, gas_ducts_empty)

# Vertical duct up to stack
duct2 = add_cube('GasDuct_Vertical', 0.4, (1.3, 0, 2.5),
                  scale=(0.6, 1.0, 1.5), material=mat_steel_dark)
set_parent(duct2, gas_ducts_empty)

# ── Economizer ────────────────────────────────────────────────────────────────
econ_empty = add_empty('Economizer', (0.9, 0, 1.2))
set_parent(econ_empty, boiler_root)

# Economizer tubes (serpentine)
n_econ = 8
for i in range(n_econ):
    z = 0.8 + i * 0.08
    etube = add_cylinder(f'Econ_Tube_{i}', 0.02, 0.8,
                          (0.9, 0, z),
                          rotation=(math.pi/2, 0, 0),
                          material=mat_copper)
    set_parent(etube, econ_empty)

# Economizer housing
econ_housing = add_cube('Economizer_Housing', 0.5, (0.9, 0, 1.1),
                         scale=(0.8, 1.3, 1.2), material=mat_steel_dark)
set_parent(econ_housing, econ_empty)

# ── FlowIndicators (setas de fluxo) ──────────────────────────────────────────
flow_empty = add_empty('FlowIndicators', (0, 0, 0))
set_parent(flow_empty, boiler_root)

def create_arrow(name, start, end, material):
    """Simple arrow using a thin cylinder + cone."""
    dx = end[0] - start[0]
    dy = end[1] - start[1]
    dz = end[2] - start[2]
    length = math.sqrt(dx*dx + dy*dy + dz*dz)
    if length < 0.001:
        return
    cx = (start[0] + end[0]) / 2
    cy = (start[1] + end[1]) / 2
    cz = (start[2] + end[2]) / 2
    
    phi = math.atan2(dy, dx)
    theta = math.acos(dz / length) if length > 0 else 0
    
    shaft = add_cylinder(f'{name}_Shaft', 0.015, length * 0.8,
                          (cx, cy, cz),
                          rotation=(theta, 0, phi),
                          segments=8, material=material)
    set_parent(shaft, flow_empty)
    
    # Arrowhead
    tip_x = end[0] - dx * 0.1
    tip_y = end[1] - dy * 0.1
    tip_z = end[2] - dz * 0.1
    bpy.ops.mesh.primitive_cone_add(
        radius1=0.04, depth=length * 0.15,
        location=(tip_x, tip_y, tip_z),
        rotation=(theta, 0, phi),
        vertices=8
    )
    tip = bpy.context.active_object
    tip.name = f'{name}_Tip'
    if material:
        tip.data.materials.append(material)
    set_parent(tip, flow_empty)

# Water flow arrows (blue)
create_arrow('Flow_Water_1', (-0.3, -0.7, 0.2), (-0.3, -0.7, 2.5), mat_flow_blue)
create_arrow('Flow_Water_2', (0.7, -0.7, 0.2), (0.7, -0.7, 2.5), mat_flow_blue)

# Hot gas flow arrows (red)
create_arrow('Flow_Gas_1', (-0.2, 0, 1.6), (1.0, 0, 1.6), mat_flow_red)
create_arrow('Flow_Gas_2', (1.2, 0, 1.8), (1.2, 0, 2.8), mat_flow_red)

# Combustion arrows (orange)
create_arrow('Flow_Combustion', (-1.3, 0, 0.5), (-0.5, 0, 0.5), mat_flow_orange)

# ═══════════════════════════════════════════════════════════════════════════════
#  FINALIZE & EXPORT
# ═══════════════════════════════════════════════════════════════════════════════

# Apply all transforms
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

# Set smooth shading for meshes
for obj in bpy.data.objects:
    if obj.type == 'MESH':
        for poly in obj.data.polygons:
            poly.use_smooth = True

# Export as GLB
output_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'boiler.glb')

# glTF export with version-compatible parameters
export_args = dict(
    filepath=output_path,
    export_format='GLB',
    use_selection=False,
    export_apply=True,
    export_cameras=False,
    export_lights=False,
    export_materials='EXPORT',
    export_normals=True,
)
# Parameters that may not exist in all Blender versions
try:
    bpy.ops.export_scene.gltf(**export_args,
        export_animations=True,
        export_tangentials=False,
        export_draco_mesh_compression_enable=False,
    )
except TypeError:
    # Fallback for Blender versions with different parameter names
    bpy.ops.export_scene.gltf(**export_args)

print(f'\n✅ Model exported to: {output_path}')
print(f'   Objects: {len(bpy.data.objects)}')
print(f'   Materials: {len(bpy.data.materials)}')
