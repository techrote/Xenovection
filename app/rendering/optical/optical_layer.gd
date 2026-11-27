class_name OpticalLayer
extends Node3D
## Selected-region artistic proxies. The dataset and selection are never edited.
## Meshes are built only on a membership/type change; animation is shader-only.

const SURFACE_SHADER := preload("res://rendering/optical/optical_surface.gdshader")
const TRANSLUCENT_SHADER := preload("res://rendering/optical/optical_translucent.gdshader")
const BACKGROUND_SHADER := preload("res://rendering/optical/spectral_background.gdshader")
const MAX_RIBBONS := 96
const DEFAULTS := {
	"enabled": true, "scientific": false, "sky_visible": true,
	"sky_frequency": Vector2(1.6, 2.1), "sky_speed": 0.55,
	"sky_diagonal": 0.65, "sky_radius": 1.7, "sky_warp": 0.38,
	"sky_contrast": 1.7, "sky_intensity": 2.3, "sky_rotation": 0.0,
	"sky_pan": Vector2.ZERO, "palette_phase": 0.0,
	"background_strength": 0.006, "roughness": 0.19, "metallic": 0.92,
	"normal_strength": 0.24, "displacement": 0.12, "domain_warp": 0.12,
	"surface_opacity": 1.0,
	"material_tint": Color(0.32, 0.59, 0.64), "palette": "glacier",
}
const LIMITS := {
	"sky_speed": Vector2(-8.0, 8.0), "sky_diagonal": Vector2(-8.0, 8.0),
	"sky_radius": Vector2(0.0, 12.0), "sky_warp": Vector2(0.0, 3.0),
	"sky_contrast": Vector2(0.1, 5.0), "sky_intensity": Vector2(0.0, 8.0),
	"sky_rotation": Vector2(-1000.0, 1000.0), "palette_phase": Vector2(-1000.0, 1000.0),
	"background_strength": Vector2(0.0, 0.3), "roughness": Vector2(0.02, 1.0),
	"metallic": Vector2(0.0, 1.0), "normal_strength": Vector2(0.0, 2.0),
	"displacement": Vector2(0.0, 1.0), "domain_warp": Vector2(0.0, 3.0),
	"surface_opacity": Vector2(0.1, 1.0),
}
const SHARED_KEYS := ["sky_frequency", "sky_speed", "sky_diagonal", "sky_radius", "sky_warp", "sky_contrast", "sky_intensity", "sky_rotation", "sky_pan", "palette_phase"]
const SURFACE_KEYS := ["roughness", "metallic", "normal_strength", "displacement", "domain_warp", "material_tint", "surface_opacity"]

class SurfaceBuilder:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	func vertex(p: Vector3, n: Vector3, uv: Vector2) -> void:
		positions.append(p)
		normals.append(n)
		uvs.append(uv)

	func quad(a: int, b: int, c: int, d: int) -> void:
		indices.append_array(PackedInt32Array([a, c, b, b, c, d]))

	func finish() -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		var result := ArrayMesh.new()
		if not positions.is_empty() and not indices.is_empty():
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return result

