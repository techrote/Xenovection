extends Node3D
const Field = preload("res://matter/field_model.gd")
const MaterialBridge = preload("res://rendering/optical/material_bridge.gd")
const ParticleOpticalShader = preload("res://rendering/optical/generated_optical.gdshader")
const MaterialShader = preload("res://matter/matter.gdshader")
const SEGMENTS := 80
const PARTICLES := 48
var identity := "matter.unassigned.material"
var surface: MeshInstance3D
var shader: ShaderMaterial
var dots: MultiMeshInstance3D
var particle_shader: ShaderMaterial
var positions := PackedVector3Array()
var builds := 0
var particle_uploads := 0
var fixed_steps := 0
var dropped_steps := 0
var field_usec := 0
var particle_time := 0.0
var accumulator := 0.0
var vertex_count := 0
var triangle_count := 0
var rows := 0
var built_mode := 1
var material_updates := 0
var optical_updates := 0
var geometry_upload_bytes := 0
var particle_upload_bytes := 0
var _uniform_cache: Dictionary = {}
var _particle_uniform_cache: Dictionary = {}

func _ready() -> void:
	surface = MeshInstance3D.new()
	surface.custom_aabb = AABB(Vector3.ONE * -12.0, Vector3.ONE * 24.0)
	shader = ShaderMaterial.new()
	shader.shader = MaterialShader
	surface.material_override = shader
	add_child(surface)
	dots = MultiMeshInstance3D.new()
	dots.custom_aabb = AABB(Vector3.ONE * -6.0, Vector3.ONE * 12.0)
	var sphere := SphereMesh.new()
	sphere.radius = 0.017
	sphere.height = 0.034
	sphere.radial_segments = 5
	sphere.rings = 2
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = Color(0.65,0.9,0.92)
	sphere.material = ink
	particle_shader = ShaderMaterial.new()
	particle_shader.shader = ParticleOpticalShader
	particle_shader.set_shader_parameter("family_tint",Color(0.65,0.9,0.92,1.0))
	material_updates += 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sphere
	mm.instance_count = PARTICLES
	dots.multimesh = mm
	dots.visible = false
	add_child(dots)

