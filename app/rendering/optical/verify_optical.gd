extends SceneTree
## Headless structural qualification only; this does not qualify rendered appearance.

const Optical := preload("res://rendering/optical/optical_layer.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var layer := Optical.new()
	root.add_child(layer)
	var source := {
		"manifest": {"source_id": "optical-fixture", "revision": "r1", "coordinate_mapping": "artistic"},
		"nodes": [
			{"id": "n:a", "index": 0, "layer": 0, "position": Vector3(-3.0, -1.0, 0.0)},
			{"id": "n:b", "index": 1, "layer": 1, "position": Vector3(3.0, 1.0, 0.0)},
		],
		"edges": [{"id": "e:ab", "index": 0, "from_index": 0, "to_index": 1, "a": Vector3(-3.0, -1.0, 0.0), "b": Vector3(3.0, 1.0, 0.0), "weight": 0.5}],
	}
	var source_before := var_to_bytes(source)
	layer.set_dataset(source)
	var expected: Dictionary = {}
	for kind in ["knot", "ribbon", "membrane", "none", "knot"]:
		layer.set_visual_state({"node_ids": ["n:a", "n:b"], "edge_ids": ["e:ab"], "materialisation": kind})
		var membership := layer.get_source_membership()
		if expected.is_empty():
			expected = membership
		_check(membership == expected, "membership stable through " + kind)
		_check(var_to_bytes(source) == source_before, "source immutable through " + kind)
		var metrics := layer.get_metrics()
		_check(int(metrics.proxy_triangles) > 0 if kind != "none" else int(metrics.proxy_triangles) == 0, "geometry appropriate for " + kind)
		var surface: MeshInstance3D = layer.get_node("SelectedArtisticProxy")
		if surface.mesh != null and surface.mesh.get_surface_count() > 0:
			var vertices: PackedVector3Array = surface.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var finite := true
			for p in vertices:
				finite = finite and p.is_finite()
			_check(finite, "finite vertices for " + kind)
	# Picking addresses the visible artistic group, including true membrane holes.
	layer.set_parameters({"displacement": 0.0})
	var pick_surface: MeshInstance3D = layer.get_node("SelectedArtisticProxy")
	var pick_arrays: Array = pick_surface.mesh.surface_get_arrays(0)
	var pick_vertices: PackedVector3Array = pick_arrays[Mesh.ARRAY_VERTEX]
	var pick_indices: PackedInt32Array = pick_arrays[Mesh.ARRAY_INDEX]
	var ta := pick_vertices[pick_indices[0]]
	var tb := pick_vertices[pick_indices[1]]
	var tc := pick_vertices[pick_indices[2]]
	var triangle_center := (ta + tb + tc) / 3.0
	var triangle_normal := (tb - ta).cross(tc - ta).normalized()
	var pick_builds := int(layer.get_metrics().proxy_geometry_builds)
	var picked := layer.ray_pick_proxy(triangle_center + triangle_normal * 4.0, -triangle_normal)
	_check(not picked.is_empty(), "ray hits actual knot triangle")
	if not picked.is_empty():
		_check(picked.source_membership == expected and not bool(picked.individual_source_item), "proxy hit retains group identity without inventing a source item")
		_check(picked.world_position.is_finite() and is_finite(float(picked.distance)), "proxy hit reports finite position and distance")
	_check(int(layer.get_metrics().proxy_geometry_builds) == pick_builds, "ray picking does not rebuild geometry")
	_check(layer.ray_pick_proxy(Vector3(500.0, 500.0, 500.0), Vector3.RIGHT).is_empty(), "off-proxy ray misses")
	_check(layer.ray_pick_proxy(Vector3.ZERO, Vector3.ZERO).is_empty(), "zero-length ray is rejected")
	layer.set_parameters({"scientific": true})
	_check(layer.ray_pick_proxy(triangle_center + triangle_normal * 4.0, -triangle_normal).is_empty(), "scientific mode has no proxy hit")
	layer.set_parameters({"scientific": false})
	layer.set_visual_state({"materialisation": "membrane"})
	var lace_arrays: Array = pick_surface.mesh.surface_get_arrays(0)
	var lace_vertices: PackedVector3Array = lace_arrays[Mesh.ARRAY_VERTEX]
	var lace_normals: PackedVector3Array = lace_arrays[Mesh.ARRAY_NORMAL]
	var aperture_center := Vector3.ZERO
	var aperture_normal := Vector3.ZERO
	for i in range(32):
		aperture_center += lace_vertices[i] / 32.0
		aperture_normal += lace_normals[i]
	aperture_normal = aperture_normal.normalized()
	_check(layer.ray_pick_proxy(aperture_center + aperture_normal * 4.0, -aperture_normal).is_empty(), "ray through membrane aperture does not hit proxy bounds")
	var lace_indices: PackedInt32Array = lace_arrays[Mesh.ARRAY_INDEX]
	var lace_uvs: PackedVector2Array = lace_arrays[Mesh.ARRAY_TEX_UV]
	var material_fraction := 0.0
	for i in range(0, lace_indices.size(), 3):
		var ua := lace_uvs[lace_indices[i]]
		var ub := lace_uvs[lace_indices[i + 1]]
		var uc := lace_uvs[lace_indices[i + 2]]
		material_fraction += absf((ub - ua).cross(uc - ua)) * 0.5
	_check(material_fraction > 0.15 and material_fraction < 0.35, "membrane remains open lace rather than a solid plate")
	var shared_uvs := {}
	var maximum_seam := 0.0
	for i in range(lace_uvs.size()):
		var key := Vector2i(roundi(lace_uvs[i].x * 1000000.0), roundi(lace_uvs[i].y * 1000000.0))
		if shared_uvs.has(key):
			maximum_seam = maxf(maximum_seam, lace_vertices[i].distance_to(shared_uvs[key]))
		else:
			shared_uvs[key] = lace_vertices[i]
	_check(maximum_seam < 0.0001, "shared membrane cell boundaries remain continuous")
	print("OPTICAL_LACE ", JSON.stringify({"apertures": 216, "material_uv_fraction": material_fraction, "maximum_shared_boundary_error": maximum_seam}))
	var la := lace_vertices[lace_indices[0]]
	var lb := lace_vertices[lace_indices[1]]
	var lc := lace_vertices[lace_indices[2]]
	var lace_center := (la + lb + lc) / 3.0
	var lace_normal := (lb - la).cross(lc - la).normalized()
	_check(not layer.ray_pick_proxy(lace_center + lace_normal * 0.25, -lace_normal).is_empty(), "ray hits delicate membrane ligament")
	layer.set_visual_state({"materialisation": "knot"})
	layer.set_parameters({"displacement": 0.12})
	layer.update_clocks({"displacement": 1.25})
	var deformed_pick := layer.ray_pick_proxy(triangle_center + triangle_normal * 4.0, -triangle_normal)
	_check(not deformed_pick.is_empty(), "ray query evaluates current displaced geometry")
	if not deformed_pick.is_empty():
		_check(bool(deformed_pick.deformation_approximate) and deformed_pick.source_membership == expected, "deformed picking reports approximation and preserves group")
	var builds := int(layer.get_metrics().proxy_geometry_builds)
	for i in range(120):
		layer.set_visual_state({"node_ids": ["n:b", "n:a"], "edge_ids": ["e:ab"], "materialisation": "knot"})
		layer.update_clocks({"sky": float(i) * -0.2, "normal": 0.0, "displacement": float(i) * 0.4, "palette": 0.0})
	_check(int(layer.get_metrics().proxy_geometry_builds) == builds, "animation and reorder do not rebuild geometry")
	var frozen := {"sky": -23.8, "normal": 0.0, "displacement": 47.6, "palette": 0.0}
	layer.update_clocks(frozen)
	var paused_updates := int(layer.get_metrics().proxy_clock_updates)
	for i in range(30):
		layer.update_clocks(frozen)
	_check(int(layer.get_metrics().proxy_clock_updates) == paused_updates, "paused clocks do not rewrite uniforms")
	var opacity_builds := int(layer.get_metrics().proxy_geometry_builds)
	for alpha in [0.55, 1.0, 0.3, 1.0]:
		layer.set_parameters({"surface_opacity": alpha})
		_check(layer.get_source_membership() == expected, "opacity preserves exact source membership")
	_check(int(layer.get_metrics().proxy_geometry_builds) == opacity_builds, "opacity switches do not rebuild geometry")
	layer.set_parameters({"enabled": false})
	var updates := int(layer.get_metrics().proxy_clock_updates)
	for i in range(30):
		layer.update_clocks({"sky": float(i)})
	_check(int(layer.get_metrics().proxy_clock_updates) == updates, "disabled layer does no shader clock updates")
	_check(not bool(layer.get_metrics().optical_visible) and not bool(layer.get_metrics().sky_visible), "disabled layer hides both passes")
	layer.set_parameters({"enabled": true, "scientific": true, "displacement": 1e20, "normal_strength": NAN, "sky_intensity": INF})
	_check(not bool(layer.get_metrics().optical_visible) and not bool(layer.get_metrics().sky_visible), "scientific mode hides artistic passes")
	_check(layer.get_source_membership() == expected, "scientific mode preserves membership")
	var surface_material: ShaderMaterial = layer.get_node("SelectedArtisticProxy").material_override
	_check(float(surface_material.get_shader_parameter("displacement")) == 1.0, "extreme displacement bounded")
	_check(is_finite(float(surface_material.get_shader_parameter("normal_strength"))), "NaN normal sanitized")
	layer.set_parameters({"scientific": false})
	layer.set_visual_state({"hidden_layers": [0]})
	_check(layer.get_source_membership() == expected, "hidden layer preserves full source selection")
	_check(layer.get_represented_membership().node_ids == ["n:b"], "hidden layer removes its node contribution")
	_check(layer.get_represented_membership().edge_ids.is_empty(), "edge touching hidden layer is not represented")
	layer.set_visual_state({"hidden_layers": [0, 1]})
	_check(not bool(layer.get_metrics().optical_visible), "hiding all selected layers hides proxy")
	layer.set_visual_state({"hidden_layers": []})
	_check(layer.get_represented_membership().edge_ids == ["e:ab"], "reveal restores represented edge")
	layer.set_dataset({"manifest": {"revision": "empty"}, "nodes": [], "edges": []})
	_check(int(layer.get_metrics().proxy_vertices) == 0, "empty replacement frees geometry")
	_check(layer.get_source_membership().node_ids.is_empty(), "empty replacement removes stale membership")
	layer.free()
	print(JSON.stringify({"suite": "optical structural invariants", "checks": checks, "failures": failures, "graphical_qualification": false}))
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)