var _dataset: Dictionary = {}
var _node_by_id: Dictionary = {}
var _edge_by_id: Dictionary = {}
var _node_layer_by_index: Dictionary = {}
var _visual: Dictionary = {"node_ids": [], "edge_ids": [], "materialisation": "none", "hidden_layers": []}
var _parameters: Dictionary = DEFAULTS.duplicate(true)
var _clocks: Dictionary = {"sky": 0.0, "normal": 0.0, "displacement": 0.0, "palette": 0.0}
var _sent_surface_clocks: Dictionary = {}
var _sent_background_clocks: Dictionary = {}
var _data_generation := 0
var _signature := ""
var _surface: MeshInstance3D
var _background: MeshInstance3D
var _surface_material: ShaderMaterial
var _opaque_material: ShaderMaterial
var _translucent_material: ShaderMaterial
var _background_material: ShaderMaterial
var _palette_texture: ImageTexture
var _source_node_ids: Array[String] = []
var _source_edge_ids: Array[String] = []
var _represented_node_ids: Array[String] = []
var _represented_edge_ids: Array[String] = []
var _mesh_vertices := 0
var _mesh_triangles := 0
var _mesh_bytes := 0
var _mesh_builds := 0
var _represented_ribbons := 0
var _clock_updates := 0
var _surface_scale := 1.0
var _surface_mode := 0
var _pick_positions := PackedVector3Array()
var _pick_normals := PackedVector3Array()
var _pick_uvs := PackedVector2Array()
var _pick_indices := PackedInt32Array()
var _pick_count := 0
var _last_pick_usec := 0
var _last_pick_triangle_tests := 0

func _ready() -> void:
	_ensure_nodes()
	_apply_visibility()

func set_dataset(dataset: Dictionary) -> void:
	_dataset = dataset
	_data_generation += 1
	_node_by_id.clear()
	_edge_by_id.clear()
	_node_layer_by_index.clear()
	var node_index := 0
	for node in dataset.get("nodes", []):
		if node is Dictionary and node.has("id"):
			_node_by_id[str(node.id)] = node
			_node_layer_by_index[int(node.get("index", node_index))] = int(node.get("layer", 0))
		node_index += 1
	for edge in dataset.get("edges", []):
		if edge is Dictionary and edge.has("id"):
			_edge_by_id[str(edge.id)] = edge
	_signature = ""
	_refresh_proxy()

func set_visual_state(state: Dictionary) -> void:
	for key in ["node_ids", "edge_ids", "materialisation", "hidden_layers"]:
		if state.has(key):
			_visual[key] = state[key].duplicate() if state[key] is Array else state[key]
	_refresh_proxy()

func set_parameters(parameters: Dictionary) -> void:
	_ensure_nodes()
	for key in parameters:
		if not DEFAULTS.has(key):
			continue
		var value: Variant = parameters[key]
		if LIMITS.has(key):
			if not (value is int or value is float):
				continue
			var bounds: Vector2 = LIMITS[key]
			value = clampf(_finite(float(value), float(DEFAULTS[key])), bounds.x, bounds.y)
		elif key in ["sky_frequency", "sky_pan"]:
			if not value is Vector2:
				continue
			var vector: Vector2 = value
			var bound := 16.0 if key == "sky_frequency" else 100.0
			value = Vector2(clampf(_finite(vector.x, 1.0), -bound, bound), clampf(_finite(vector.y, 1.0), -bound, bound))
		elif key in ["enabled", "scientific", "sky_visible"]:
			value = bool(value)
		elif key == "material_tint":
			if not value is Color:
				continue
			var tint: Color = value
			value = Color(clampf(_finite(tint.r, 0.3), 0.0, 1.0), clampf(_finite(tint.g, 0.6), 0.0, 1.0), clampf(_finite(tint.b, 0.6), 0.0, 1.0), 1.0)
		elif key == "palette":
			value = str(value)
		if _parameters.get(key) == value:
			continue
		_parameters[key] = value
		if key == "palette":
			_rebuild_palette()
		elif key in SHARED_KEYS:
			_surface_material.set_shader_parameter(key, value)
			_background_material.set_shader_parameter(key, value)
		elif key in SURFACE_KEYS:
			_surface_material.set_shader_parameter(key, value)
		elif key == "background_strength":
			_background_material.set_shader_parameter(key, value)
	_apply_surface_material()
	_apply_visibility()
	update_clocks(_clocks)

