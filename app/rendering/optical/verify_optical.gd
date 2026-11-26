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
