extends SceneTree

const Source = preload("res://core/source_model.gd")
const Selection = preload("res://core/selection_state.gd")
const Modulation = preload("res://core/modulation_bus.gd")
const Camera = preload("res://interaction/exploration_camera.gd")
const Picker = preload("res://interaction/spatial_selection.gd")
const Replay = preload("res://core/sample_replay.gd")

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
	check(imported.load_json(exported).ok, "Exported snapshot reimports with verified content hash")
	check(imported.get_dataset().manifest.revision == original_revision, "Source identity survives serialization round-trip")
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


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("FAIL: " + label)


func finish() -> void:
	print(JSON.stringify({"suite": "core-source-selection-modulation-camera", "checks": checks,
		"passed": checks - failures.size(), "failed": failures.size(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