func update_clocks(clocks: Dictionary) -> void:
	for key in ["sky", "normal", "displacement", "palette"]:
		if clocks.has(key):
			_clocks[key] = clampf(_finite(float(clocks[key]), 0.0), -10000000.0, 10000000.0)
	if not is_instance_valid(_surface):
		return
	# No shader uniform work while the optical layer is disabled.
	if not _surface.visible and not _background.visible:
		return
	var changed := false
	for key in ["sky", "palette"]:
		if _surface.visible:
			changed = _send_clock(_surface_material, _sent_surface_clocks, key, float(_clocks[key])) or changed
		if _background.visible:
			changed = _send_clock(_background_material, _sent_background_clocks, key, float(_clocks[key])) or changed
	if _surface.visible:
		if float(_parameters.normal_strength) > 0.0001:
			changed = _send_clock(_surface_material, _sent_surface_clocks, "normal", float(_clocks.normal)) or changed
		if float(_parameters.displacement) > 0.0001:
			changed = _send_clock(_surface_material, _sent_surface_clocks, "displacement", float(_clocks.displacement)) or changed
	if changed:
		_clock_updates += 1

func _send_clock(material: ShaderMaterial, cache: Dictionary, key: String, value: float) -> bool:
	if cache.has(key) and float(cache[key]) == value:
		return false
	material.set_shader_parameter(key + "_clock", value)
	cache[key] = value
	return true

func get_metrics() -> Dictionary:
	return {
		"optical_visible": is_instance_valid(_surface) and _surface.visible,
		"sky_visible": is_instance_valid(_background) and _background.visible,
		"proxy_kind": str(_visual.get("materialisation", "none")),
		"proxy_vertices": _mesh_vertices, "proxy_triangles": _mesh_triangles,
		"proxy_mesh_bytes_estimate": _mesh_bytes,
		"proxy_geometry_builds": _mesh_builds, "proxy_clock_updates": _clock_updates,
		"proxy_source_nodes": _source_node_ids.size(), "proxy_source_edges": _source_edge_ids.size(),
		"proxy_visible_source_nodes": _represented_node_ids.size(), "proxy_visible_source_edges": _represented_edge_ids.size(),
		"proxy_ribbons_drawn": _represented_ribbons, "proxy_ribbon_budget": MAX_RIBBONS,
		"surface_translucent": float(_parameters.surface_opacity) < 0.999,
		"proxy_pick_cpu_bytes_estimate": _mesh_bytes,
		"proxy_pick_count": _pick_count, "proxy_last_pick_usec": _last_pick_usec,
		"proxy_last_pick_triangle_tests": _last_pick_triangle_tests,
		"environment_method": "analytical reflected direction; no dynamic cubemap",
		"topology_modified": false,
	}

func get_source_membership() -> Dictionary:
	return {"node_ids": _source_node_ids.duplicate(), "edge_ids": _source_edge_ids.duplicate(), "representation": "artistic proxy", "source_revision": _dataset.get("manifest", {}).get("revision", "")}

func get_represented_membership() -> Dictionary:
	return {"node_ids": _represented_node_ids.duplicate(), "edge_ids": _represented_edge_ids.duplicate(), "representation": "visible subset of artistic proxy; source selection unchanged"}

