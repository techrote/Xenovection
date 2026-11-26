extends Node3D
## Persistent source-addressable hairlines, decorative fibres and quiet nodes.
## Source/selection changes upload instance buffers. Animation only writes
## constant-size shader uniforms; there is deliberately no _process method.

const FILAMENT_SHADER = preload("res://rendering/filaments/filament.gdshader")
const NODE_SHADER = preload("res://rendering/filaments/node_marker.gdshader")
const DEFAULTS := {
	"enabled": true, "scientific": false, "nodes_visible": true,
	"line_width_px": 0.52, "opacity": 0.16, "intensity": 0.9,
	"phase_speed": 0.70, "phase_frequency": 2.4,
	"wave_amplitude": 0.11, "wave_frequency": 1.5,
	"braid_radius": 0.065, "braid_turns": 2.0,
	"turbulence": 0.025, "resonance": 0.04,
	"palette_amount": 0.18, "palette_phase": 0.0,
	"coverage": 1.0, "adaptive_coverage": 1.0, "selection_fade": 0.28,
	"fibres": 2, "segments": 24, "node_radius": 0.012,
	"counterflow": true,
	"positive_colour": Color(0.08, 0.72, 0.87),
	"negative_colour": Color(0.95, 0.23, 0.19),
}
const NUMERIC_BOUNDS := {
	"line_width_px": Vector2(0.05, 6.0), "opacity": Vector2(0.0, 1.0),
	"intensity": Vector2(0.0, 4.0), "phase_speed": Vector2(-8.0, 8.0),
	"phase_frequency": Vector2(0.0, 16.0), "wave_amplitude": Vector2(0.0, 2.0),
	"wave_frequency": Vector2(0.0, 8.0), "braid_radius": Vector2(0.0, 1.0),
	"braid_turns": Vector2(0.0, 8.0), "turbulence": Vector2(0.0, 1.0),
	"resonance": Vector2(0.0, 1.0), "palette_amount": Vector2(0.0, 1.0),
	"palette_phase": Vector2(-10000.0, 10000.0), "coverage": Vector2(0.0, 1.0),
	"adaptive_coverage": Vector2(0.0, 1.0),
	"selection_fade": Vector2(0.0, 1.0), "node_radius": Vector2(0.002, 0.10),
}

var parameters: Dictionary = DEFAULTS.duplicate(true)
var visual_state: Dictionary = {
	"node_ids": [], "edge_ids": [], "isolate": false,
	"hidden_layers": [], "materialisation": "filaments",
}
var _dataset: Dictionary = {"nodes": [], "edges": [], "manifest": {}}
var _primary: MultiMeshInstance3D
var _secondary: MultiMeshInstance3D
var _nodes: MultiMeshInstance3D
var _primary_material: ShaderMaterial
var _secondary_material: ShaderMaterial
var _node_material: ShaderMaterial
var _ribbon_mesh: ArrayMesh
var _scientific_mesh: ArrayMesh
var _node_mesh: SphereMesh
var _source_edge_ids: Array[String] = []
var _source_node_ids: Array[String] = []
var _edge_id_to_source_index: Dictionary = {}
var _edge_transforms: Array[Transform3D] = []
var _edge_seeds := PackedFloat32Array()
var _primary_visible_edge_ids: Array[String] = []
var _visible_edge_lookup: Dictionary = {}
var _visible_node_lookup: Dictionary = {}
var _primary_visible_source_indices: PackedInt32Array = PackedInt32Array()
var _node_selected: Dictionary = {}
var _edge_selected: Dictionary = {}
var _mesh_build_count := 0
var _instance_upload_count := 0
var _instance_rebuild_count := 0
var _uniform_update_count := 0
var _invalid_edges := 0
var _last_rebuild_usec := 0
var _bounds := AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
var _clocks: Dictionary = {"filament": 0.0, "palette": 0.0}
var _sent_primary_clocks: Dictionary = {}
var _sent_secondary_clocks: Dictionary = {}


func _ready() -> void:
	_ensure_resources()