func rebuild(p: Dictionary) -> void:
	var start := Time.get_ticks_usec()
	rows = clampi(int(p.count), 24, 192)
	built_mode = clampi(int(p.mode), 0, 1)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	var seeds := Field.seeds(int(p.seed), rows)
	var cfg := field_config(p)
	for row in range(rows):
		var curve := PackedVector3Array()
		if built_mode == 0:
			curve = Field.path(seeds[row], SEGMENTS + 1, float(p.integration), cfg, p.pathline >= 0.5)
		var offset := vertices.size()
		for j in range(SEGMENTS + 1):
			var u := float(j) / SEGMENTS
			var point := Vector3(u, (float(row) + 0.5) / rows, 0.0)
			var tangent := Vector3.UP
			if built_mode == 0:
				point = curve[j]
				tangent = (curve[mini(j+1, SEGMENTS)] - curve[maxi(j-1,0)]).normalized()
				if tangent.length_squared() < 0.001: tangent = Vector3.UP
			for side in range(2):
				vertices.append(point)
				normals.append(tangent)
				uv.append(Vector2(u, float(side)))
			if j < SEGMENTS:
				var k := offset + j * 2
				indices.append_array(PackedInt32Array([k,k+1,k+2,k+1,k+3,k+2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	surface.mesh = mesh
	vertex_count = vertices.size()
	triangle_count = int(indices.size() / 3.0)
	builds += 1
	geometry_upload_bytes += vertices.size() * 12 + normals.size() * 12 + uv.size() * 8 + indices.size() * 4
	_send("mode", built_mode)
	_send("row_count", float(rows))
	_send("seed_phase", fposmod(float(p.seed) * 0.618, TAU))
	reset_particles(int(p.seed))
	field_usec = Time.get_ticks_usec() - start

func reset_particles(seed_value: int) -> void:
	positions = Field.seeds(seed_value + 7919, PARTICLES)
	particle_time = 0.0
	accumulator = 0.0
	fixed_steps = 0
	dropped_steps = 0
	_upload_particles()

func _upload_particles() -> void:
	for i in range(positions.size()):
		dots.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, positions[i]))
	particle_uploads += 1
	particle_upload_bytes += positions.size() * 12 * 4

static func field_config(p: Dictionary) -> Dictionary:
	return {"field": int(p.field), "secondary": int(p.secondary), "mix": float(p.mix),
		"strength": float(p.strength), "origin": Vector3(p.origin_x,p.origin_y,p.origin_z)}

func update(p: Dictionary, clocks: Dictionary, delta: float, advancing: bool, shown: bool, optical_context: Dictionary = {}) -> void:
	visible = shown and p.visible >= 0.5
	if not visible:
		dots.visible = false
		return
	position = Vector3(p.x, p.y, p.z)
	rotation = Vector3(0.0,p.rotation,0.0)
	scale = Vector3.ONE * float(p.scale)
	for key in ["condensation","shell","thickness","roughness","absorption","opacity","pore_size","growth","strength","deformation","line_width","hue","trails"]:
		_send(key, p[key])
	_send("blend_field", p.mix)
	_send("field_kind", int(p.field))
	_send("secondary_kind", int(p.secondary))
	_send("field_origin", Vector3(p.origin_x,p.origin_y,p.origin_z))
	_send("flow_time", clampf(float(clocks.filament), -1000000.0, 1000000.0))
	_send("shape_time", clampf(float(clocks.displacement), -1000000.0, 1000000.0))
	_send("normal_time", clampf(float(clocks.normal), -1000000.0, 1000000.0))
	_send("optical_time", clampf(float(clocks.sky), -1000000.0, 1000000.0))
	_send("colour_time", clampf(float(clocks.palette), -1000000.0, 1000000.0))
	var optical_writes := MaterialBridge.apply_context(shader,optical_context,clocks,float(p.get("optical_mix",0.0)),_uniform_cache)
	material_updates += optical_writes
	optical_updates += optical_writes
	dots.visible = built_mode == 0 and p.particles >= 0.5
	if dots.visible:
		var particle_writes := MaterialBridge.apply_context(particle_shader,optical_context,clocks,float(p.get("optical_mix",0.0)),_particle_uniform_cache)
		material_updates += particle_writes
		optical_updates += particle_writes
		# The original opaque unshaded particle material remains exact at mix 0.
		var assigned: Material = particle_shader if float(_particle_uniform_cache.get("xeno_optical_mix",0.0)) > 0.0001 else null
		if dots.material_override != assigned:
			dots.material_override = assigned
	else:
		dots.material_override = null
	if not dots.visible or not advancing or not is_finite(delta) or delta <= 0.0:
		return
	var start := Time.get_ticks_usec()
	accumulator += minf(delta, 0.25)
	var cfg := field_config(p)
	var steps := 0
	while accumulator + 1.0e-9 >= Field.FIXED_STEP and steps < 4:
		for i in range(positions.size()):
			positions[i] = Field.step(positions[i],particle_time,Field.FIXED_STEP,cfg)
		particle_time += Field.FIXED_STEP
		accumulator -= Field.FIXED_STEP
		steps += 1
		fixed_steps += 1
	if accumulator >= Field.FIXED_STEP:
		dropped_steps += int(accumulator / Field.FIXED_STEP)
		accumulator = fposmod(accumulator, Field.FIXED_STEP)
	if steps > 0: _upload_particles()
	field_usec = Time.get_ticks_usec() - start

func _send(name: String, value: Variant) -> void:
	material_updates += MaterialBridge.set_uniform(shader,name,value,_uniform_cache)

func metrics() -> Dictionary:
	var shown := is_visible_in_tree()
	return {"visible": shown, "mode": built_mode, "strips": rows, "vertices": vertex_count,
		"triangles": triangle_count, "geometry_builds": builds, "particle_uploads": particle_uploads,
		"particles": positions.size() if dots.visible else 0, "fixed_steps": fixed_steps,
		"dropped_steps": dropped_steps, "field_update_usec": field_usec,
		"geometry_upload_count": builds, "geometry_upload_bytes_estimate": geometry_upload_bytes,
		"particle_upload_bytes_estimate": particle_upload_bytes,
		"material_uniform_writes": material_updates, "optical_uniform_writes": optical_updates,
		"optical_mix": float(_uniform_cache.get("xeno_optical_mix",0.0)),
		"optical_material_id": "optical:" + identity,
		"screen_copy": false, "allocated_materials": 3, "allocated_meshes": 1 + int(surface.mesh != null),
		"active_materials": (1 + int(dots.visible)) if shown else 0,
		"active_meshes": (int(surface.mesh != null) + int(dots.visible)) if shown else 0}