func ray_pick_proxy(ray_origin: Vector3, ray_direction: Vector3, max_distance: float = 1000.0) -> Dictionary:
	## A hit addresses this artistic aggregate, never an invented individual source.
	## Evaluate static mesh + current bounded shader displacement only on a click.
	## CPU/GPU floating-point differences make deformed-surface picking approximate.
	if not is_instance_valid(_surface) or not _surface.is_visible_in_tree() or _surface.mesh == null:
		return {}
	if not ray_origin.is_finite() or not ray_direction.is_finite() or not is_finite(max_distance) or max_distance <= 0.0:
		return {}
	if ray_direction.length_squared() < 0.000000000001 or _pick_indices.is_empty():
		return {}
	var transform := _surface.global_transform
	if absf(transform.basis.determinant()) < 0.000000000001:
		return {}
	var started := Time.get_ticks_usec()
	_pick_count += 1
	_last_pick_triangle_tests = 0
	var inverse := transform.affine_inverse()
	var local_origin := inverse * ray_origin
	var local_direction := (inverse.basis * ray_direction.normalized()).normalized()
	var amplitude := float(_parameters.displacement) * _surface_scale * 0.34
	var bounds := _surface.mesh.get_aabb().grow(amplitude + 0.0001)
	if bounds.intersects_ray(local_origin, local_direction) == null:
		_last_pick_usec = Time.get_ticks_usec() - started
		return {}
	var positions := _pick_positions
	var deformed := float(_parameters.displacement) > 0.0001
	if deformed:
		positions = _pick_positions.duplicate()
		var scale_value := maxf(_surface_scale, 0.05)
		var k0 := Vector3(1.7, 2.3, 0.9) / scale_value
		var k1 := Vector3(-2.9, 1.4, 2.1) / scale_value
		var clock := float(_clocks.displacement)
		for i in range(positions.size()):
			var p := _pick_positions[i]
			var envelope := 1.0
			if _surface_mode == 1:
				var pin := sin(_pick_uvs[i].x * PI)
				envelope = pin * pin
			elif _surface_mode == 2:
				var pin := sin(_pick_uvs[i].x * PI) * sin(_pick_uvs[i].y * PI)
				envelope = pin * pin
			var height := 0.62 * sin(p.dot(k0) + clock * 0.81) + 0.38 * sin(p.dot(k1) - clock * 0.53)
			positions[i] = p + _pick_normals[i] * amplitude * envelope * height
	var closest := max_distance
	var world_hit := Vector3.ZERO
	var found := false
	for i in range(0, _pick_indices.size(), 3):
		_last_pick_triangle_tests += 1
		var intersection: Variant = Geometry3D.ray_intersects_triangle(local_origin, local_direction,
			positions[_pick_indices[i]], positions[_pick_indices[i + 1]], positions[_pick_indices[i + 2]])
		if intersection == null:
			continue
		var point: Vector3 = transform * Vector3(intersection)
		var distance := ray_origin.distance_to(point)
		if distance <= closest:
			closest = distance
			world_hit = point
			found = true
	_last_pick_usec = Time.get_ticks_usec() - started
	if not found:
		return {}
	return {"hit_semantics": "artistic-proxy-mesh", "selection_semantics": "retain-existing-exact-group",
		"proxy_kind": str(_visual.get("materialisation", "none")), "source_membership": get_source_membership(),
		"represented_membership": get_represented_membership(), "world_position": world_hit, "distance": closest,
		"deformation_approximate": deformed, "individual_source_item": false}

func get_parameter_schema() -> Dictionary:
	return {"defaults": DEFAULTS.duplicate(true), "limits": LIMITS.duplicate(true), "palettes": ["glacier", "ember", "pearl"]}

func _ensure_nodes() -> void:
	if is_instance_valid(_surface):
		return
	_surface_material = ShaderMaterial.new()
	_surface_material.shader = SURFACE_SHADER
	_opaque_material = _surface_material
	_background_material = ShaderMaterial.new()
	_background_material.shader = BACKGROUND_SHADER
	_background_material.render_priority = -128
	_surface = MeshInstance3D.new()
	_surface.name = "SelectedArtisticProxy"
	_surface.material_override = _surface_material
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_surface.visible = false
	add_child(_surface)
	_background = MeshInstance3D.new()
	_background.name = "AnalyticalEnvironmentBackground"
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_background.mesh = quad
	_background.material_override = _background_material
	_background.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_background.extra_cull_margin = 16384.0
	_background.ignore_occlusion_culling = true
	_background.visible = false
	add_child(_background)
	for key in SHARED_KEYS:
		_surface_material.set_shader_parameter(key, _parameters[key])
		_background_material.set_shader_parameter(key, _parameters[key])
	for key in SURFACE_KEYS:
		_surface_material.set_shader_parameter(key, _parameters[key])
	_background_material.set_shader_parameter("background_strength", _parameters.background_strength)
	_rebuild_palette()