func _ensure_resources() -> void:
	if is_instance_valid(_primary):
		return
	_primary_material = ShaderMaterial.new()
	_primary_material.shader = FILAMENT_SHADER
	_secondary_material = ShaderMaterial.new()
	_secondary_material.shader = FILAMENT_SHADER
	_secondary_material.set_shader_parameter("decorative", true)
	_node_material = ShaderMaterial.new()
	_node_material.shader = NODE_SHADER
	_primary = _make_pass("ExactPrimaryFilaments", _primary_material)
	_secondary = _make_pass("DecorativeSecondaryFibres", _secondary_material)
	_nodes = _make_pass("SourceNodeMarkers", _node_material)
	_node_mesh = SphereMesh.new()
	_node_mesh.radius = 1.0
	_node_mesh.height = 2.0
	_node_mesh.radial_segments = 8
	_node_mesh.rings = 4
	_nodes.multimesh.mesh = _node_mesh
	_rebuild_ribbon_mesh()
	_apply_uniforms()
	_apply_visibility()


func _make_pass(pass_name: String, material: ShaderMaterial) -> MultiMeshInstance3D:
	var instance := MultiMeshInstance3D.new()
	instance.name = pass_name
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.material_override = material
	instance.extra_cull_margin = 8.0
	var population := MultiMesh.new()
	population.transform_format = MultiMesh.TRANSFORM_3D
	population.use_custom_data = true
	instance.multimesh = population
	add_child(instance)
	return instance


func set_dataset(dataset: Dictionary) -> void:
	_ensure_resources()
	# Copy the source contract so subsequent caller mutations cannot silently
	# alter renderer mappings. No render setting ever writes to source data.
	_dataset = dataset.duplicate(true)
	if not (_dataset.get("nodes", []) is Array) or not (_dataset.get("edges", []) is Array):
		_dataset = {"nodes": [], "edges": [], "manifest": {}}
	_source_edge_ids.clear()
	_source_node_ids.clear()
	_edge_id_to_source_index.clear()
	var nodes: Array = _dataset.get("nodes", [])
	var edges: Array = _dataset.get("edges", [])
	_edge_transforms.resize(edges.size())
	_edge_seeds.resize(edges.size())
	for i in range(nodes.size()):
		_source_node_ids.append(str(nodes[i].get("id", "node:%d" % i)))
	for i in range(edges.size()):
		var edge_id := str(edges[i].get("id", "edge:%d" % i))
		_source_edge_ids.append(edge_id)
		_edge_id_to_source_index[edge_id] = i
		var edge: Dictionary = edges[i]
		var a := _position(edge.get("a", Vector3.ZERO))
		var b := _position(edge.get("b", Vector3.ZERO))
		_edge_transforms[i] = edge_transform(a, b) if a.is_finite() and b.is_finite() and a.distance_squared_to(b) > 0.00000001 else Transform3D.IDENTITY
		_edge_seeds[i] = fposmod(float(int(edge.get("index", i))) * 0.618033988749895 + 0.173, 1.0)
	_recompute_bounds()
	_rebuild_instances()


func set_visual_state(state: Dictionary) -> void:
	_ensure_resources()
	var next := visual_state.duplicate(true)
	next.merge(state, true)
	# A proxy style alone does not affect the primary representation. Avoid
	# needless uploads when materialising/unmaterialising a source selection.
	var changed: bool = next.get("node_ids", []) != visual_state.get("node_ids", []) \
		or next.get("edge_ids", []) != visual_state.get("edge_ids", []) \
		or next.get("isolate", false) != visual_state.get("isolate", false) \
		or next.get("hidden_layers", []) != visual_state.get("hidden_layers", [])
	visual_state = next
	if changed:
		_rebuild_instances()


