extends SceneTree

const Source = preload("res://core/source_model.gd")
const Selection = preload("res://core/selection_state.gd")
const Modulation = preload("res://core/modulation_bus.gd")
const Camera = preload("res://interaction/exploration_camera.gd")
const Picker = preload("res://interaction/spatial_selection.gd")
const Replay = preload("res://core/sample_replay.gd")
const SceneValidation = preload("res://core/scene_validation.gd")

var failures: Array = []
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var source := Source.new()
	var loaded: Dictionary = source.load_json("res://data/synthetic_foundry.json")
	check(loaded.get("ok", false), "Historical source loads")
	if not loaded.get("ok", false):
		finish()
		return
	var dataset: Dictionary = source.get_dataset()
	check(dataset.is_read_only() and dataset.nodes.is_read_only() and dataset.edges.is_read_only()
		and dataset.nodes[0].is_read_only() and dataset.edges[0].is_read_only() and dataset.manifest.is_read_only(),
		"Source snapshots are recursively immutable without per-frame copying")
	check(dataset.nodes.size() == 288 and dataset.edges.size() == 11520, "Historical topology has 288 nodes and 11520 exact edges")
	check(dataset.manifest.revision == "sha256:745d47fa3ebd6a91ce1c9bd11181688ce4237199bbbce11e2e330dc76d78947c", "Historical source identity equals archived specimen hash")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/synthetic_foundry.json"))
	var max_weight_error := 0.0
	for edge in dataset.edges:
		var address: PackedStringArray = edge.id.split(":")
		max_weight_error = maxf(max_weight_error, absf(float(edge.weight) - float(raw.weights[int(address[1])][int(address[2])][int(address[3])])))
	check(max_weight_error == 0.0, "Every historical coefficient maps to its exact edge address")
	var original_revision: String = dataset.manifest.revision
	var modified := raw.duplicate(true)
	modified.input[0] = float(modified.input[0]) + 0.01
	var modified_path := "user://modified-historical-schema.json"
	var modified_file := FileAccess.open(modified_path, FileAccess.WRITE)
	modified_file.store_string(JSON.stringify(modified, "", true, true))
	modified_file.close()
	var derived_source := Source.new()
	check(derived_source.load_json(modified_path).ok, "A modified historical-format specimen can be imported independently")
	check(derived_source.get_dataset().manifest.revision != original_revision
		and derived_source.get_dataset().manifest.source_kind == "synthetic-imported"
		and derived_source.get_dataset().manifest.source_id != dataset.manifest.source_id,
		"Modified historical-schema bytes cannot claim recovered-baseline provenance")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(modified_path))
	var exported := "user://core-test-source.json"
	check(source.export_json(exported) == OK, "Snapshot exports")
	var imported := Source.new()
	Source._historical_reference = {} # Exercise normalized import before any cached custody reference.
	check(imported.load_json(exported).ok, "Exported snapshot reimports with verified content hash")
	check(imported.get_dataset().manifest.revision == original_revision, "Source identity survives serialization round-trip")
	check(imported.get_dataset().manifest.historical_custody_verified,
		"Baseline snapshot custody is independently checked against the recovered specimen")
	var forged: Dictionary = dataset.duplicate(true)
	forged.edges[0].weight += 0.01
	forged.manifest.content_sha256 = Source._canonical(forged.manifest.source_id,
		forged.manifest.coordinate_mapping, forged.nodes, forged.edges).sha256_text()
	check(not source.set_validated(forged).ok and source.get_dataset().manifest.revision == original_revision,
		"A self-consistent modified snapshot cannot forge the reserved baseline revision")
	check(not imported.import_historical(modified, Source.HISTORICAL_SPECIMEN_SHA256).ok,
		"Caller-supplied raw hashes cannot confer recovered custody on modified source values")
	var reprojected: Dictionary = dataset.duplicate(true)
	reprojected.manifest.erase("content_sha256")
	reprojected.nodes[0].position += Vector3.ONE
	check(imported.set_validated(reprojected).ok and imported.get_dataset().manifest.revision == original_revision
		and imported.get_dataset().manifest.historical_custody_verified
		and imported.get_dataset().manifest.projection_revision != dataset.manifest.projection_revision,
		"Verified historical science retains custody across explicitly separate artistic projections")
	var malformed := {"schema": "xenovection.source.v1", "manifest": {"source_id": "bad"},
		"nodes": [{"id": "a", "position": [0, 0, 0]}],
		"edges": [{"id": "broken", "from_index": 0, "to_index": 9, "weight": 1.0}]}
	check(not source.set_validated(malformed).ok, "Dangling source edges are refused")
	check(source.get_dataset().manifest.revision == original_revision, "Rejected source leaves live dataset intact")
	malformed.edges = []
	malformed.nodes[0].value = NAN
	check(not source.set_validated(malformed).ok, "NaN numerical input is refused")
	malformed.nodes[0].value = 0.0
	malformed.nodes.append(malformed.nodes[0].duplicate(true))
	check(not source.set_validated(malformed).ok, "Duplicate source IDs are refused")
	check(not source.set_validated({"schema": "future.v99", "manifest": {}}).ok, "Unknown adapter schemas are refused")
	var empty := Source.new()
	check(empty.set_validated({"schema": "xenovection.source.v1", "manifest": {"source_id": "empty"}, "nodes": [], "edges": []}).ok, "Empty datasets are valid")
	check(not empty.set_validated({"manifest": {"source_id": "unversioned"}, "nodes": [], "edges": []}).ok, "Unversioned source adapters are refused")
	var first := Source.new()
	var second := Source.new()
	first.generate_synthetic(16)
	second.generate_synthetic(16)
	check(first.get_dataset().manifest.revision == second.get_dataset().manifest.revision, "New synthetic generation is deterministic")
	var projected: Dictionary = first.get_dataset().duplicate(true)
	projected.manifest.erase("content_sha256")
	projected.nodes[0].position += Vector3.ONE
	second.set_validated(projected)
	check(first.get_dataset().manifest.revision == second.get_dataset().manifest.revision, "Artistic positions do not mutate scientific source identity")
	check(first.get_dataset().manifest.projection_revision != second.get_dataset().manifest.projection_revision, "Projection changes have their own revision")
	var flow := Source.new()
	var flow_repeat := Source.new()
	check(flow.generate_spatial_flow().ok and flow_repeat.generate_spatial_flow().ok,
		"General spatial-flow adapter generates through the same versioned source contract")
	var flow_data: Dictionary = flow.get_dataset()
	check(flow_data.nodes.size() == 4608 and flow_data.edges.size() == 6144
		and flow_data.manifest.revision == flow_repeat.get_dataset().manifest.revision
		and flow_data.manifest.projection_revision == flow_repeat.get_dataset().manifest.projection_revision,
		"Spatial flow has deterministic stable IDs, 4608 source nodes and 6144 exact edges")
	var flow_valid: bool = flow_data.manifest.source_kind == "synthetic-spatial" and not flow_data.manifest.historical_custody_verified
	var along_count := 0
	var coupling_count := 0
	var layers: Dictionary = {}
	for node in flow_data.nodes:
		flow_valid = flow_valid and node.position.is_finite() and node.position.length() < 7.0 \
			and absf(node.value) <= 0.85 and node.value_kind == "derived" and node.units == "synthetic_field"
		layers[node.layer] = true
	for edge in flow_data.edges:
		flow_valid = flow_valid and is_finite(edge.weight) and absf(edge.weight) <= 0.7 and edge.value_kind == "derived"
		along_count += 1 if edge.relation == "streamline_step" else 0
		coupling_count += 1 if edge.relation == "neighbour_coupling" else 0
	check(flow_valid and layers.size() == 8 and along_count == 4608 and coupling_count == 1536,
		"Spatial source coordinates and values are finite/bounded with explicit synthetic relations and eight layers")
	var flow_path := "user://core-spatial-flow.json"
	check(flow.export_json(flow_path) == OK and flow_repeat.load_json(flow_path).ok
		and flow_repeat.get_dataset().manifest.revision == flow_data.manifest.revision
		and flow_repeat.get_dataset().edges[0].relation == "streamline_step",
		"Spatial source export preserves exact identity and typed connection semantics")
	forged = flow_data.duplicate(true)
	forged.manifest.source_id = Source.HISTORICAL_SOURCE_ID
	forged.manifest.revision = original_revision
	forged.manifest.content_sha256 = Source._canonical(forged.manifest.source_id,
		forged.manifest.coordinate_mapping, forged.nodes, forged.edges).sha256_text()
	check(not source.set_validated(forged).ok,
		"A general source cannot self-claim recovered ID and revision even with its own valid content hash")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(flow_path))
	var selection := Selection.new()
	selection.bind_dataset(dataset)
	selection.select_band(2, 0, 8)
	var reference: Dictionary = selection.get_reference()
	check(reference.node_ids.size() == 16 and reference.edge_ids.size() == 64, "Region selection enumerates exactly two node bands and their induced edges")
	for index in range(100):
		selection.set_materialisation(["knot", "ribbon", "membrane", "none"][index % 4])
		selection.set_isolated(index % 2 == 0)
	check(selection.get_reference() == reference, "Repeated materialisation and isolation preserve exact source selection")
	selection.set_materialisation("knot")
	selection.undo()
	selection.redo()
	check(selection.get_visual_state().materialisation == "knot", "Graphics undo/redo restores the visual operation")
	check(selection.get_history_counts().x <= 48, "Graphics history remains bounded")
	check(source.get_dataset().manifest.revision == original_revision, "Visual history never changes source revision")
	selection.select_edge("e:2:17:9")
	check(selection.get_reference().edge_ids == ["e:2:17:9"] and selection.get_reference().node_ids.is_empty(), "Exact edge selection does not silently expand to adjacency")
	selection.bind_dataset(first.get_dataset())
	check(selection.get_reference().node_ids.is_empty() and selection.get_reference().edge_ids.is_empty(), "New source revision clears stale selections")
	_check_reused_upstream_revision()
	var bus := Modulation.new()
	check(bus.register_target("gain", 2.0, 0.0, 10.0), "Scalar modulation target registers")
	check(bus.register_target("vector", Vector3.ONE, -3.0, 3.0), "Vector modulation target registers")
	check(bus.register_target("colour", Color(0.3, 0.4, 0.5, 1.0), 0.0, 1.0), "Colour modulation target registers")
	bus.register_source("shared", {"type": "lfo", "clock": "filament", "frequency": 1.0, "phase": 0.25})
	check(bus.add_route({"id": "a", "source": "shared", "target": "gain", "amplitude": 0.5}), "Reusable named oscillator route registers")
	check(bus.add_route({"id": "v", "source": "shared", "target": "vector", "amplitude": Vector3(0.1, 0.2, 0.3)}), "Scalar oscillator has typed vector amplitude")
	check(bus.add_route({"id": "c", "source": "shared", "target": "colour", "amplitude": Color(0.1, 0.05, 0.02, 0.0)}), "Scalar oscillator has typed colour amplitude")
	var values: Dictionary = bus.evaluate()
	check(is_equal_approx(values.gain, 2.5) and bus.get_base("gain") == 2.0, "Transient modulation leaves stored base unchanged")
	check(values.vector.is_equal_approx(Vector3(1.1, 1.2, 1.3)), "Vector modulation preserves component dimensions")
	check(is_equal_approx(values.colour.r, 0.4) and is_equal_approx(values.colour.a, 1.0), "Colour modulation leaves unmodulated alpha unchanged")
	bus.set_clock("sky", {"paused": true})
	bus.advance(0.25)
	check(is_equal_approx(bus.get_clocks().filament, 0.25) and bus.get_clocks().sky == 0.0, "Visual clocks pause independently")
	bus.set_clock("filament", {"rate": -1.0})
	bus.advance(0.25)
	check(is_equal_approx(bus.get_clocks().filament, 0.0), "Clock reversal returns through the same phase")
	bus.paused = true
	bus.advance(0.25)
	check(bus.get_clocks().filament == 0.0, "Global pause freezes clock time")
	check(not bus.add_route({"target": "gain", "offset": Color.RED}), "Incompatible typed route is refused")
	check(not bus.set_base("gain", NAN), "Non-finite base is refused")
	check(not bus.add_route({"target": "missing"}), "Unknown modulation target is refused")
	check(not bus.register_target("invalid", 0.0, 2.0, 1.0), "Reversed parameter bounds are refused")
	bus.clear_routes()
	bus.register_source("huge", {"type": "manual", "value": 1.0e308})
	bus.add_route({"target": "gain", "source": "huge", "amplitude": 1.0e308})
	check(is_finite(float(bus.evaluate().gain)), "Extreme finite modulation cannot produce NaN/Inf in renderer parameters")
	bus.clear_routes()
	bus.add_route({"id": "smooth", "target": "gain", "frequency": 0.7, "amplitude": 1.0, "smoothing": 0.2})
	bus.paused = false
	bus.reset()
	bus.set_clock("filament", {"rate": 1.0})
	for step in range(120):
		bus.advance(1.0 / 60.0)
	var expected: float = bus.get_parameters().gain
	bus.reset()
	for step in range(120):
		bus.advance(1.0 / 60.0)
	check(is_equal_approx(bus.get_parameters().gain, expected), "Fixed-step modulation replay is deterministic including smoothing")
	var camera := Camera.new()
	root.add_child(camera)
	camera.set_pose({"pivot": Vector3.ZERO, "distance": 17.0, "yaw": 0.32, "pitch": 0.18})
	var before := camera.global_transform
	camera.call("_begin_fly")
	camera.call("_end_fly")
	check(camera.global_transform.is_equal_approx(before), "Fly capture/release does not jump camera pose")
	var screen: Vector2 = camera.unproject_position(dataset.nodes[0].position)
	var picked: Dictionary = Picker.pick(camera, dataset, screen)
	check(picked.kind == "node" and picked.id == dataset.nodes[0].id, "Screen-space source picking round-trips an exact node ID")
	var boxed: Dictionary = Picker.box(camera, dataset, Rect2(-100000, -100000, 200000, 200000))
	check(boxed.node_ids.size() == 288 and boxed.edge_ids.size() == 11520, "Through-depth box has explicit induced-edge semantics")
	camera.free()
	var replay := Replay.new()
	check(replay.generate_synthetic(dataset), "Versioned synthetic sample replay binds to exact source revision")
	replay.advance(0.0)
	var zero: Dictionary = replay.get_latest("node", "n:0:0").duplicate()
	replay.advance(10.25)
	check(replay.get_metrics().coalesced_samples > 0, "Large replay time jumps coalesce a bounded backlog")
	check(replay.get_latest("node", "n:0:0").time <= 10.25 and replay.get_latest("node", "n:0:0").time > 10.2, "Coalescing keeps latest per-stream sample")
	replay.advance(0.0)
	check(replay.get_latest("node", "n:0:0") == zero, "Reversed replay seeks deterministically")
	replay.advance(-0.1)
	check(replay.get_latest("node", "n:0:0").time > 11.8, "Negative replay time wraps backwards instead of freezing at zero")
	check(source.get_dataset().manifest.revision == original_revision, "Sample replay is an overlay and never changes scientific source")
	check(not replay.set_validated({"schema": "xenovection.samples.v1", "source_id": dataset.manifest.source_id,
		"source_revision": "wrong", "samples": []}, dataset), "Replay rejects a mismatched source revision")
	check(not replay.set_validated({"schema": "xenovection.samples.v1", "source_id": dataset.manifest.source_id,
		"source_revision": original_revision, "samples": [{"time": 0, "value": 1, "id": "absent", "kind": "node", "value_kind": "derived"}]}, dataset), "Replay rejects stale source item IDs")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(exported))
	finish()