func _apply_surface_material() -> void:
	var needs_translucency := float(_parameters.surface_opacity) < 0.999
	if needs_translucency and _translucent_material == null:
		_translucent_material = ShaderMaterial.new()
		_translucent_material.shader = TRANSLUCENT_SHADER
		# Background(-128), translucent proxy(-64), exact hairlines(0).
		_translucent_material.render_priority = -64
	var desired := _translucent_material if needs_translucency else _opaque_material
	if _surface_material == desired:
		return
	_surface_material = desired
	_surface.material_override = desired
	for key in SHARED_KEYS:
		_surface_material.set_shader_parameter(key, _parameters[key])
	for key in SURFACE_KEYS:
		_surface_material.set_shader_parameter(key, _parameters[key])
	_surface_material.set_shader_parameter("surface_mode", _surface_mode)
	_surface_material.set_shader_parameter("displacement_scale", _surface_scale)
	_surface_material.set_shader_parameter("palette_lut", _palette_texture)
	_sent_surface_clocks.clear()

func _apply_visibility() -> void:
	if not is_instance_valid(_surface):
		return
	var active := bool(_parameters.enabled) and not bool(_parameters.scientific)
	_surface.visible = active and _surface.mesh != null and _mesh_triangles > 0
	_background.visible = active and bool(_parameters.sky_visible) and float(_parameters.background_strength) > 0.0

func _refresh_proxy() -> void:
	_ensure_nodes()
	var nodes := _sorted_ids(_visual.get("node_ids", []), _node_by_id)
	var edges := _sorted_ids(_visual.get("edge_ids", []), _edge_by_id)
	var kind := str(_visual.get("materialisation", "none"))
	if kind not in ["none", "knot", "ribbon", "membrane"]:
		kind = "none"
	var hidden: Array = _visual.get("hidden_layers", []).duplicate()
	hidden.sort()
	var signature := str(_data_generation) + ":" + kind + ":" + JSON.stringify(nodes) + ":" + JSON.stringify(edges) + ":" + JSON.stringify(hidden)
	if signature == _signature:
		return
	_signature = signature
	_source_node_ids = nodes
	_source_edge_ids = edges
	_represented_node_ids.clear()
	_represented_edge_ids.clear()
	for id in nodes:
		if int(_node_by_id[id].get("layer", 0)) not in hidden:
			_represented_node_ids.append(id)
	for id in edges:
		var edge: Dictionary = _edge_by_id[id]
		var source_layer := int(_node_layer_by_index.get(int(edge.get("from_index", -1)), 0))
		var target_layer := int(_node_layer_by_index.get(int(edge.get("to_index", -1)), 0))
		if source_layer not in hidden and target_layer not in hidden:
			_represented_edge_ids.append(id)
	_surface.mesh = null
	_pick_positions = PackedVector3Array()
	_pick_normals = PackedVector3Array()
	_pick_uvs = PackedVector2Array()
	_pick_indices = PackedInt32Array()
	_mesh_vertices = 0
	_mesh_triangles = 0
	_mesh_bytes = 0
	_represented_ribbons = 0
	if kind == "none" or (_represented_node_ids.is_empty() and _represented_edge_ids.is_empty()):
		_apply_visibility()
		return
	var anchors := PackedVector3Array()
	for id in _represented_node_ids:
		anchors.append(_position(_node_by_id[id].get("position", Vector3.ZERO)))
	for id in _represented_edge_ids:
		var edge: Dictionary = _edge_by_id[id]
		anchors.append(_position(edge.get("a", Vector3.ZERO)))
		anchors.append(_position(edge.get("b", Vector3.ZERO)))
	var bounds := AABB(anchors[0], Vector3.ZERO)
	for p in anchors:
		bounds = bounds.expand(p)
	var center := bounds.get_center()
	_surface_scale = clampf(bounds.size.length() * 0.22, 0.8, 4.8)
	var builder := SurfaceBuilder.new()
	match kind:
		"knot":
			_build_knot(builder, center, _surface_scale)
			_surface_mode = 0
		"ribbon":
			_build_ribbons(builder, _represented_edge_ids, anchors, center)
			_surface_mode = 1
		"membrane":
			_build_membrane(builder, center, bounds.size)
			_surface_mode = 2
	_surface_material.set_shader_parameter("surface_mode", _surface_mode)
	_surface.mesh = builder.finish()
	# Retained bounded CPU geometry supports accurate holes/shape hit-testing on
	# demand. There is no per-frame picking mesh or deformation update.
	_pick_positions = builder.positions
	_pick_normals = builder.normals
	_pick_uvs = builder.uvs
	_pick_indices = builder.indices
	_surface.extra_cull_margin = _surface_scale
	_surface_material.set_shader_parameter("displacement_scale", _surface_scale)
	_surface.set_meta("source_membership", get_source_membership())
	_surface.set_meta("represented_membership", get_represented_membership())
	_surface.set_meta("scientific_geometry", false)
	_mesh_vertices = builder.positions.size()
	_mesh_triangles = builder.indices.size() / 3
	_mesh_bytes = builder.positions.size() * 32 + builder.indices.size() * 4
	_mesh_builds += 1
	_apply_visibility()
	update_clocks(_clocks)