func set_parameters(values: Dictionary) -> void:
	_ensure_resources()
	var prior_fibres := int(parameters.fibres)
	var prior_segments := int(parameters.segments)
	var changed: Array = []
	for key in values:
		if not DEFAULTS.has(key):
			continue
		var value: Variant = values[key]
		var prior_value: Variant = parameters[key]
		if NUMERIC_BOUNDS.has(key):
			if not (value is int or value is float) or not is_finite(float(value)):
				continue
			var limits: Vector2 = NUMERIC_BOUNDS[key]
			parameters[key] = clampf(float(value), limits.x, limits.y)
		elif key == "fibres" or key == "segments":
			if (value is int or value is float) and is_finite(float(value)):
				parameters[key] = clampi(int(value), 0, 4) if key == "fibres" else clampi(int(value), 4, 64)
		elif DEFAULTS[key] is bool:
			if value is bool:
				parameters[key] = value
		elif DEFAULTS[key] is Color and value is Color:
			var c: Color = value
			if is_finite(c.r) and is_finite(c.g) and is_finite(c.b) and is_finite(c.a):
				parameters[key] = Color(clampf(c.r, 0.0, 4.0), clampf(c.g, 0.0, 4.0), clampf(c.b, 0.0, 4.0), clampf(c.a, 0.0, 1.0))
		if parameters[key] != prior_value:
			changed.append(key)
	if changed.is_empty():
		return
	if int(parameters.segments) != prior_segments:
		_rebuild_ribbon_mesh()
	if int(parameters.fibres) != prior_fibres:
		_rebuild_instances()
	_apply_uniforms(changed)
	if "enabled" in changed or "scientific" in changed or "nodes_visible" in changed or "fibres" in changed:
		_apply_visibility()


func update_clocks(clocks: Dictionary) -> void:
	# Inactive passes do no per-frame uniform work. Shader clocks are explicit,
	# never TIME, so pause/reverse/reset are deterministic and independently owned.
	if not bool(parameters.enabled) or bool(parameters.scientific):
		return
	_ensure_resources()
	for key in ["filament", "palette"]:
		var value: Variant = clocks.get(key, _clocks[key])
		if (value is float or value is int) and is_finite(float(value)):
			_clocks[key] = clampf(float(value), -1000000.0, 1000000.0)
	for material in [_primary_material, _secondary_material]:
		if material == _secondary_material and not _secondary.visible:
			continue
		var sent: Dictionary = _sent_secondary_clocks if material == _secondary_material else _sent_primary_clocks
		for key in ["filament", "palette"]:
			if not sent.has(key) or sent[key] != _clocks[key]:
				material.set_shader_parameter("clock_" + key, _clocks[key])
				sent[key] = _clocks[key]
				_uniform_update_count += 1


func _apply_uniforms(changed: Array = []) -> void:
	var keys: Array = parameters.keys() if changed.is_empty() else changed
	for key in keys:
		if key in ["enabled", "nodes_visible", "fibres", "segments", "node_radius"]:
			continue
		_primary_material.set_shader_parameter(key, parameters[key])
		_secondary_material.set_shader_parameter(key, parameters[key])
	_primary_material.set_shader_parameter("has_selection", not _edge_selected.is_empty())
	_secondary_material.set_shader_parameter("has_selection", not _edge_selected.is_empty())
	_node_material.set_shader_parameter("has_selection", not _node_selected.is_empty())
	_node_material.set_shader_parameter("node_radius", parameters.node_radius)
	_node_material.set_shader_parameter("selection_fade", parameters.selection_fade)
	_node_material.set_shader_parameter("positive_colour", parameters.positive_colour)
	_node_material.set_shader_parameter("negative_colour", parameters.negative_colour)


func _apply_visibility() -> void:
	_primary.visible = bool(parameters.enabled)
	_primary.multimesh.mesh = _scientific_mesh if bool(parameters.scientific) else _ribbon_mesh
	_secondary.visible = bool(parameters.enabled) and not bool(parameters.scientific) and int(parameters.fibres) > 0
	_nodes.visible = bool(parameters.enabled) and bool(parameters.nodes_visible)


func _rebuild_ribbon_mesh() -> void:
	_ribbon_mesh = _make_ribbon_mesh(int(parameters.segments))
	if _scientific_mesh == null:
		_scientific_mesh = _make_ribbon_mesh(1)
	_primary.multimesh.mesh = _scientific_mesh if bool(parameters.scientific) else _ribbon_mesh
	_secondary.multimesh.mesh = _ribbon_mesh