func _check_reused_upstream_revision() -> void:
	var source := Source.new()
	var replacement := Source.new()
	source.set_validated({"schema": Source.SCHEMA, "manifest": {"source_id": "declared-upstream-rebind"},
		"nodes": [{"id": "old", "position": [-1, 0, 0]}, {"id": "keep-a", "position": [0, 0, 0]},
			{"id": "keep-b", "position": [1, 0, 0]}],
		"edges": [{"id": "deleted-edge", "from_index": 0, "to_index": 1},
			{"id": "stable-edge", "from_index": 1, "to_index": 2}]})
	var original: Dictionary = source.get_dataset()
	var selection := Selection.new()
	selection.bind_dataset(original)
	selection.select(["keep-a"], ["stable-edge"])
	selection.select(["old", "keep-a"], ["deleted-edge", "stable-edge"])
	selection.set_materialisation("knot")
	selection.set_materialisation("ribbon")
	selection.undo() # Stale IDs now occur in current state and both history stacks.
	replacement.set_validated({"schema": Source.SCHEMA, "manifest": {"source_id": "declared-upstream-rebind"},
		"nodes": [{"id": "keep-b", "position": [2, 0, 0]}, {"id": "keep-a", "position": [0, 1, 0]},
			{"id": "replacement", "position": [0, 0, 2]}],
		"edges": [{"id": "stable-edge", "from_index": 1, "to_index": 0},
			{"id": "new-edge", "from_index": 2, "to_index": 0}]})
	var input: Dictionary = replacement.get_dataset().duplicate(true)
	input.manifest.revision = original.manifest.revision
	check(source.set_validated(input).ok and source.get_dataset().manifest.revision == original.manifest.revision,
		"A valid ordinary snapshot may retain its declared upstream revision after changed content")
	selection.bind_dataset(source.get_dataset())
	var retained: Dictionary = selection.get_reference()
	var points: PackedVector3Array = selection.get_selected_points()
	check(retained.node_ids == ["keep-a"] and retained.edge_ids == ["stable-edge"]
		and points.size() == 2 and Vector3(2, 0, 0) in points and Vector3(0, 1, 0) in points,
		"Same-revision rebind prunes removed node/edge IDs and resolves retained IDs through reordered indices")
	var history_valid := true
	for action in ["undo", "redo"]:
		while selection.call(action):
			var reference: Dictionary = selection.get_reference()
			for id in reference.node_ids:
				history_valid = history_valid and not source.get_node(id).is_empty()
			for id in reference.edge_ids:
				history_valid = history_valid and not source.get_edge(id).is_empty()
			for point in selection.get_selected_points():
				history_valid = history_valid and point.is_finite()
	check(history_valid and selection.get_reference().node_ids == retained.node_ids
		and selection.get_reference().edge_ids == retained.edge_ids,
		"Undo/redo after reused-revision rebind cannot revive deleted source membership")
	var saved := {"schema": SceneValidation.SCHEMA, "source_id": original.manifest.source_id,
		"source_revision": original.manifest.revision, "source_projection_revision": original.manifest.projection_revision}
	var refused: Dictionary = SceneValidation.validate(saved, source.get_dataset(), {}, {}, {})
	check(not refused.ok and str(refused.error).contains("projection"),
		"Scene recall rejects the changed snapshot before stale IDs can be restored despite a reused upstream revision")
	var old_projection: String = source.get_dataset().manifest.projection_revision
	var history_before: Vector2i = selection.get_history_counts()
	input = source.get_dataset().duplicate(true)
	input.nodes[1].position = Vector3(4, 1, 0)
	input.manifest.content_sha256 = Source._canonical(input.manifest.source_id,
		input.manifest.coordinate_mapping, input.nodes, input.edges).sha256_text()
	source.set_validated(input)
	selection.bind_dataset(source.get_dataset())
	check(selection.get_reference().node_ids == retained.node_ids and selection.get_reference().edge_ids == retained.edge_ids
		and selection.get_history_counts() == history_before and Vector3(4, 1, 0) in selection.get_selected_points()
		and source.get_dataset().manifest.projection_revision != old_projection,
		"Coordinate-only remaps preserve valid exact membership/history while selected points follow the new mapping")
	selection.select_node("replacement")
	selection.set_materialisation("knot")
	selection.set_isolated(true)
	input = source.get_dataset().duplicate(true)
	input.nodes.pop_back()
	input.edges = [input.edges[0]]
	input.manifest.content_sha256 = Source._canonical(input.manifest.source_id,
		input.manifest.coordinate_mapping, input.nodes, input.edges).sha256_text()
	source.set_validated(input)
	selection.bind_dataset(source.get_dataset())
	var empty_state: Dictionary = selection.get_visual_state()
	check(empty_state.node_ids.is_empty() and empty_state.edge_ids.is_empty()
		and empty_state.materialisation == "none" and empty_state.isolate and selection.get_selected_points().is_empty(),
		"Deleting the entire selected region removes its proxy and keeps intentional empty isolation without invalid point access")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("FAIL: " + label)


func finish() -> void:
	print(JSON.stringify({"suite": "core-source-selection-modulation-camera", "checks": checks,
		"passed": checks - failures.size(), "failed": failures.size(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