func _build_knot(builder: SurfaceBuilder, center: Vector3, scale_value: float) -> void:
	const LENGTH_STEPS := 256
	const RING_STEPS := 12
	for fibre in range(3):
		var phase := TAU * float(fibre) / 3.0
		var base := builder.positions.size()
		for i in range(LENGTH_STEPS + 1):
			var u := float(i) / LENGTH_STEPS
			var t := u * TAU
			var p := _knot_path(t, phase)
			var tangent := (_knot_path(t + 0.001, phase) - _knot_path(t - 0.001, phase)).normalized()
			var normal := Vector3(cos(t * 2.0), 0.0, sin(t * 2.0))
			normal = (normal - tangent * normal.dot(tangent)).normalized()
			var binormal := tangent.cross(normal).normalized()
			var radius := 0.065 * (0.92 + 0.08 * cos(t * 7.0 + phase))
			for j in range(RING_STEPS + 1):
				var v := float(j) / RING_STEPS
				var radial := normal * cos(v * TAU) + binormal * sin(v * TAU)
				builder.vertex(center + (p + radial * radius) * scale_value, radial, Vector2(u, v))
		for i in range(LENGTH_STEPS):
			for j in range(RING_STEPS):
				var a := base + i * (RING_STEPS + 1) + j
				builder.quad(a, a + 1, a + RING_STEPS + 1, a + RING_STEPS + 2)

func _knot_path(t: float, phase: float) -> Vector3:
	var major := 1.0 + 0.34 * cos(t * 3.0)
	var p := Vector3(major * cos(t * 2.0), 0.34 * sin(t * 3.0), major * sin(t * 2.0))
	var radial := Vector3(cos(t * 2.0), 0.0, sin(t * 2.0))
	p += (radial * cos(t * 8.0 + phase) + Vector3.UP * sin(t * 8.0 + phase)) * 0.11
	return p