func _make_ribbon_mesh(segments: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	vertices.resize((segments + 1) * 2)
	normals.resize(vertices.size())
	uvs.resize(vertices.size())
	indices.resize(segments * 6)
	for j in range(segments + 1):
		var t := float(j) / float(segments)
		for side in range(2):
			var index := j * 2 + side
			vertices[index] = Vector3(0.0, t, 0.0)
			normals[index] = Vector3(0, 0, 1)
			uvs[index] = Vector2(t, float(side))
	for j in range(segments):
		var k := j * 2
		var offset := j * 6
		indices[offset] = k
		indices[offset + 1] = k + 1
		indices[offset + 2] = k + 2
		indices[offset + 3] = k + 1
		indices[offset + 4] = k + 3
		indices[offset + 5] = k + 2
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_build_count += 1
	return mesh


func _recompute_bounds() -> void:
	var first := true
	for node in _dataset.get("nodes", []):
		var p := _position(node.get("position", Vector3.ZERO))
		if not p.is_finite():
			continue
		if first:
			_bounds = AABB(p, Vector3.ZERO)
			first = false
		else:
			_bounds = _bounds.expand(p)
	if first:
		_bounds = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	# Maximum allowed waves + braid + turbulence + resonance stay under this
	# fixed margin, avoiding a per-frame visibility-bound update.
	_bounds = _bounds.grow(6.0)
	for population in [_primary, _secondary, _nodes]:
		population.multimesh.custom_aabb = _bounds


func _rebuild_instances() -> void:
	var start := Time.get_ticks_usec()
	_node_selected.clear()
	_edge_selected.clear()
	for id in visual_state.get("node_ids", []):
		_node_selected[str(id)] = true
	for id in visual_state.get("edge_ids", []):
		_edge_selected[str(id)] = true
	var hidden := {}
	for layer in visual_state.get("hidden_layers", []):
		hidden[int(layer)] = true
	var isolate := bool(visual_state.get("isolate", false))
	var nodes: Array = _dataset.get("nodes", [])
	var edges: Array = _dataset.get("edges", [])
	var visible_edges: Array[int] = []
	var visible_nodes: Array[int] = []
	_invalid_edges = 0
	_primary_visible_edge_ids.clear()
	_primary_visible_source_indices.clear()
	_visible_edge_lookup.clear()
	_visible_node_lookup.clear()
	for i in range(nodes.size()):
		var node: Dictionary = nodes[i]
		if hidden.has(int(node.get("layer", -1))):
			continue
		if isolate and not _node_selected.has(_source_node_ids[i]):
			continue
		if _position(node.get("position", Vector3.ZERO)).is_finite():
			visible_nodes.append(i)
			_visible_node_lookup[_source_node_ids[i]] = true
	for i in range(edges.size()):
		var edge: Dictionary = edges[i]
		var from_index := int(edge.get("from_index", -1))
		var to_index := int(edge.get("to_index", -1))
		if from_index < 0 or from_index >= nodes.size() or to_index < 0 or to_index >= nodes.size():
			_invalid_edges += 1
			continue
		if hidden.has(int(nodes[from_index].get("layer", -1))) or hidden.has(int(nodes[to_index].get("layer", -1))):
			continue
		if isolate and not _edge_selected.has(_source_edge_ids[i]):
			continue
		var a := _position(edge.get("a", nodes[from_index].get("position", Vector3.ZERO)))
		var b := _position(edge.get("b", nodes[to_index].get("position", Vector3.ZERO)))
		var weight := float(edge.get("weight", 0.0))
		if not a.is_finite() or not b.is_finite() or not is_finite(weight) or a.distance_squared_to(b) < 0.00000001:
			_invalid_edges += 1
			continue
		visible_edges.append(i)
		_primary_visible_edge_ids.append(_source_edge_ids[i])
		_primary_visible_source_indices.append(i)
		_visible_edge_lookup[_source_edge_ids[i]] = true
	var primary_data := PackedFloat32Array()
	var secondary_data := PackedFloat32Array()
	var node_data := PackedFloat32Array()
	var fibres := int(parameters.fibres)
	primary_data.resize(visible_edges.size() * 16)
	secondary_data.resize(visible_edges.size() * fibres * 16)
	node_data.resize(visible_nodes.size() * 16)
	for render_index in range(visible_edges.size()):
		var source_index := visible_edges[render_index]
		var edge: Dictionary = edges[source_index]
		var transform: Transform3D = _edge_transforms[source_index]
		var seed: float = _edge_seeds[source_index]
		var selected := 1.0 if _edge_selected.has(_source_edge_ids[source_index]) else 0.0
		var weight := float(edge.get("weight", 0.0))
		_write_instance(primary_data, render_index, transform, Color(seed, weight, selected, 0.0))
		for fibre in range(fibres):
			var fibre_phase := float(fibre + 1) / float(fibres + 1)
			_write_instance(secondary_data, render_index * fibres + fibre, transform, Color(seed, weight, selected, fibre_phase))
	for render_index in range(visible_nodes.size()):
		var source_index := visible_nodes[render_index]
		var node: Dictionary = nodes[source_index]
		var position := _position(node.get("position", Vector3.ZERO))
		var selected := 1.0 if _node_selected.has(_source_node_ids[source_index]) else 0.0
		var value := float(node.get("value", 0.0))
		if not is_finite(value):
			value = 0.0
		_write_instance(node_data, render_index, Transform3D(Basis.IDENTITY, position), Color(value, selected, 0.0, 0.0))
	_upload(_primary.multimesh, primary_data, visible_edges.size())
	_upload(_secondary.multimesh, secondary_data, visible_edges.size() * fibres)
	_upload(_nodes.multimesh, node_data, visible_nodes.size())
	_instance_rebuild_count += 1
	_last_rebuild_usec = Time.get_ticks_usec() - start
	_apply_uniforms()
	_apply_visibility()


func _upload(population: MultiMesh, data: PackedFloat32Array, count: int) -> void:
	population.instance_count = count
	if count > 0:
		population.buffer = data
	_instance_upload_count += 1


static func edge_transform(a: Vector3, b: Vector3) -> Transform3D:
	var delta := b - a
	var direction := delta.normalized()
	var reference := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
	var tangent_x := direction.cross(reference).normalized()
	var tangent_z := tangent_x.cross(direction).normalized()
	return Transform3D(Basis(tangent_x, delta, tangent_z), a)


static func _position(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


static func _write_instance(buffer: PackedFloat32Array, index: int, transform: Transform3D, custom: Color) -> void:
	# Godot MultiMesh 3D buffer layout: three row-major vec4 transform rows,
	# then four custom floats. No per-instance colour storage is allocated.
	var offset := index * 16
	buffer[offset] = transform.basis.x.x
	buffer[offset + 1] = transform.basis.y.x
	buffer[offset + 2] = transform.basis.z.x
	buffer[offset + 3] = transform.origin.x
	buffer[offset + 4] = transform.basis.x.y
	buffer[offset + 5] = transform.basis.y.y
	buffer[offset + 6] = transform.basis.z.y
	buffer[offset + 7] = transform.origin.y
	buffer[offset + 8] = transform.basis.x.z
	buffer[offset + 9] = transform.basis.y.z
	buffer[offset + 10] = transform.basis.z.z
	buffer[offset + 11] = transform.origin.z
	buffer[offset + 12] = custom.r
	buffer[offset + 13] = custom.g
	buffer[offset + 14] = custom.b
	buffer[offset + 15] = custom.a


func source_edge_id_for_instance(instance_index: int) -> String:
	if instance_index < 0 or instance_index >= _primary_visible_edge_ids.size():
		return ""
	return _primary_visible_edge_ids[instance_index]


func source_index_for_edge(edge_id: String) -> int:
	return int(_edge_id_to_source_index.get(edge_id, -1))


func source_edge_is_visible(edge_id: String) -> bool:
	return bool(parameters.enabled) and _visible_edge_lookup.has(edge_id)


func source_node_is_visible(node_id: String) -> bool:
	return bool(parameters.enabled) and bool(parameters.nodes_visible) and _visible_node_lookup.has(node_id)


func curve_sample_count() -> int:
	# Number of segment intervals; callers sample 0..count inclusive. This is
	# the same tessellation as the submitted primary mesh, not an arbitrary
	# finer approximation that could select invisible bends.
	return 1 if bool(parameters.scientific) else int(parameters.segments)


func max_primary_offset() -> float:
	if bool(parameters.scientific):
		return 0.0
	var local_bound := 1.2 * float(parameters.wave_amplitude) + 1.2 * float(parameters.resonance) + 1.5 * float(parameters.turbulence)
	var world_scale := global_transform.basis.get_scale().abs()
	return local_bound * maxf(world_scale.x, maxf(world_scale.y, world_scale.z))


func curve_world_position(edge_id: String, t: float) -> Vector3:
	# Deliberately evaluated only for bounded click candidates by the picker.
	# This mirrors filament.gdshader path_at() for primary (nondecorative)
	# instances, including stable float32 seed and independent explicit clocks.
	var source_index := source_index_for_edge(edge_id)
	if source_index < 0:
		return Vector3(INF, INF, INF)
	var position := Vector3(0.0, clampf(t, 0.0, 1.0), 0.0)
	if not bool(parameters.scientific):
		var u: float = position.y
		var seed: float = _edge_seeds[source_index]
		var direction := -1.0 if bool(parameters.counterflow) and seed < 0.5 else 1.0
		var phase: float = float(_clocks.filament) * float(parameters.phase_speed) * direction
		var offset := Vector2.ZERO
		var amplitude: float = parameters.wave_amplitude
		var frequency: float = parameters.wave_frequency
		if amplitude > 0.00001:
			var a: float = TAU * frequency * u - phase + seed * TAU
			var b: float = TAU * frequency * 0.73 * u + phase * 0.69 + seed * 9.1
			offset += amplitude * Vector2(sin(a), 0.55 * sin(b))
		if float(parameters.resonance) > 0.00001:
			var carrier := sin(float(_clocks.filament) * 1.27 + seed * TAU)
			offset += float(parameters.resonance) * carrier * Vector2(sin(PI * 3.0 * u), 0.6 * sin(PI * 2.0 * u))
		if float(parameters.turbulence) > 0.00001:
			var a: float = TAU * 3.3 * u + float(_clocks.filament) * 0.41 + seed * 17.0
			var b: float = TAU * 5.1 * u - float(_clocks.filament) * 0.29 + seed * 23.0
			offset += float(parameters.turbulence) * Vector2(sin(a) * cos(b), cos(a) * sin(b))
		var envelope := 4.0 * u * (1.0 - u)
		position.x = envelope * offset.x
		position.z = envelope * offset.y
	return global_transform * (_edge_transforms[source_index] * position)


func visible_source_edge_ids() -> Array[String]:
	return _primary_visible_edge_ids.duplicate()


func get_metrics() -> Dictionary:
	_ensure_resources()
	var primary_count := _primary.multimesh.instance_count if _primary.visible else 0
	var secondary_count := _secondary.multimesh.instance_count if _secondary.visible else 0
	var node_count := _nodes.multimesh.instance_count if _nodes.visible else 0
	var stored_count := _primary.multimesh.instance_count + _secondary.multimesh.instance_count + _nodes.multimesh.instance_count
	var segments := 1 if bool(parameters.scientific) else int(parameters.segments)
	var mesh_segments := int(parameters.segments)
	var estimated_bytes := stored_count * 64 + (mesh_segments + 1) * 2 * 32 + mesh_segments * 6 * 4 + 152
	return {
		"primary_edges": primary_count, "secondary_fibres": secondary_count,
		"visible_strands": primary_count + secondary_count, "visible_nodes": node_count,
		"segments_per_strand": segments, "active_segments": (primary_count + secondary_count) * segments,
		"active_triangles": (primary_count + secondary_count) * segments * 2,
		"submitted_passes": int(primary_count > 0) + int(secondary_count > 0) + int(node_count > 0),
		"instance_buffer_bytes_estimate": stored_count * 64,
		"geometry_bytes_estimate": estimated_bytes,
		"memory_kind": "estimate: instance buffers + shared ribbon; excludes engine, textures and driver",
		"mesh_build_count": _mesh_build_count, "instance_upload_count": _instance_upload_count,
		"instance_rebuild_count": _instance_rebuild_count, "uniform_update_count": _uniform_update_count,
		"last_instance_rebuild_ms": float(_last_rebuild_usec) / 1000.0,
		"invalid_or_degenerate_edges": _invalid_edges,
		"source_edges": _source_edge_ids.size(), "source_nodes": _source_node_ids.size(),
		"scientific": bool(parameters.scientific),
		"source_revision": _dataset.get("manifest", {}).get("revision", ""),
	}
