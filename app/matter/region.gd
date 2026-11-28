extends Node3D
const Field = preload("res://matter/field_model.gd")
const MaterialShader = preload("res://matter/matter.gdshader")
const SEGMENTS := 80
const PARTICLES := 48
var surface: MeshInstance3D
var shader: ShaderMaterial
var dots: MultiMeshInstance3D
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
	triangle_count = indices.size() / 3
	builds += 1
	shader.set_shader_parameter("mode", built_mode)
	shader.set_shader_parameter("row_count", float(rows))
	shader.set_shader_parameter("seed_phase", fposmod(float(p.seed) * 0.618, TAU))
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

static func field_config(p: Dictionary) -> Dictionary:
	return {"field": int(p.field), "secondary": int(p.secondary), "mix": float(p.mix),
		"strength": float(p.strength), "origin": Vector3(p.origin_x,p.origin_y,p.origin_z)}

func update(p: Dictionary, clocks: Dictionary, delta: float, advancing: bool, shown: bool) -> void:
	visible = shown and p.visible >= 0.5
	if not visible:
		dots.visible = false
		return
	position = Vector3(p.x, p.y, p.z)
	rotation = Vector3(0.0,p.rotation,0.0)
	scale = Vector3.ONE * float(p.scale)
	for key in ["condensation","shell","thickness","roughness","absorption","opacity","pore_size","growth","strength","deformation","line_width","hue","trails"]:
		shader.set_shader_parameter(key, p[key])
	shader.set_shader_parameter("blend_field", p.mix)
	shader.set_shader_parameter("field_origin", Vector3(p.origin_x,p.origin_y,p.origin_z))
	shader.set_shader_parameter("flow_time", fposmod(float(clocks.filament), 1200.0))
	shader.set_shader_parameter("shape_time", fposmod(float(clocks.displacement), 1200.0))
	shader.set_shader_parameter("normal_time", fposmod(float(clocks.normal), 1200.0))
	shader.set_shader_parameter("optical_time", fposmod(float(clocks.sky), 1200.0))
	shader.set_shader_parameter("colour_time", fposmod(float(clocks.palette), 1200.0))
	dots.visible = built_mode == 0 and p.particles >= 0.5
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

func metrics() -> Dictionary:
	return {"visible": visible, "mode": built_mode, "strips": rows, "vertices": vertex_count,
		"triangles": triangle_count, "geometry_builds": builds, "particle_uploads": particle_uploads,
		"particles": positions.size() if dots.visible else 0, "fixed_steps": fixed_steps,
		"dropped_steps": dropped_steps, "field_update_usec": field_usec}