func _build_ribbons(builder: SurfaceBuilder, edges: Array[String], anchors: PackedVector3Array, center: Vector3) -> void:
	var pairs: Array[Vector3] = []
	if not edges.is_empty():
		var count := mini(edges.size(), MAX_RIBBONS)
		for i in range(count):
			# Deterministic even sampling; source membership still includes every ID.
			var index := mini(int(float(i) * edges.size() / count), edges.size() - 1)
			var edge: Dictionary = _edge_by_id[edges[index]]
			pairs.append(_position(edge.get("a", Vector3.ZERO)))
			pairs.append(_position(edge.get("b", Vector3.ZERO)))
	elif anchors.size() > 1:
		for i in range(mini(anchors.size() - 1, MAX_RIBBONS)):
			pairs.append(anchors[i])
			pairs.append(anchors[i + 1])
	else:
		pairs.append(center + Vector3.LEFT * _surface_scale)
		pairs.append(center + Vector3.RIGHT * _surface_scale)
	const LENGTH_STEPS := 48
	const WIDTH_STEPS := 4
	for ribbon in range(pairs.size() / 2):
		var a: Vector3 = pairs[ribbon * 2]
		var b: Vector3 = pairs[ribbon * 2 + 1]
		if a.distance_squared_to(b) < 0.000001:
			continue
		var tangent := (b - a).normalized()
		var normal := tangent.cross(Vector3.UP if absf(tangent.y) < 0.95 else Vector3.RIGHT).normalized()
		var binormal := tangent.cross(normal).normalized()
		var base := builder.positions.size()
		var phase := float(ribbon) * 2.3999632297
		var width := clampf(a.distance_to(b) * 0.008, 0.012, 0.09)
		for i in range(LENGTH_STEPS + 1):
			var u := float(i) / LENGTH_STEPS
			var envelope := sin(u * PI)
			var twist := u * TAU * 1.5 + phase
			var axis := normal * cos(twist) + binormal * sin(twist)
			var n := tangent.cross(axis).normalized()
			var p := a.lerp(b, u) + normal * envelope * sin(u * TAU + phase) * _surface_scale * 0.055
			for j in range(WIDTH_STEPS + 1):
				var v := float(j) / WIDTH_STEPS
				builder.vertex(p + axis * (v * 2.0 - 1.0) * width * envelope, n, Vector2(u, v))
		for i in range(LENGTH_STEPS):
			for j in range(WIDTH_STEPS):
				var index := base + i * (WIDTH_STEPS + 1) + j
				builder.quad(index, index + 1, index + WIDTH_STEPS + 1, index + WIDTH_STEPS + 2)
		_represented_ribbons += 1

func _build_membrane(builder: SurfaceBuilder, center: Vector3, extent: Vector3) -> void:
	const COLUMNS := 18
	const ROWS := 12
	const ARC_STEPS := 32
	const RADIAL_STEPS := 2
	var width := clampf(maxf(extent.x, extent.z) * 0.58, 1.5, 7.0)
	var height := clampf(extent.y * 0.55, 1.1, 5.0)
	# A delicate continuous lace: large rounded apertures leave narrow ligaments.
	# Only each inner rim varies; outer cell boundaries use one shared UV map.
	# Domain bending is smooth and static, so animation preserves connectivity.
	for column in range(COLUMNS):
		for row in range(ROWS):
			var base := builder.positions.size()
			var seed := float(column * 7 + row * 11)
			var aperture := 0.905 + 0.015 * sin(seed)
			for radial in range(RADIAL_STEPS + 1):
				var blend := float(radial) / RADIAL_STEPS
				for arc in range(ARC_STEPS + 1):
					var angle := TAU * float(arc) / ARC_STEPS
					var direction := Vector2(cos(angle), sin(angle))
					var outer := 0.5 / maxf(absf(direction.x), absf(direction.y))
					var rounded := 0.5 / pow(pow(absf(direction.x), 3.2) + pow(absf(direction.y), 3.2), 1.0 / 3.2)
					var asymmetry := 1.0 + 0.045 * sin(angle * 3.0 + seed) + 0.03 * cos(angle * 5.0 - seed * 0.71)
					var inner := minf(rounded * aperture * asymmetry, outer * 0.96)
					var local := direction * lerpf(inner, outer, blend) + Vector2(0.5, 0.5)
					var uv := Vector2((float(column) + local.x) / COLUMNS, (float(row) + local.y) / ROWS)
					var p := _membrane_domain(uv, width, height)
					var du := _membrane_domain(uv + Vector2(0.0001, 0.0), width, height) - _membrane_domain(uv - Vector2(0.0001, 0.0), width, height)
					var dv := _membrane_domain(uv + Vector2(0.0, 0.0001), width, height) - _membrane_domain(uv - Vector2(0.0, 0.0001), width, height)
					builder.vertex(center + p, du.cross(dv).normalized(), uv)
			for radial in range(RADIAL_STEPS):
				for arc in range(ARC_STEPS):
					var a := base + radial * (ARC_STEPS + 1) + arc
					builder.quad(a, a + 1, a + ARC_STEPS + 1, a + ARC_STEPS + 2)

