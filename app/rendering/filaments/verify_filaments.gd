extends SceneTree
## Compact renderer invariants. This is headless logic evidence, not GPU or
## visual qualification: run graphical captures separately.

const Renderer = preload("res://rendering/filaments/filament_renderer.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)


func _run() -> void:
	var renderer = Renderer.new()
	root.add_child(renderer)
	var nodes: Array = [
		{"id": "a", "index": 0, "position": Vector3(-2, 0, 0), "layer": 0, "value": -0.3},
		{"id": "b", "index": 1, "position": Vector3(1, 2, 0), "layer": 1, "value": 0.4},
		{"id": "c", "index": 2, "position": Vector3(2, -1, 3), "layer": 1, "value": 0.1},
	]
	var edges: Array = [
		{"id": "ab", "index": 0, "from_index": 0, "to_index": 1, "a": nodes[0].position, "b": nodes[1].position, "weight": -0.7},
		{"id": "ac", "index": 1, "from_index": 0, "to_index": 2, "a": nodes[0].position, "b": nodes[2].position, "weight": 0.2},
	]
	var dataset := {"manifest": {"source_id": "renderer-invariant-fixture", "revision": "fixture-v1"}, "nodes": nodes, "edges": edges}
	renderer.set_dataset(dataset)
	check(renderer.get_metrics().primary_edges == 2, "Every exact primary edge is represented")
	check(renderer.get_metrics().secondary_fibres == 4, "Decorative fibres remain a separate pass")
	check(renderer.visible_source_edge_ids() == ["ab", "ac"], "Source edge order survives buffer packing")
	var population: MultiMesh = renderer.get_node("ExactPrimaryFilaments").multimesh
	for index in range(2):
		var transform := Renderer.edge_transform(edges[index].a, edges[index].b)
		check((transform * Vector3.ZERO).distance_to(edges[index].a) < 0.00001, "Instance %d begins at the source endpoint" % index)
		check((transform * Vector3(0, 1, 0)).distance_to(edges[index].b) < 0.00001, "Instance %d ends at the source endpoint" % index)
		var staging := PackedFloat32Array()
		staging.resize(16)
		Renderer._write_instance(staging, 0, transform, Color(0.1, -0.7, 1.0, 0.0))
		check(Vector3(staging[3], staging[7], staging[11]).distance_to(edges[index].a) < 0.00001, "Packed instance %d preserves the source origin" % index)
		check(is_equal_approx(staging[13], -0.7) and staging[14] == 1.0, "Packed instance %d preserves signed weight and selection" % index)
		# Dummy headless rendering does not retain GPU instance buffers. Check
		# actual buffer roundtrip when the same suite runs with a graphics driver.
		if DisplayServer.get_name() != "headless":
			check(population.get_instance_transform(index).is_equal_approx(transform), "GPU buffer instance %d roundtrip" % index)
	var initial_uploads: int = renderer.get_metrics().instance_upload_count
	var initial_meshes: int = renderer.get_metrics().mesh_build_count
	for frame in range(600):
		renderer.update_clocks({"filament": float(frame) * 0.016, "palette": -float(frame) * 0.011})
	check(renderer.get_metrics().instance_upload_count == initial_uploads, "600 animation frames do not upload geometry")
	check(renderer.get_metrics().mesh_build_count == initial_meshes, "600 animation frames do not rebuild the ribbon mesh")
	check(renderer.curve_world_position("ab", 0.0).distance_to(edges[0].a) < 0.00001 and renderer.curve_world_position("ab", 1.0).distance_to(edges[0].b) < 0.00001, "Picking curve retains exact source endpoints")
	var forward: Vector3 = renderer.curve_world_position("ab", 0.4)
	renderer.update_clocks({"filament": -3.5})
	check(renderer.curve_world_position("ab", 0.4).distance_to(forward) > 0.0001, "Picking curve follows the explicit reversed shader clock")
	check(renderer.curve_sample_count() == 24, "Picking samples the actual primary mesh tessellation")
	var frozen_updates: int = renderer.get_metrics().uniform_update_count
	for frame in range(20):
		renderer.update_clocks({"filament": -3.5})
	check(renderer.get_metrics().uniform_update_count == frozen_updates, "Paused clocks do not resend unchanged shader uniforms")
	renderer.set_visual_state({"node_ids": ["a", "b"], "edge_ids": ["ab"], "isolate": true})
	check(renderer.visible_source_edge_ids() == ["ab"], "Isolation uses exactly selected edges, not endpoint star expansion")
	check(renderer.source_index_for_edge("ac") == 1, "Hidden source edge identity remains addressable")
	check(renderer.source_edge_is_visible("ab") and not renderer.source_edge_is_visible("ac"), "Picker visibility follows the rendered isolated membership")
	initial_uploads = renderer.get_metrics().instance_upload_count
	for cycle in range(30):
		renderer.set_visual_state({"materialisation": "knot"})
		renderer.set_visual_state({"materialisation": "filaments"})
	check(renderer.get_metrics().instance_upload_count == initial_uploads, "Materialisation cycles do not rebuild source instances")
	check(renderer.visible_source_edge_ids() == ["ab"], "Materialisation does not change source mapping")
	renderer.set_parameters({"scientific": true})
	check(renderer.get_metrics().secondary_fibres == 0, "Scientific view fully disables the decorative draw")
	check(renderer.get_metrics().active_segments == 1 and renderer.curve_sample_count() == 1, "Scientific view uses a single exact segment per edge")
	check(renderer.curve_world_position("ab", 0.4).distance_to(edges[0].a.lerp(edges[0].b, 0.4)) < 0.00001, "Scientific picking follows the undeformed source line")
	var uniforms: int = renderer.get_metrics().uniform_update_count
	renderer.update_clocks({"filament": 4.0, "palette": 2.0})
	check(renderer.get_metrics().uniform_update_count == uniforms, "Scientific view performs no animation uniform updates")
	renderer.set_parameters({"enabled": false})
	check(renderer.get_metrics().submitted_passes == 0, "Disabled renderer submits no populated passes")
	renderer.update_clocks({"filament": 5.0})
	check(renderer.get_metrics().uniform_update_count == uniforms, "Disabled renderer performs no clock work")
	renderer.set_parameters({"enabled": true, "scientific": false, "wave_amplitude": NAN, "line_width_px": -100.0, "fibres": 999})
	check(is_finite(float(renderer.parameters.wave_amplitude)), "Nonfinite modulation cannot enter uniforms")
	check(is_equal_approx(renderer.parameters.line_width_px, 0.05) and renderer.parameters.fibres == 4, "Extreme parameters are bounded")
	renderer.set_visual_state({"isolate": true, "node_ids": [], "edge_ids": []})
	check(renderer.get_metrics().visible_strands == 0, "Isolating an empty selection produces an empty view")
	renderer.set_visual_state({"isolate": false, "hidden_layers": [1]})
	check(renderer.get_metrics().primary_edges == 0, "Hidden endpoint layers remove incident rendered edges")
	renderer.set_visual_state({"hidden_layers": []})
	dataset.edges[0].weight = 99.0
	check(renderer._dataset.edges[0].weight == -0.7, "Renderer snapshot cannot be mutated through the caller dictionary")
	renderer.set_dataset({"manifest": {"revision": "empty"}, "nodes": [], "edges": []})
	check(renderer.get_metrics().visible_strands == 0 and renderer.get_metrics().visible_nodes == 0, "Empty datasets clear all populations")
	var evidence_kind := "headless logic; not GPU/visual qualification" if DisplayServer.get_name() == "headless" else "logic and real-driver buffer roundtrip; visual capture is separate"
	print(JSON.stringify({"suite": "filament-renderer-invariants", "checks": checks, "failures": failures, "status": "PASS" if failures.is_empty() else "FAIL", "evidence_kind": evidence_kind}))
	renderer.free()
	quit(0 if failures.is_empty() else 1)
