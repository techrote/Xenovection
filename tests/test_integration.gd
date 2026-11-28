extends SceneTree
## Actual application/state-loop qualification. Headless is logic evidence only.

const Main = preload("res://main.gd")
const SceneValidation = preload("res://core/scene_validation.gd")
const Picker = preload("res://interaction/spatial_selection.gd")

var checks := 0
var failures: Array = []
var application


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	application = Main.new()
	root.add_child(application)
	application.set_process(false)
	application._process(1.0 / 60.0)
	check(application._ready_done, "The integrated application reaches ready state")
	check(application.dataset.edges.size() == 11520, "Application starts from recovered scientific source")
	var original_revision: String = application.dataset.manifest.revision
	var initial_reference: Dictionary = application.selection.get_reference()
	var before: Dictionary = application.filaments.get_metrics()
	var optical_before: Dictionary = application.optical.get_metrics()
	for frame in range(120):
		application._process(1.0 / 60.0)
	var after: Dictionary = application.filaments.get_metrics()
	check(before.instance_upload_count == after.instance_upload_count, "Integrated animation performs no per-frame instance uploads")
	check(before.mesh_build_count == after.mesh_build_count, "Integrated animation does not rebuild strand geometry")
	check(optical_before.proxy_geometry_builds == application.optical.get_metrics().proxy_geometry_builds, "Integrated optical animation does not rebuild proxy geometry")
	var base_width: float = application.bus.get_base("filament.line_width_px")
	application.handle_action("scientific")
	application._process(1.0 / 60.0)
	check(application.filaments.get_metrics().secondary_fibres == 0 and not application.optical.get_metrics().optical_visible,
		"Scientific action disables decorative fibres and the material pass")
	check(application.selection.get_reference() == initial_reference, "Scientific switching keeps exact selection provenance")
	check(application.bus.get_base("filament.line_width_px") == base_width, "Scientific overrides do not overwrite the stored artistic width")
	application.handle_action("scientific")
	application.handle_action("pause")
	var frozen: Dictionary = application.bus.get_clocks()
	for frame in range(12):
		application._process(0.1)
	check(application.bus.get_clocks() == frozen, "Pause freezes all integrated visual clocks")
	application.handle_action("pause")
	application.handle_action("reverse")
	application._process(0.1)
	check(application.bus.get_clocks().sky < frozen.sky, "Reverse acts on the shared transport")
	application.handle_action("reverse")
	for kind in ["ribbon", "membrane", "knot", "unmaterialise", "knot"]:
		application.handle_action(kind)
		application._process(0.016)
	check(application.selection.get_reference() == initial_reference, "All integrated materialisation modes preserve exact IDs")
	application.selection.set_layer_visible(2, false)
	application._process(0.016)
	check(application.filaments.get_metrics().primary_edges < 11520, "Hiding a source layer removes incident primary draws")
	check(application.optical.get_source_membership().edge_ids == initial_reference.edge_ids, "Layer visibility never loses proxy source membership")
	application.selection.set_layer_visible(3, false)
	application._process(0.016)
	check(not application.optical.get_metrics().optical_visible, "Hiding all selected contributors suppresses the optical pass")
	application.handle_action("reveal")
	application._process(0.016)
	check(application.optical.get_metrics().optical_visible and application.filaments.get_metrics().primary_edges == 11520, "Reveal restores both source and optical geometry")
	application.selection.select_edge("e:2:17:9")
	application.selection.set_isolated(true)
	application.set_parameter("filament.wave_amplitude", 0.4)
	application._process(0.016)
	var curve_point: Vector3 = application.filaments.curve_world_position("e:2:17:9", 0.5)
	var screen: Vector2 = application.camera.unproject_position(curve_point)
	var picked: Dictionary = Picker.pick(application.camera, application.dataset, screen, 3, [], application.filaments)
	check(picked.kind == "edge" and picked.id == "e:2:17:9", "An actual animated curve click returns its exact primary edge ID")
	check(picked.get("hit_semantics", "") == "rendered-primary-polyline", "Artistic curve hit testing declares its rendered-polyline basis")
	application.selection.set_isolated(false)
	application.set_parameter("filament.wave_amplitude", 2.0)
	application._process(0.016)
	var dense_pick: Dictionary = Picker.pick(application.camera, application.dataset,
		application.camera.unproject_position(Vector3.ZERO), 0.25, [], application.filaments)
	check(dense_pick.get("candidate_limit_reached", false) and int(dense_pick.get("curve_candidates", 0)) == 1024,
		"Extreme dense curve hit queries respect the candidate bound")
	check(not str(dense_pick.get("warning", "")).is_empty(), "Bounded dense picking returns an explicit nearest-hit qualification")
	application.selection.set_isolated(true)
	application.selection.clear()
	application._process(0.016)
	check(application.filaments.get_metrics().visible_strands == 0 and not application.optical.get_metrics().optical_visible,
		"Empty isolated selection submits no strands or optical geometry")
	application.handle_action("reveal")
	application.handle_action("select_region")
	application.handle_action("knot")
	application._process(0.016)
	var save_path := "user://integration-scene.json"
	application.bus.paused = true
	application.save_scene(save_path)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	var validated: Dictionary = validate_scene(saved)
	check(validated.ok, "The application saves a scene accepted by the typed validator")
	var saved_reference: Dictionary = application.selection.get_reference()
	application.set_parameter("filament.opacity", 0.02)
	application.handle_action("unmaterialise")
	check(application.load_scene(save_path), "Saved scene loads into the actual application")
	check(application.selection.get_reference().edge_ids == saved_reference.edge_ids and application.selection.get_visual_state().materialisation == "knot",
		"Scene recall restores exact region and materialisation")
	var malformed := saved.duplicate(true)
	malformed.base_parameters["optical.sky_frequency"] = {"_type": "v2", "value": "broken"}
	check(not validate_scene(malformed).ok, "Malformed encoded vector is rejected before scene mutation")
	malformed = saved.duplicate(true)
	malformed.camera.pivot = {"_type": "v3", "value": [0, 1]}
	check(not validate_scene(malformed).ok, "Malformed camera vector is rejected")
	malformed = saved.duplicate(true)
	malformed.clocks.filament.rate = "fast"
	check(not validate_scene(malformed).ok, "Non-numeric saved clock rate is rejected")
	malformed = saved.duplicate(true)
	malformed.selection.edge_ids = ["e:absent"]
	check(not validate_scene(malformed).ok, "Scene recall rejects stale exact item IDs")
	malformed = saved.duplicate(true)
	malformed.source_id = "different-source"
	check(not validate_scene(malformed).ok, "Source ID is checked independently of revision")
	malformed = saved.duplicate(true)
	malformed.source_projection_revision = "sha256:wrong-projection"
	check(not validate_scene(malformed).ok, "Saved scenes bind the exact artistic projection separately from source identity")
	malformed = saved.duplicate(true)
	malformed.preset_index = "flow"
	check(not validate_scene(malformed).ok, "Saved preset identity cannot contain a malformed string index")
	malformed = saved.duplicate(true)
	malformed.filament_flags.enabled = "false"
	check(not validate_scene(malformed).ok, "String booleans cannot silently enable renderer passes")
	malformed = saved.duplicate(true)
	malformed.filament_flags.positive_colour = {"_type": "color", "value": [1.0e308, 0, 0, 1]}
	check(not validate_scene(malformed).ok, "Finite JSON values overflowing GPU float colour precision are refused")
	malformed = saved.duplicate(true)
	malformed.base_parameters["filament.opacity"] = 0.71
	malformed.camera.pivot = {"_type": "v3", "value": "malformed"}
	var refused_path := "user://integration-refused-scene.json"
	var invalid_file := FileAccess.open(refused_path, FileAccess.WRITE)
	invalid_file.store_string(JSON.stringify(malformed))
	invalid_file.close()
	var before_refusal: Dictionary = application.selection.get_reference()
	var opacity_before: float = application.bus.get_base("filament.opacity")
	var camera_before: Transform3D = application.camera.global_transform
	check(not application.load_scene(refused_path), "Actual scene loader refuses malformed encoded values")
	check(application.bus.get_base("filament.opacity") == opacity_before
		and application.selection.get_reference() == before_refusal
		and application.camera.global_transform.is_equal_approx(camera_before),
		"Malformed scene refusal is atomic across parameters, selection and camera")
	malformed = saved.duplicate(true)
	malformed.replay_enabled = "false"
	check(not validate_scene(malformed).ok, "Saved replay enable requires a true boolean")
	malformed = saved.duplicate(true)
	malformed.erase("replay_enabled")
	check(validate_scene(malformed).scene.replay_enabled == false, "Older scene files default to disabled replay modulation")
	application.camera.call("_begin_fly")
	application.camera.call("_notification", Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not application.camera.is_navigating() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "Focus loss releases captured fly navigation")
	application.handle_action("release")
	check(not application._dragging, "Escape/release cancels active selection gesture")
	application.load_density(24)
	application._process(0.016)
	check(application.dataset.edges.size() == 2880 and application.dataset.manifest.revision != original_revision,
		"Density switch explicitly binds a distinct deterministic source")
	check(application.selection.get_reference().edge_ids.is_empty(), "Density change cannot carry stale source selection")
	check(not application.optical.get_metrics().optical_visible, "Replacing a selected materialised source removes stale proxy geometry")
	application.load_density(48)
	application._process(0.016)
	check(application.dataset.manifest.revision == original_revision, "Recovered source returns with its exact archived identity")
	var tiny_path := "user://integration-empty-source.json"
	var file := FileAccess.open(tiny_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema": "xenovection.source.v1", "manifest": {"source_id": "empty-integration"}, "nodes": [], "edges": []}))
	file.close()
	application.set_parameter("replay.enabled", true)
	application.bus.register_source("sample", {"type": "manual", "value": 0.6})
	application._import_source(tiny_path)
	application._process(0.016)
	check(application.bus.sources.sample.value == 0.0, "Empty-source import clears the previous source replay sample")
	application.handle_action("knot")
	check(application.dataset.nodes.is_empty() and not application.optical.get_metrics().optical_visible, "Empty source remains usable without phantom material geometry")
	check(not application.load_scene(save_path), "Saved scene cannot cross into a different source revision")
	application.load_density(48)
	for index in range(5):
		application.apply_preset(index)
		application._process(0.016)
		check(application.dataset.manifest.revision == original_revision, "Principal preset %d retains the archived source" % index)
	for optical_index in range(7, 13):
		application.apply_preset(optical_index)
		application._process(0.016)
		check(application.optical.get_metrics().optical_visible and application.optical.get_metrics().optical_matter_mix > 0.99, "Optical composition %d active" % optical_index)
		check(application.dataset.manifest.revision == original_revision, "Optical composition preserves source")
		check(application.bus.targets.has("optical.optical_thickness") and application.bus.targets.has("optical.refraction_strength"), "Optical typed targets registered")
	application.set_parameter("optical.optical_thickness", 0.91)
	var optical_save_path := "user://optical003-roundtrip.json"
	application.save_scene(optical_save_path)
	application.set_parameter("optical.optical_thickness", 0.12)
	check(application.load_scene(optical_save_path) and is_equal_approx(float(application.bus.get_base("optical.optical_thickness")), 0.91), "Optical authored thickness survives scene recall")
	application.apply_preset(2)
	application.set_parameter("optical.displacement", 0.0)
	application._process(0.016)
	var optical_selection: Dictionary = application.selection.get_reference()
	var proxy_surface: MeshInstance3D = application.optical.get_node("SelectedArtisticProxy")
	var proxy_arrays: Array = proxy_surface.mesh.surface_get_arrays(0)
	var proxy_vertices: PackedVector3Array = proxy_arrays[Mesh.ARRAY_VERTEX]
	var proxy_indices: PackedInt32Array = proxy_arrays[Mesh.ARRAY_INDEX]
	var proxy_point: Vector3 = proxy_surface.global_transform * ((proxy_vertices[proxy_indices[0]]
		+ proxy_vertices[proxy_indices[1]] + proxy_vertices[proxy_indices[2]]) / 3.0)
	var proxy_screen: Vector2 = application.camera.unproject_position(proxy_point)
	var proxy_hit: Dictionary = application.optical.ray_pick_proxy(application.camera.project_ray_origin(proxy_screen),
		application.camera.project_ray_normal(proxy_screen), application.camera.far)
	check(not proxy_hit.is_empty() and not proxy_hit.individual_source_item
		and proxy_hit.source_membership.node_ids == optical_selection.node_ids
		and proxy_hit.source_membership.edge_ids == optical_selection.edge_ids,
		"Optical-only click addresses its full exact group without inventing an individual source item")
	var proxy_state: Dictionary = application.selection.get_visual_state()
	var proxy_history: Vector2i = application.selection.get_history_counts()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = proxy_screen
	click.pressed = true
	application._unhandled_input(click)
	click.pressed = false
	application._input(click)
	check(application.selection.get_reference() == optical_selection
		and application.selection.get_visual_state() == proxy_state
		and application.selection.get_history_counts() == proxy_history,
		"Application proxy click retains exact group, selection origin, materialisation and graphics history")
	application.handle_action("unmaterialise")
	application._process(0.016)
	check(application.filaments.get_metrics().primary_edges > 0
		and not application.optical.get_metrics().optical_visible
		and application.selection.get_reference() == optical_selection,
		"Optical preset returns to visible fine filaments without losing its exact source selection")
	file = FileAccess.open(tiny_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema": "xenovection.source.v1", "manifest": {"source_id": "near-plane-crossing"},
		"nodes": [{"id": "behind", "position": [-0.5, 0, 1], "layer": 8}, {"id": "front", "position": [0.5, 0, -2], "layer": 9}],
		"edges": [{"id": "crossing", "from_index": 0, "to_index": 1, "weight": 0.25}]}))
	file.close()
	application._import_source(tiny_path)
	application.scientific = true
	application.camera.set_pose({"pivot": Vector3(0, 0, -0.12), "distance": 0.12, "yaw": 0.0, "pitch": 0.0})
	application.selection.select_edge("crossing")
	application.selection.set_isolated(true)
	application._process(0.016)
	var visible_point: Vector3 = application.filaments.curve_world_position("crossing", 0.75)
	var crossing_pick: Dictionary = Picker.pick(application.camera, application.dataset,
		application.camera.unproject_position(visible_point), 3, [], application.filaments)
	check(crossing_pick.kind == "edge" and crossing_pick.id == "crossing", "Extreme close-up can pick an exact segment with one endpoint behind the camera")
	var restored_state: Dictionary = application.selection.get_visual_state()
	restored_state.hidden_layers = [8]
	check(application.selection.restore_visual_state(restored_state), "Atomic visual restore accepts imported source layers beyond the founding six")
	check(application.selection.get_visual_state().hidden_layers == [8], "Layer visibility restore preserves arbitrary imported layer IDs")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tiny_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(refused_path))
	application.free()
	print(JSON.stringify({"suite": "integrated-native-application-interactions", "checks": checks,
		"passed": checks - failures.size(), "failed": failures.size(), "failures": failures,
		"evidence_kind": "actual app state/renderer invariants; headless does not qualify visuals"}))
	quit(0 if failures.is_empty() else 1)


func validate_scene(value: Dictionary) -> Dictionary:
	return SceneValidation.validate(value, application.dataset, application.bus.targets,
		Main.FilamentRenderer.DEFAULTS, Main.OpticalRenderer.DEFAULTS)


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("FAIL: " + label)