func _membrane_domain(uv: Vector2, width: float, height: float) -> Vector3:
	var u := uv.x
	var v := uv.y
	var sx := u * 2.0 - 1.0
	var sy := v * 2.0 - 1.0
	# Curved outline and smooth uneven cell spacing remove the manufactured grid.
	var x := width * (sx * (1.0 - 0.20 * sy * sy) + 0.055 * sin(v * TAU) + 0.018 * sin(u * TAU * 2.0 + v * 3.1) + 0.012 * sin(v * TAU * 6.0 + u * 2.1))
	var y := height * (sy * (0.94 + 0.06 * cos(u * TAU)) + 0.10 * sin(u * TAU + 0.4) + 0.018 * sin(v * TAU * 2.0 - u * 2.7) + 0.012 * sin(u * TAU * 9.0 + v * 2.3))
	var z := _surface_scale * (0.27 * sin(u * TAU * 1.25) * sin(v * PI) + 0.12 * cos(v * TAU * 1.5) + 0.16 * sx * sy)
	return Vector3(x, y, z)

func _rebuild_palette() -> void:
	var stops: Array[Color]
	match str(_parameters.palette):
		"ember":
			stops = [Color("091322"), Color("315a78"), Color("e66634"), Color("ffe4a9"), Color("e34262"), Color("522859"), Color("091322")]
		"pearl":
			stops = [Color("081c2a"), Color("446d86"), Color("d5eeee"), Color("fff2d1"), Color("bd8d98"), Color("3d394d"), Color("081c2a")]
		_:
			stops = [Color("051c32"), Color("17688c"), Color("53d8e6"), Color("f0e9d6"), Color("e85f54"), Color("612950"), Color("051c32")]
	var image := Image.create(256, 1, false, Image.FORMAT_RGB8)
	for i in range(256):
		var coordinate := float(i) / 256.0 * float(stops.size() - 1)
		var index := mini(int(coordinate), stops.size() - 2)
		var blend := smoothstep(0.0, 1.0, coordinate - float(index))
		image.set_pixel(i, 0, stops[index].lerp(stops[index + 1], blend))
	_palette_texture = ImageTexture.create_from_image(image)
	_surface_material.set_shader_parameter("palette_lut", _palette_texture)
	_background_material.set_shader_parameter("palette_lut", _palette_texture)

func _sorted_ids(values: Variant, registry: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	var seen: Dictionary = {}
	if values is Array or values is PackedStringArray:
		for value in values:
			var id := str(value)
			if registry.has(id) and not seen.has(id):
				seen[id] = true
				ids.append(id)
	ids.sort()
	return ids

func _position(value: Variant) -> Vector3:
	if value is Vector3:
		var vector: Vector3 = value
		return Vector3(_finite(vector.x, 0.0), _finite(vector.y, 0.0), _finite(vector.z, 0.0))
	if value is Array and value.size() >= 3:
		return Vector3(_finite(float(value[0]), 0.0), _finite(float(value[1]), 0.0), _finite(float(value[2]), 0.0))
	return Vector3.ZERO

func _finite(value: float, fallback: float) -> float:
	return fallback if is_nan(value) or is_inf(value) else value
