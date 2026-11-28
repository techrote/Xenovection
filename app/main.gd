extends Node3D
## Unified instrument: source, authoring, numerical ecology and rendering have explicit owners.

const SourceModel = preload("res://core/source_model.gd")
const SelectionState = preload("res://core/selection_state.gd")
const ModulationBus = preload("res://core/modulation_bus.gd")
const SynthGraph = preload("res://core/synth_graph.gd")
const SynthPanel = preload("res://ui/synth_panel.gd")
const SynthExamples = preload("res://core/synth_examples.gd")
const SpatialSelection = preload("res://interaction/spatial_selection.gd")
const ExplorationCamera = preload("res://interaction/exploration_camera.gd")
const FilamentRenderer = preload("res://rendering/filaments/filament_renderer.gd")
const OpticalRenderer = preload("res://rendering/optical/optical_layer.gd")
const InstrumentPanel = preload("res://ui/instrument_panel.gd")
const FrameRecorder = preload("res://diagnostics/frame_recorder.gd")
const FoundryProbe = preload("res://analysis/foundry_probe.gd")
const SceneValidation = preload("res://core/scene_validation.gd")
const SampleReplay = preload("res://core/sample_replay.gd")
const Presets = preload("res://presets.gd")
const Matter = preload("res://matter/laboratory.gd")
const MatterPresets = preload("res://matter/presets.gd")
const Catalogue = preload("res://convergence/composition_catalogue.gd")
const IntegratedCompositions = preload("res://convergence/integrated_compositions.gd")
const CompositionStore = preload("res://convergence/composition_store.gd")
const InstrumentClock = preload("res://convergence/instrument_clock.gd")
const EcologyPatch = preload("res://convergence/ecology_patch.gd")
const EcologyWorkspace = preload("res://ecology/workspace.gd")
const EcologyWorld = preload("res://ecology/world.gd")
const SpatialEcology = preload("res://ecology/spatial_adapter.gd")
const LifePanel = preload("res://convergence/life_panel.gd")

var source = SourceModel.new()
var selection = SelectionState.new()
var bus = ModulationBus.new()
var synth = SynthGraph.new()
var synth_panel
var synth_error := ""
var synth_base_enabled := true
var recorder = FrameRecorder.new()
var probe = FoundryProbe.new()
var replay = SampleReplay.new()
var replay_enabled: bool = false
# Scene-owned Nodes are allocated and attached together in _ready.
var filaments
var optical
var camera
var ui
var dataset: Dictionary = {}
var presets: Array = _composition_presets()
var matter = Matter.new()
var preset_index: int = 0
var scientific: bool = false
var density: int = 48
var filament_flags: Dictionary = {}
var optical_flags: Dictionary = {}
var mod_depth: float = 1.0
var mod_frequency: float = 0.08
var mod_waveform: String = "sine"
var _dragging: bool = false
var _drag_start := Vector2.ZERO
var _drag_additive: bool = false
var _hud_elapsed: float = 0.0
var _frame: int = 0
var _args: Dictionary = {}
var _captured: bool = false
var _source_sha: String = ""
var _file_dialog: FileDialog
var _composition_dialog: FileDialog
var _composition_saving := false
var _ready_done: bool = false
var instrument_clock = InstrumentClock.new()
var ecology
var spatial_ecology
var ecology_layer: CanvasLayer
var life_panel
var workspace_mode := "instrument"
var _spatial_requested := false
var _applying_composition := false
var _startup_started := Time.get_ticks_usec()
var startup_usec := 0
var scene_prepare_usec := 0
var scene_prepare_samples: Array[int] = []
var transition_samples: Array[int] = []
var _last_effective: Dictionary = {}
var _build: Dictionary = {"source_sha": "working-tree", "status": "Draft/HOLD"}

static func _composition_presets() -> Array:
	var inherited: Array = Presets.all()
	var populations: Array = inherited.slice(0, 7) + MatterPresets.all() + inherited.slice(7)
	populations = Catalogue.decorate(populations)
	return Catalogue.decorate(populations + IntegratedCompositions.all(populations))

func _setup_ecology() -> void:
	spatial_ecology = SpatialEcology.new()
	spatial_ecology.name = "SpatialEcology"
	spatial_ecology.hide()
	add_child(spatial_ecology)
	ecology_layer = CanvasLayer.new()
	ecology_layer.layer = 12
	add_child(ecology_layer)
	ecology = EcologyWorkspace.new()
	ecology.name = "PersistentEcology"
	ecology.configure_shared(bus, _step_ecology_manual)
	ecology.hide()
	ecology.snapshot_updated.connect(_ecology_snapshot)
	ecology.return_requested.connect(func(): set_workspace("instrument"))
	ecology.spatial_requested.connect(func(): set_workspace("spatial", true))
	ecology.modulation_requested.connect(_set_ecology_lfo)
	ecology.configuration_changed.connect(_ecology_configuration_changed)
	ecology_layer.add_child(ecology)
	ecology.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var session: VBoxContainer = ui._page(ui.tabs, "Scenes")
	ui._section(session, "Whole composition", "Save source identity, matter, optics, graph and initial ecology together. Saves preserve authored state; numerical histories restart on recall.")
	ui._button(session, "Save composition [F5]", "save_scene")
	ui._button(session, "Recall composition [F6]", "load_scene")
	ui._button(session, "Save composition as…", "save_scene_as")
	ui._button(session, "Open composition…", "open_scene")
	ui._button(session, "Recover previous composition save", "recover_scene")
	ui._section(session, "Authoring scopes", "Ctrl+Z uses Synth graph history in Synth, region history in Matter, and exact source selection history elsewhere. Ecology Reset and recall restore initial conditions; they do not reverse numerical history.")
	ui._section(session, "Workspace keys", "F2 Matter · F3 Optics · F4 Life · F7 Synth. Scientific [G] isolates the original source. Planar Life [Escape] returns without resetting its organisms.")
	life_panel = LifePanel.new()
	ui._page(ui.tabs, "Life").add_child(life_panel)
	life_panel.setup(self)

func _ecology_boundary(values: Dictionary, force: bool = false) -> void:
	if is_instance_valid(ecology):
		ecology.step_resolved(values, force)

func _step_ecology_manual() -> void:
	if scientific:
		return
	instrument_clock.step_ecology(bus, synth, _ecology_boundary, false)

func _ecology_snapshot(snapshot: Dictionary) -> void:
	if _spatial_requested and is_instance_valid(spatial_ecology):
		spatial_ecology.apply_snapshot(snapshot)

func _ecology_configuration_changed() -> void:
	if _applying_composition:
		return
	_set_ecology_lfo(bool(ecology.world.config.get("lfo", false)))
	if is_instance_valid(life_panel): life_panel.refresh()

func _set_ecology_lfo(enabled: bool) -> void:
	# The familiar ecology toggle authors ordinary visible shared-graph routes.
	# It never installs hidden routes in a second bus.
	if not enabled and not synth.nodes.has(EcologyPatch.SOURCE):
		return
	var candidate := EcologyPatch.with_lfo(synth.snapshot(bus) if not synth.patch.is_empty() else {}, preset_index, presets[preset_index].stable_id, enabled)
	if not candidate.ok or not install_synth_patch(candidate.get("patch", {})):
		ecology.world.config.lfo = synth.nodes.has(EcologyPatch.SOURCE)
		ecology._sync_controls()
		ui.show_message("Ecology modulation refused: " + str(candidate.get("error", synth_error)), 8)

func set_ecology_enabled(enabled: bool) -> void:
	if enabled: scientific = false
	ecology.simulation_enabled = enabled
	if enabled:
		_spatial_requested = true
		spatial_ecology.apply_snapshot(ecology.latest_snapshot)
	else:
		spatial_ecology.clear_organisms()
	_refresh_target_availability()
	if is_instance_valid(life_panel): life_panel.refresh()
	if is_instance_valid(synth_panel): synth_panel.refresh()
	ui.set_transport(scientific, bus.paused)

func set_workspace(mode: String, frame_domain: bool = false, enable_ecology: bool = true) -> void:
	if not mode in ["instrument", "planar", "spatial"] or not is_instance_valid(ecology):
		return
	var started := Time.get_ticks_usec()
	workspace_mode = mode
	_dragging = false
	camera.release_pointer()
	ui.show_selection_box(Rect2(), false)
	if mode != "instrument" and enable_ecology:
		scientific = false
		ecology.simulation_enabled = true
	if mode == "spatial":
		_spatial_requested = true
		if not ecology.latest_snapshot.is_empty(): spatial_ecology.apply_snapshot(ecology.latest_snapshot)
	ecology.visible = mode == "planar"
	ui.visible = mode != "planar"
	camera.navigation_enabled = mode != "planar"
	filaments.visible = mode != "planar"
	optical.visible = mode != "planar"
	spatial_ecology.visible = _spatial_requested and ecology.simulation_enabled and mode != "planar" and not scientific
	if mode == "planar":
		matter.hide()
	else:
		_frame_canvas()
	if frame_domain:
		camera.focus_points(PackedVector3Array([Vector3(-6, -6, -1), Vector3(6, 6, 1)]))
		ui.rail.show()
		ui.set_tab(ui.tabs.get_node("Life").get_index())
	_refresh_target_availability()
	transition_samples.append(Time.get_ticks_usec() - started)
	if transition_samples.size() > 128: transition_samples.pop_front()
	if is_instance_valid(life_panel): life_panel.refresh()
	ui.set_transport(scientific, bus.paused)

func _refresh_target_availability() -> void:
	bus.set_namespace_available("matter.", matter.active and not scientific)
	bus.set_namespace_available("eco.", is_instance_valid(ecology) and ecology.simulation_enabled and not scientific)
	bus.set_namespace_available("optical.", bool(optical_flags.get("enabled", true)) and not scientific)

static func _timing_summary(values: Array[int]) -> Dictionary:
	var ordered: Array[int] = values.duplicate()
	ordered.sort()
	return {"samples": ordered.size(), "p50_usec": ordered[int((ordered.size() - 1) * 0.5)] if not ordered.is_empty() else 0,
		"p95_usec": ordered[int((ordered.size() - 1) * 0.95)] if not ordered.is_empty() else 0}

func _ready() -> void:
	_args = _read_arguments()
	filaments = FilamentRenderer.new()
	optical = OpticalRenderer.new()
	camera = ExplorationCamera.new()
	ui = InstrumentPanel.new()
	_load_build_info()
	_setup_world()
	add_child(filaments)
	add_child(optical)
	add_child(matter)
	add_child(camera)
	camera.current = true
	add_child(ui)
	_setup_ecology()
	camera.navigation_changed.connect(_frame_canvas)
	get_viewport().size_changed.connect(_frame_canvas)
	ui.set_presets(presets)
	ui.action_requested.connect(handle_action)
	ui.parameter_changed.connect(set_parameter)
	ui.preset_selected.connect(apply_preset)
	ui.clock_changed.connect(func(clock: String, setting: Dictionary): bus.set_clock(clock, setting))
	selection.changed.connect(_selection_changed)
	probe.load_specimen("res://data/synthetic_foundry.json")
	for index in range(presets.size()):
		if str(_args.get("preset", "hybrid")) in [presets[index].id, presets[index].stable_id]:
			preset_index = index
	apply_preset(preset_index)
	synth_panel = SynthPanel.new()
	ui._page(ui.tabs, "Synth").add_child(synth_panel)
	synth_panel.setup(self)
	if _args.has("patch-example"):
		var index := int(_args["patch-example"]) - 1
		var examples := SynthExamples.all()
		if index < 0 or index >= examples.size() or not install_synth_patch(examples[index].patch, true):
			push_error("Patch example refused: " + synth_error)
			get_tree().quit(1)
			return
	if _args.has("density"):
		load_density(int(_args.density))
	if _args.has("source"):
		_import_source(str(_args.source))
	if _args.has("scientific"):
		scientific = true
	if _args.has("clean"):
		ui.toggle_clean()
	if _args.has("hide-panel"):
		ui.rail.hide()
	if _args.has("fixed-time"):
		bus.seek(float(_args["fixed-time"]))
		bus.paused = true
	if _args.has("no-optical"):
		optical_flags.enabled = false
	if _args.has("legacy-optics"):
		set_parameter("optical.optical_mix", 0.0)
	if _args.has("close-optics"):
		camera.set_pose({"distance": camera.orbit_distance * 0.58})
	if _args.has("no-filaments"):
		filament_flags.enabled = false
	if _args.has("no-fibres"):
		filament_flags.fibres = 0
	if _args.has("no-wave"):
		for key in ["wave_amplitude", "resonance", "turbulence", "braid_radius"]:
			bus.set_base("filament." + key, 0.0)
		bus.enabled = false
	_setup_file_dialog()
	recorder.setup(get_viewport())
	_ready_done = true
	if _args.has("ecosystem"):
		set_workspace("planar")
		_set_ecology_lfo(bool(ecology.world.config.get("lfo", false)))
	if _args.has("spatial-ecology"):
		set_workspace("spatial", true)
	startup_usec = Time.get_ticks_usec() - _startup_started
	_frame_canvas()
	_sync_ui()
	print("XENOVECTION_READY ", JSON.stringify({"source": dataset.manifest.source_id,
		"source_revision": dataset.manifest.revision, "nodes": dataset.nodes.size(),
		"edges": dataset.edges.size(), "preset": presets[preset_index].id, "build": _build}))

func _setup_world() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.003, 0.007, 0.014)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.18, 0.26, 0.32)
	environment.ambient_light_energy = 0.25
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.8
	environment.glow_enabled = false
	world.environment = environment
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, -28, 0)
	key.light_color = Color(0.55, 0.78, 0.86)
	key.light_energy = 0.45
	key.shadow_enabled = false
	add_child(key)

func _frame_canvas() -> void:
	if not is_instance_valid(ui.rail):
		return
	# Reserve the control rail's screen space without changing source coordinates.
	var height: float = maxf(get_viewport().get_visible_rect().size.y, 1.0)
	camera.h_offset = camera.orbit_distance * tan(deg_to_rad(camera.fov * 0.5)) * 326.0 / height if ui.rail.visible and not ui.clean_view else 0.0
	camera.v_offset = -camera.orbit_distance * tan(deg_to_rad(camera.fov * 0.5)) * 76.0 / height if not ui.clean_view else 0.0

func _notification(what: int) -> void:
	if not _ready_done:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_dragging = false
		ui.show_selection_box(Rect2(), false)
		camera.release_pointer()

func _register_defaults() -> void:
	bus.reset_registry()
	instrument_clock.reset()
	filament_flags = FilamentRenderer.DEFAULTS.duplicate(true)
	optical_flags = OpticalRenderer.DEFAULTS.duplicate(true)
	for name: String in FilamentRenderer.NUMERIC_BOUNDS:
		var bound: Vector2 = FilamentRenderer.NUMERIC_BOUNDS[name]
		bus.register_target("filament." + name, float(filament_flags[name]), bound.x, bound.y)
	for name: String in OpticalRenderer.LIMITS:
		var bound: Vector2 = OpticalRenderer.LIMITS[name]
		bus.register_target("optical." + name, float(optical_flags[name]), bound.x, bound.y)
	bus.register_target("optical.sky_frequency", optical_flags.sky_frequency, -16.0, 16.0)
	bus.register_target("optical.sky_pan", Vector2.ZERO, -100.0, 100.0)
	bus.register_target("optical.material_tint", optical_flags.material_tint, 0.0, 1.0)
	matter.register_targets(bus)
	for key in EcologyWorld.BOUNDS:
		var bound: Vector2 = EcologyWorld.BOUNDS[key]
		bus.register_target("eco." + str(key), float(EcologyWorld.DEFAULTS[key]), bound.x, bound.y)
	mod_depth = 1.0
	mod_frequency = 0.08
	mod_waveform = "sine"
	_rebuild_modulation()

func _rebuild_modulation() -> void:
	bus.clear_routes()
	bus.register_source("breath", {"type": "lfo", "clock": "sky", "frequency": mod_frequency, "waveform": mod_waveform, "phase": 0.0})
	bus.register_source("counterphase", {"type": "lfo", "clock": "filament", "frequency": mod_frequency * 1.37, "waveform": "sine", "phase": 0.25})
	bus.add_route({"id": "breath-braid", "source": "breath", "target": "filament.braid_radius", "amplitude": 0.023 * mod_depth, "operation": "add", "smoothing": 0.18})
	bus.add_route({"id": "breath-field", "source": "breath", "target": "optical.sky_warp", "amplitude": 0.15 * mod_depth, "operation": "add", "smoothing": 0.18})
	bus.add_route({"id": "counter-resonance", "source": "counterphase", "target": "filament.resonance", "amplitude": 0.28 * mod_depth, "operation": "multiply"})
	bus.add_route({"id": "spectral-drift", "source": "breath", "target": "optical.sky_frequency", "amplitude": Vector2(0.14, -0.1) * mod_depth, "operation": "add"})
	bus.add_route({"id": "material-breath", "source": "breath", "target": "optical.material_tint", "amplitude": Color(0.035, 0.018, -0.015, 0) * mod_depth, "operation": "add"})
	# Existing clock and typed bus; no second modulation engine.
	bus.add_route({"id": "optical-depth-breath", "source": "counterphase", "target": "optical.optical_thickness", "amplitude": 0.12 * mod_depth, "operation": "multiply", "smoothing": 0.18})
	bus.add_route({"id": "optical-phase-breath", "source": "breath", "target": "optical.interference_phase", "amplitude": 0.38 * mod_depth, "operation": "add"})
	bus.register_source("sample", {"type": "manual", "value": 0.0})
	bus.add_route({"id": "sample-phase", "source": "sample", "target": "filament.phase_speed", "amplitude": 0.55, "operation": "add", "mask": 1.0 if replay_enabled else 0.0})
	bus.add_route({"id": "sample-field", "source": "sample", "target": "optical.sky_warp", "amplitude": 0.2, "operation": "add", "mask": 1.0 if replay_enabled else 0.0})
	if not synth.patch.is_empty() and not synth.attach(bus):
		synth_error = synth.last_error

func load_density(channels: int) -> void:
	density = clampi(channels, 4, 128)
	var result: Dictionary = source.load_json("res://data/synthetic_foundry.json") if density == 48 else source.generate_synthetic(density)
	if not result.ok:
		ui.show_message("Source refused: " + str(result.error), 8)
		return
	_bind_source()

func load_spatial_flow() -> void:
	var result: Dictionary = source.generate_spatial_flow()
	if not result.ok:
		ui.show_message("Spatial source refused: " + str(result.error), 8)
		return
	density = 0
	_bind_source()

func _select_example_region() -> void:
	if density > 0:
		selection.select_band(2, mini(8, density / 2), mini(12, density))
		return
	# A generic spatial source need not have the founding layer/channel layout.
	var candidates: Array = dataset.nodes.duplicate()
	var centre: Vector3 = camera.pivot
	candidates.sort_custom(func(a: Dictionary, b: Dictionary):
		var da: float = a.position.distance_squared_to(centre)
		var db: float = b.position.distance_squared_to(centre)
		return da < db if da != db else a.id < b.id)
	var ids: Array = []
	var membership: Dictionary = {}
	for index in range(mini(96, candidates.size())):
		ids.append(candidates[index].id)
		membership[candidates[index].index] = true
	var edges: Array = []
	for edge: Dictionary in dataset.edges:
		if membership.has(edge.from_index) and membership.has(edge.to_index):
			edges.append(edge.id)
	selection.select(ids, edges, false, "nearest-spatial-region-induced-edges")

func _bind_source() -> void:
	dataset = source.get_dataset()
	_source_sha = dataset.manifest.revision
	replay.generate_synthetic(dataset)
	bus.register_source("sample", {"type": "manual", "value": 0.0})
	filaments.set_dataset(dataset)
	optical.set_dataset(dataset)
	selection.bind_dataset(dataset)
	var layers: Array = []
	for node: Dictionary in dataset.nodes:
		if not node.layer in layers:
			layers.append(node.layer)
	layers.sort()
	ui.set_source_layers(layers)
	if is_instance_valid(ui.source_label):
		ui.source_label.text = "%s\n\n%d nodes · %d exact edges\n\nSource revision\n%s\n\nCoordinates: %s\n\n%s\n\nSource values are read-only. The inspector distinguishes source values, derived quantities and artistic appearance." % [dataset.manifest.source_id, dataset.nodes.size(), dataset.edges.size(), str(dataset.manifest.revision).substr(0, 32) + "…", dataset.manifest.coordinate_mapping, dataset.manifest.description]
		ui.source_label.tooltip_text = JSON.stringify(dataset.manifest, "\t")
	_selection_changed()

func apply_preset(index: int) -> void:
	var prepared_at := Time.get_ticks_usec()
	_applying_composition = true
	synth = SynthGraph.new()
	preset_index = clampi(index, 0, presets.size() - 1)
	var preset: Dictionary = presets[preset_index]
	_register_defaults()
	for name: String in preset.get("filament", {}):
		set_parameter("filament." + name, preset.filament[name])
	for name: String in preset.get("optical", {}):
		set_parameter("optical." + name, preset.optical[name])
	bus.enabled = preset.get("modulation", true)
	scientific = preset.get("scientific", false)
	if preset.get("source", "foundry") == "spatial_flow":
		load_spatial_flow()
	else:
		load_density(int(preset.density))
	selection.clear()
	selection.reveal()
	if preset.has("band"):
		selection.select_band(preset.band[0], preset.band[1], preset.band[2])
	selection.set_materialisation(preset.materialisation)
	camera.reset_view()
	if preset.get("focus", false):
		camera.focus_points(selection.get_selected_points())
	camera.set_pose({"distance": preset.distance, "yaw": preset.yaw, "pitch": preset.pitch})
	bus.reset()
	matter.set_defaults(bus,preset)
	if is_instance_valid(ecology):
		if preset.has("ecology_config"):
			ecology.apply_configuration(preset.ecology_config)
			ecology.paused = false
			ecology.simulation_enabled = true
			set_workspace("spatial")
		else:
			ecology.simulation_enabled = false
			_spatial_requested = false
			spatial_ecology.clear_organisms()
			set_workspace("instrument")
	_refresh_target_availability()
	if preset.has("synth_patch"):
		if not install_synth_patch(preset.synth_patch):
			push_error("Integrated composition patch refused: " + synth_error)
	if is_instance_valid(ecology) and ecology.simulation_enabled and bool(ecology.world.config.get("lfo", false)):
		_set_ecology_lfo(true)
	_applying_composition = false
	scene_prepare_usec = Time.get_ticks_usec() - prepared_at
	scene_prepare_samples.append(scene_prepare_usec)
	if scene_prepare_samples.size() > 128: scene_prepare_samples.pop_front()
	ui.preset_picker.select(preset_index)
	ui.set_tab(ui.tabs.get_node("Matter").get_index() if matter.active else (1 if preset.id in ["optical", "membrane"] or str(preset.id).begins_with("optical_") else 0))
	ui.subtitle_label.text = str(preset.description).to_upper()
	if _ready_done:
		recorder.reset()
		_sync_ui()
	if is_instance_valid(synth_panel):
		synth_panel.refresh()

func install_synth_patch(data: Dictionary, recall: bool = false, morph: bool = false) -> bool:
	synth_error = ""
	var migrated := Catalogue.migrate_patch(data, presets)
	if not migrated.ok:
		synth_error = migrated.error
		return false
	data = migrated.patch
	var candidate = SynthGraph.new()
	if not candidate.configure(data, bus):
		synth_error = candidate.last_error
		return false
	if int(candidate.patch.preset) >= presets.size():
		synth_error = "Scene is not present in this application."
		return false
	var previous = synth
	var compatible: bool = morph and candidate.transition_from(previous)
	if recall and not compatible:
		apply_preset(int(candidate.patch.preset))
		if not candidate.configure(data, bus):
			synth_error = candidate.last_error
			return false
	if synth.patch.is_empty():
		synth_base_enabled = bus.enabled
	if not candidate.attach(bus):
		if not synth.patch.is_empty():
			synth.attach(bus)
		synth_error = candidate.last_error
		return false
	synth = candidate
	bus.enabled = true
	if recall:
		for clock in candidate.patch.clocks:
			bus.set_clock(clock, candidate.patch.clocks[clock])
		if not compatible:
			bus.reset()
		if is_instance_valid(synth_panel):
			ui.set_tab(ui.tabs.get_node("Synth").get_index())
		if morph:
			synth_error = "0.8 s compatible morph." if compatible else "Different scene or routing: explicit cut."
	_sync_ui()
	if is_instance_valid(synth_panel): synth_panel.refresh()
	return true

func stop_synth() -> void:
	if synth.patch.is_empty():
		return
	synth.detach(bus)
	synth = SynthGraph.new()
	bus.enabled = synth_base_enabled
	_rebuild_modulation()
	_sync_ui()

func set_parameter(target: String, value: Variant) -> void:
	if target.begins_with("matter.edit."):
		matter.edit(bus,target.trim_prefix("matter.edit."),value)
	elif target == "modulation.enabled":
		bus.enabled = bool(value)
	elif target == "modulation.frequency":
		mod_frequency = float(value)
		_rebuild_modulation()
	elif target == "modulation.depth":
		mod_depth = float(value)
		_rebuild_modulation()
	elif target == "modulation.waveform":
		mod_waveform = str(value)
		_rebuild_modulation()
	elif target == "fibres_enabled":
		filament_flags.fibres = 2 if bool(value) else 0
	elif target == "replay.enabled":
		replay_enabled = bool(value)
		_rebuild_modulation()
	elif target.begins_with("layer."):
		selection.set_layer_visible(int(target.trim_prefix("layer.")), bool(value))
	elif target in ["optical.sky_frequency_x", "optical.sky_frequency_y"]:
		var frequency: Vector2 = bus.get_base("optical.sky_frequency")
		if target.ends_with("_x"):
			frequency.x = float(value)
		else:
			frequency.y = float(value)
		bus.set_base("optical.sky_frequency", frequency)
	elif target in ["optical.sky_pan_x", "optical.sky_pan_y"]:
		var pan: Vector2 = bus.get_base("optical.sky_pan")
		if target.ends_with("_x"): pan.x = float(value)
		else: pan.y = float(value)
		bus.set_base("optical.sky_pan", pan)
	elif bus.targets.has(target):
		bus.set_base(target, value)
	elif target.begins_with("filament."):
		filament_flags[target.trim_prefix("filament.")] = value
	elif target.begins_with("optical."):
		optical_flags[target.trim_prefix("optical.")] = value

func _process(delta: float) -> void:
	if not _ready_done:
		return
	var start: int = Time.get_ticks_usec()
	_frame += 1
	_refresh_target_availability()
	var effective: Dictionary
	if ecology.automated:
		effective = bus.evaluate(0.0)
	else:
		effective = instrument_clock.advance(bus, synth, delta, scientific, _ecology_boundary)
	_last_effective = effective
	if replay_enabled and not dataset.nodes.is_empty():
		replay.advance(float(bus.get_clocks().filament))
		var sample: Dictionary = replay.get_latest("node", dataset.nodes[0].id)
		bus.register_source("sample", {"type": "manual", "value": float(sample.get("value", 0.0))})
		effective = bus.evaluate(0.0)
	var fp: Dictionary = filament_flags.duplicate()
	var op: Dictionary = optical_flags.duplicate()
	for key: String in effective:
		if key.begins_with("filament."):
			fp[key.trim_prefix("filament.")] = effective[key]
		elif key.begins_with("optical."):
			op[key.trim_prefix("optical.")] = effective[key]
	fp.scientific = scientific
	op.scientific = scientific
	if scientific:
		fp.enabled = true
		fp.coverage = 1.0
		fp.palette_amount = 0.0
		fp.opacity = 0.24
		fp.line_width_px = 0.55
	filaments.set_parameters(fp)
	optical.set_parameters(op)
	var clocks: Dictionary = bus.get_clocks()
	filaments.update_clocks(clocks)
	optical.update_clocks(clocks)
	matter.update(bus,effective,clocks,delta,scientific,_args.has("no-matter"),optical.get_environment_context())
	spatial_ecology.visible = _spatial_requested and ecology.simulation_enabled and not scientific and workspace_mode != "planar"
	var presentation_alpha: float = 1.0 if ecology.paused or not ecology.simulation_enabled else float(posmod(instrument_clock.ticks, 4)) / 4.0 + float(instrument_clock.accumulator) / EcologyWorld.DT
	ecology.presentation_alpha = presentation_alpha
	if spatial_ecology.visible:
		spatial_ecology.quality = [1, 2, 4].find(ecology.stride)
		spatial_ecology.selected = ecology.selected
		spatial_ecology.isolated = ecology.isolated
		spatial_ecology.update_presentation(presentation_alpha, optical.get_environment_context(), clocks)
	filaments.visible = workspace_mode != "planar"
	optical.visible = workspace_mode != "planar"
	if workspace_mode == "planar": matter.hide()
	_hud_elapsed += delta
	if _hud_elapsed > 0.5:
		_hud_elapsed = 0.0
		_update_performance()
		life_panel.refresh()
	recorder.sample(Time.get_ticks_usec() - start)
	var warmup: int = int(_args.get("warmup", 45))
	if _frame == warmup:
		recorder.reset()
	if _args.has("capture") and not _captured and _frame >= int(_args.get("capture-frame", 90)):
		_captured = true
		_capture(str(_args.capture))
	if _args.has("profile") and _frame >= warmup + int(_args.get("profile-frames", 240)):
		recorder.save(str(_args.profile), evidence_context())
		print("XENOVECTION_PROFILE_SAVED ", str(_args.profile))
		get_tree().quit(0)

func evidence_context() -> Dictionary:
	# Canvas stretching can make both visible_rect and ViewportTexture.size logical.
	# Read actual pixels only when emitting a receipt, after the sampled frames.
	var rendered_pixels: Array = [0, 0]
	if DisplayServer.get_name() != "headless":
		var rendered_image: Image = get_viewport().get_texture().get_image()
		if rendered_image != null and not rendered_image.is_empty():
			rendered_pixels = [rendered_image.get_width(), rendered_image.get_height()]
	return {"build": _build, "preset": presets[preset_index].id, "scientific": scientific,
		"viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"viewport_scope": "Logical canvas coordinates; render_target_pixels is an actual image readback outside the frame samples",
		"render_target_pixels": rendered_pixels,
		"hud_visible": not ui.clean_view, "control_panel_visible": ui.rail.visible and not ui.clean_view,
		"source": dataset.manifest, "selection": selection.get_reference(),
		"filaments": filaments.get_metrics(), "optical": optical.get_metrics(),
		"clocks": bus.get_clocks(), "camera": _encode(camera.get_pose()),
		"modulation": _encode(bus.snapshot()), "sample_replay": replay.get_metrics(),
		"synthesis": synth.metrics(), "synth_patch": synth.snapshot(bus) if not synth.patch.is_empty() else {},
		"matter": matter.metrics(), "composition_id": presets[preset_index].stable_id,
		"instrument_clock": instrument_clock.metrics(), "modulation_diagnostics": bus.diagnostics.duplicate(true),
		"ecology": ecology.convergence_metrics(), "ecology_digest": ecology.world.digest(),
		"spatial_ecology": spatial_ecology.metrics(), "workspace": workspace_mode,
		"startup_usec": startup_usec, "scene_prepare_usec": scene_prepare_usec,
		"scene_transitions": _timing_summary(scene_prepare_samples), "workspace_transitions": _timing_summary(transition_samples),
		"source_unchanged": _source_sha == dataset.manifest.revision}

func _update_performance() -> void:
	var metric: Dictionary = recorder.snapshot()
	if int(metric.samples) == 0:
		ui.performance_label.text = "Measuring frame times…"
		return
	var fm: Dictionary = filaments.get_metrics()
	var gpu_text: String = "n/a"
	if metric.gpu_timing_available:
		gpu_text = "%.2f ms" % metric.render_gpu.p50_ms
	var device_label: String = "Software device" if metric.platform.software_device else "GPU"
	ui.performance_label.text = "%.1f FPS   ·   frame p50 / p95  %.1f / %.1f ms   ·   CPU render  %.2f ms   ·   %s  %s   ·   %d draws   ·   %s strands" % [metric.fps_from_mean_frame, metric.wall_frame.p50_ms, metric.wall_frame.p95_ms, metric.render_cpu.p50_ms, device_label, gpu_text, metric.draw_calls_3d, str(int(fm.get("visible_strands", 0)))]

func _selection_changed() -> void:
	if dataset.is_empty():
		return
	var state: Dictionary = selection.get_visual_state()
	filaments.set_visual_state(state)
	optical.set_visual_state(state)
	if not is_instance_valid(ui.selection_label):
		return
	var kind: String = " · %s proxy (artistic)" % state.materialisation if state.materialisation != "none" else ""
	ui.selection_label.text = "Selected: %d exact nodes · %d exact edges%s" % [state.node_ids.size(), state.edge_ids.size(), kind]
	ui.measurement_label.text = "Source IDs are unchanged by phase, fibres, materials and displacement."
	if state.node_ids.size() == 1:
		var node: Dictionary = source.get_node(state.node_ids[0])
		if _is_recovered_source() and int(node.layer) == 0:
			probe.probe(node.channel)
		var measure: Dictionary = probe.node_measurement(node.layer, node.channel) if _is_recovered_source() else {}
		ui.measurement_label.text = "%s · value %s (%s)" % [node.id, JSON.stringify(node.value, "", true, true), node.value_kind]
		if not measure.is_empty():
			ui.measurement_label.text += "\nΔh %.7f · derived forward response to input %d + %.3f" % [measure.delta, probe.selected_input, probe.epsilon]
	elif state.edge_ids.size() == 1:
		var edge: Dictionary = source.get_edge(state.edge_ids[0])
		ui.measurement_label.text = "%s → %s  ·  %s\nValue = %s (%s)" % [edge.source, edge.target, edge.id, JSON.stringify(edge.weight, "", true, true), edge.value_kind]
		if _is_recovered_source():
			ui.measurement_label.text = "%s → %s  ·  %s\nStored W = %s · synthetic source coefficient" % [edge.source, edge.target, edge.id, JSON.stringify(edge.weight, "", true, true)]
			var ids: PackedStringArray = str(edge.id).split(":")
			var measure: Dictionary = probe.edge_measurement(int(ids[1]), int(ids[2]), int(ids[3]))
			ui.measurement_label.text += " · W × Δh = %.7f (derived)" % float(measure.get("signed_flow", 0.0))

func _is_recovered_source() -> bool:
	return bool(dataset.get("manifest", {}).get("historical_custody_verified", false)) and _source_sha == "sha256:745d47fa3ebd6a91ce1c9bd11181688ce4237199bbbce11e2e330dc76d78947c"

func _source_descriptor() -> Dictionary:
	var id: String = str(dataset.get("manifest", {}).get("source_id", ""))
	if _is_recovered_source():
		return {"kind": "historical", "density": 48}
	if id == "xenovection-spatial-flow-v1":
		return {"kind": "flow", "density": 0}
	if density >= 4 and id == "found-002-synthetic-%d" % density:
		return {"kind": "synthetic", "density": density}
	return {"kind": "external", "source_id": id}

func _unhandled_input(event: InputEvent) -> void:
	if not _ready_done or workspace_mode == "planar":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: handle_action("pause")
			KEY_G: handle_action("scientific")
			KEY_V: handle_action("reverse")
			KEY_TAB: handle_action("panel")
			KEY_H: handle_action("clean")
			KEY_F: handle_action("focus")
			KEY_I: handle_action("isolate")
			KEY_R: handle_action("reset")
			KEY_M: handle_action("knot")
			KEY_U: handle_action("unmaterialise")
			KEY_ESCAPE: handle_action("release")
			KEY_F5: handle_action("save_scene")
			KEY_F6: handle_action("load_scene")
			KEY_F7: handle_action("synth")
			KEY_F2: handle_action("matter_workspace")
			KEY_F3: handle_action("optical_workspace")
			KEY_F4: handle_action("life_workspace")
			KEY_F9: handle_action("export_selection")
			KEY_F10: handle_action("profile")
			KEY_F12: handle_action("screenshot")
			KEY_Z:
				if event.ctrl_pressed: handle_action("redo" if event.shift_pressed else "undo")
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				apply_preset(event.keycode - KEY_1)
			KEY_0: apply_preset(9)
			_:
				return
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not scientific and spatial_ecology.visible and life_panel.owns_spatial_pointer():
			var hit: Dictionary = spatial_ecology.ray_to_domain(camera, event.position)
			if hit.valid:
				ecology.intervene_at(hit.point)
				life_panel.refresh()
			get_viewport().set_input_as_handled()
			return
		if matter.active and not scientific:
			matter.pick(camera,event.position)
			_sync_ui()
			get_viewport().set_input_as_handled()
			return
		_dragging = true
		_drag_start = event.position
		_drag_additive = event.shift_pressed
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if not _ready_done or workspace_mode == "planar" or not _dragging:
		return
	if event is InputEventMouseMotion:
		ui.show_selection_box(Rect2(_drag_start, event.position - _drag_start), _drag_start.distance_to(event.position) > 5)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
		ui.show_selection_box(Rect2(), false)
		var state: Dictionary = selection.get_visual_state()
		if _drag_start.distance_to(event.position) > 7:
			var result: Dictionary = SpatialSelection.box(camera, dataset, Rect2(_drag_start, event.position - _drag_start), state.hidden_layers)
			selection.select(result.node_ids, result.edge_ids, _drag_additive, result.selection_origin)
		else:
			var picked: Dictionary = SpatialSelection.pick(camera, dataset, event.position, 9, state.hidden_layers, filaments)
			if not str(picked.get("warning", "")).is_empty():
				ui.show_message(str(picked.warning), 7)
			if picked.kind == "node": selection.select_node(picked.id, true, _drag_additive)
			elif picked.kind == "edge": selection.select_edge(picked.id, _drag_additive)
			elif not _drag_additive:
				var proxy_hit: Dictionary = optical.ray_pick_proxy(camera.project_ray_origin(event.position), camera.project_ray_normal(event.position), camera.far)
				if proxy_hit.is_empty():
					selection.clear()
				else:
					# A proxy identifies its existing exact group, never a fabricated item.
					ui.show_message("Optical group · %d source nodes / %d source edges retained" % [proxy_hit.source_membership.node_ids.size(), proxy_hit.source_membership.edge_ids.size()])
		get_viewport().set_input_as_handled()

func handle_action(action: String) -> void:
	if action in ["undo", "redo"] and is_instance_valid(synth_panel) and ui.tabs.current_tab == ui.tabs.get_node("Synth").get_index():
		synth_panel._redo() if action == "redo" else synth_panel._undo()
		return
	if matter.active and not scientific and (not action in ["undo", "redo"] or ui.tabs.current_tab == ui.tabs.get_node("Matter").get_index()):
		if action.begins_with("matter_select_"):
			matter.selected = clampi(int(action.trim_prefix("matter_select_")),0,Matter.COUNT-1)
			_sync_ui()
			return
		match action:
			"focus": camera.focus_points(matter.focus_points())
			"isolate": matter.isolated = not matter.isolated
			"reveal": matter.isolated = false
			"matter_reintegrate": matter.rebuild(bus,matter.selected)
			"matter_reseed": matter.edit(bus,"seed",fmod(float(bus.get_base(Matter.target(matter.selected,"seed")))+1.0,10000.0))
			"matter_particles_reset": matter.reset_particles(bus)
			"undo", "redo": matter.undo(bus,action == "redo")
			_: pass
		if action in ["focus","isolate","reveal","matter_reintegrate","matter_reseed","matter_particles_reset","undo","redo"]:
			_sync_ui()
			return
	match action:
		"pause": bus.paused = not bus.paused
		"scientific": scientific = not scientific
		"reverse":
			for clock: String in bus.clocks:
				bus.set_clock(clock, {"rate": -float(bus.clocks[clock].rate)})
			ui.sync_clocks(bus.clocks)
		"panel":
			ui.toggle_panel()
			_frame_canvas()
		"clean":
			ui.toggle_clean()
			_frame_canvas()
		"reset": apply_preset(preset_index)
		"reset_time":
			bus.reset()
			if not synth.patch.is_empty(): synth.reset()
			matter.reset_particles(bus)
		"synth":
			if ui.clean_view: ui.toggle_clean()
			ui.rail.show()
			ui.set_tab(ui.tabs.get_node("Synth").get_index())
			synth_panel.refresh()
			_frame_canvas()
		"matter_workspace", "optical_workspace", "life_workspace":
			if ui.clean_view: ui.toggle_clean()
			ui.rail.show()
			var page: String = {"matter_workspace": "Matter", "optical_workspace": "Optics", "life_workspace": "Life"}[action]
			ui.set_tab(ui.tabs.get_node(page).get_index())
			_frame_canvas()
		"focus": camera.focus_points(selection.get_selected_points())
		"isolate": selection.set_isolated(not selection.get_visual_state().isolate)
		"reveal": selection.reveal()
		"release":
			camera.release_pointer()
			_dragging = false
			ui.show_selection_box(Rect2(), false)
		"select_region": _select_example_region()
		"knot", "ribbon", "membrane":
			if selection.get_selected_points().is_empty(): _select_example_region()
			selection.set_materialisation(action)
			scientific = false
			optical_flags.enabled = true
			ui.set_tab(1)
		"unmaterialise":
			selection.set_materialisation("none")
			filament_flags.enabled = true
			ui.set_tab(0)
		"undo": selection.undo()
		"redo": selection.redo()
		"density24", "density48", "density96", "density128":
			load_density(int(action.trim_prefix("density")))
			ui.show_message("%d exact edges loaded" % dataset.edges.size())
		"import": _file_dialog.popup_centered_ratio(0.65)
		"export_selection": _save_json("user://selection.json", selection.get_reference())
		"export_source":
			if source.export_json("user://source.json") == OK: ui.show_message("Saved source.json · " + OS.get_user_data_dir(), 8)
		"export_replay":
			if replay.export_json("user://samples.json") == OK: ui.show_message("Saved samples.json · derived calibration samples", 6)
		"save_scene": save_scene("user://scene.json")
		"load_scene": load_scene("user://scene.json")
		"save_scene_as": _open_composition_dialog(true)
		"open_scene": _open_composition_dialog(false)
		"recover_scene": load_scene("user://scene.json.bak")
		"profile":
			if recorder.save("user://performance.json", evidence_context()) == OK: ui.show_message("Saved performance.json · " + OS.get_user_data_dir(), 8)
		"screenshot": _capture("user://capture-%d.png" % Time.get_unix_time_from_system())
	_sync_ui()

func _sync_ui() -> void:
	if not is_instance_valid(ui.mode_button):
		return
	ui.set_transport(scientific, bus.paused)
	ui.sync_clocks(bus.clocks)
	ui.sync_matter(matter.active,matter.selected,matter.isolated,matter.params(bus,matter.selected))
	if is_instance_valid(life_panel): life_panel.refresh()
	for key: String in bus.targets:
		if bus.get_base(key) is float or bus.get_base(key) is int:
			ui.sync_value(key, bus.get_base(key))
	for key: String in filament_flags:
		if filament_flags[key] is bool:
			ui.sync_value("filament." + key, filament_flags[key])
	for key: String in optical_flags:
		if optical_flags[key] is bool or key == "palette":
			ui.sync_value("optical." + key, optical_flags[key])
	var frequency: Vector2 = bus.get_base("optical.sky_frequency")
	ui.sync_value("optical.sky_frequency_x", frequency.x)
	ui.sync_value("optical.sky_frequency_y", frequency.y)
	var pan: Vector2 = bus.get_base("optical.sky_pan")
	ui.sync_value("optical.sky_pan_x", pan.x)
	ui.sync_value("optical.sky_pan_y", pan.y)
	ui.sync_value("fibres_enabled", int(filament_flags.fibres) > 0)
	ui.sync_value("modulation.enabled", bus.enabled)
	ui.sync_value("modulation.depth", mod_depth)
	ui.sync_value("modulation.frequency", mod_frequency)
	ui.sync_value("modulation.waveform", mod_waveform)
	ui.sync_value("optical.material_tint", bus.get_base("optical.material_tint"))
	ui.sync_value("replay.enabled", replay_enabled)
	var visible_state: Dictionary = selection.get_visual_state()
	for node: Dictionary in dataset.get("nodes", []):
		ui.sync_value("layer.%d" % node.layer, not node.layer in visible_state.hidden_layers)

func _setup_file_dialog() -> void:
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = PackedStringArray(["*.json ; Xenovection source or FOUND-001 specimen"])
	_file_dialog.file_selected.connect(_import_source)
	ui.add_child(_file_dialog)
	_composition_dialog = FileDialog.new()
	_composition_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_composition_dialog.filters = PackedStringArray(["*.json ; Xenovection authored composition"])
	_composition_dialog.file_selected.connect(func(path: String):
		if _composition_saving: save_scene(path)
		else: load_scene(path))
	ui.add_child(_composition_dialog)

func _open_composition_dialog(saving: bool) -> void:
	_composition_saving = saving
	_composition_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if saving else FileDialog.FILE_MODE_OPEN_FILE
	_composition_dialog.current_file = "xenovection-composition.json" if saving else ""
	_composition_dialog.popup_centered_ratio(0.72)

func _import_source(path: String) -> void:
	var result: Dictionary = source.load_json(path)
	if result.ok:
		density = 0
		_bind_source()
		ui.show_message("Imported source snapshot: " + str(dataset.manifest.source_id))
	else:
		ui.show_message("Source refused: " + str(result.get("error", "Invalid source")), 10)

func save_scene(path: String) -> void:
	var bases: Dictionary = {}
	for key: String in bus.targets:
		bases[key] = bus.get_base(key)
	var scene: Dictionary = {"schema": "xenovection.scene.v1", "source_revision": _source_sha,
		"source_projection_revision": dataset.manifest.projection_revision,
		"source_id": dataset.manifest.source_id, "source_descriptor": _source_descriptor(), "density": density, "preset_index": preset_index,
		"base_parameters": _encode(bases), "filament_flags": _encode(filament_flags),
		"optical_flags": _encode(optical_flags), "selection": selection.get_visual_state(),
		"camera": _encode(camera.get_pose()), "clocks": _encode(bus.clocks),
		"scientific": scientific, "paused": bus.paused, "modulation_enabled": bus.enabled,
		"mod_depth": mod_depth, "mod_frequency": mod_frequency, "mod_waveform": mod_waveform,
		"replay_enabled": replay_enabled, "synth_patch": synth.snapshot(bus) if not synth.patch.is_empty() else {}, "matter": matter.snapshot()}
	var envelope := CompositionStore.encode_scene(scene, presets, ecology.authoring_snapshot(), workspace_mode)
	if CompositionStore.write(path, _encode(envelope)):
		ui.show_message("Saved composition · authored state; simulation histories restart on recall", 6)
	else:
		ui.show_message("Could not atomically save composition", 6)

func load_scene(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		ui.show_message("Save a scene first with F5")
		return false
	if file.get_length() > 4 * 1024 * 1024:
		ui.show_message("Scene exceeds 4 MiB limit")
		return false
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or not data.get("schema", "") in ["xenovection.scene.v1", CompositionStore.SCHEMA]:
		ui.show_message("Invalid scene file")
		return false
	var saved_schema: String = str(data.schema)
	var normalized := CompositionStore.normalize(data, presets, bus.default_parameters(), FilamentRenderer.DEFAULTS, OpticalRenderer.DEFAULTS)
	if not normalized.ok:
		ui.show_message("Composition refused: " + str(normalized.error), 8)
		return false
	data = normalized.scene
	var matter_data: Variant = data.get("matter",{"schema":Matter.SCHEMA,"active":false,"selected":0,"isolated":false,"baked":[]})
	if not Matter.valid_snapshot(matter_data):
		ui.show_message("Scene refused: malformed procedural region state",8)
		return false
	var candidate_source = source
	if str(data.get("source_revision", "")) != _source_sha:
		# V2 can reconstitute a known built-in source without touching live state.
		# Imported sources still require their exact source snapshot explicitly.
		var descriptor: Variant = data.get("source_descriptor", {})
		if saved_schema != CompositionStore.SCHEMA or _source_descriptor().kind == "external" or not descriptor is Dictionary:
			ui.show_message("Scene belongs to another source. Load its exact source first.", 8)
			return false
		candidate_source = SourceModel.new()
		var result: Dictionary = {"ok": false}
		match str(descriptor.get("kind", "external")):
			"historical": result = candidate_source.load_json("res://data/synthetic_foundry.json")
			"flow": result = candidate_source.generate_spatial_flow()
			"synthetic":
				var amount: Variant = descriptor.get("density", 0)
				if (amount is int or amount is float) and float(amount) == floorf(float(amount)) and amount >= 4 and amount <= 128:
					result = candidate_source.generate_synthetic(int(amount))
		if not result.ok:
			ui.show_message("Composition source cannot be reconstructed; exact external source required", 8)
			return false
	var checked: Dictionary = SceneValidation.validate(data, candidate_source.get_dataset(), bus.targets, FilamentRenderer.DEFAULTS, OpticalRenderer.DEFAULTS)
	if not checked.ok:
		ui.show_message("Scene refused: " + str(checked.get("error", "Invalid scene")), 8)
		return false
	data = checked.scene
	var saved_patch = data.get("synth_patch", {})
	if not saved_patch is Dictionary:
		ui.show_message("Scene contains malformed patch data")
		return false
	if not saved_patch.is_empty():
		var validator = SynthGraph.new()
		if not validator.configure(saved_patch, bus) or int(validator.patch.preset) != int(data.get("preset_index", preset_index)) or int(validator.patch.preset) >= presets.size():
			ui.show_message("Scene patch refused: " + validator.last_error, 8)
			return false
	_applying_composition = true
	stop_synth()
	_register_defaults()
	if candidate_source != source:
		source = candidate_source
		density = int(data.get("density", 0))
		_bind_source()
	# Older v1 scenes omitted these destinations; do not inherit a live effect.
	for name: String in ["optical_mix","optical_thickness","absorption","transmission","ior","interference_phase","interference_strength","spectral_bandwidth","dispersion_strength","reflection_intensity","optical_field","illumination_direction","illumination_intensity","illumination_balance","refraction_strength","layer_spacing","atmospheric_density","optical_diagnostic"]:
		bus.set_base("optical." + name, OpticalRenderer.DEFAULTS[name])
	for key: String in data.get("base_parameters", {}):
		set_parameter(key, _decode(data.base_parameters[key]))
	for key: String in data.get("filament_flags", {}):
		if not bus.targets.has("filament." + key): set_parameter("filament." + key, _decode(data.filament_flags[key]))
	for key: String in data.get("optical_flags", {}):
		if not bus.targets.has("optical." + key): set_parameter("optical." + key, _decode(data.optical_flags[key]))
	var state: Dictionary = data.get("selection", {})
	selection.restore_visual_state(state)
	camera.set_pose(_decode(data.get("camera", {})))
	for clock: String in data.get("clocks", {}):
		var settings: Dictionary = data.clocks[clock]
		bus.set_clock(clock, settings)
		if bus.clocks.has(clock) and is_finite(float(settings.get("time", 0.0))):
			bus.clocks[clock].time = clampf(float(settings.get("time", 0.0)), -86400.0, 86400.0)
	scientific = bool(data.get("scientific", false))
	bus.paused = bool(data.get("paused", false))
	bus.enabled = bool(data.get("modulation_enabled", true))
	mod_depth = clampf(float(data.get("mod_depth", 1.0)), 0, 2)
	mod_frequency = clampf(float(data.get("mod_frequency", 0.08)), 0, 2)
	mod_waveform = str(data.get("mod_waveform", "sine"))
	replay_enabled = bool(data.get("replay_enabled", false))
	preset_index = clampi(int(data.get("preset_index", preset_index)), 0, presets.size() - 1)
	ui.preset_picker.select(preset_index)
	ui.subtitle_label.text = str(presets[preset_index].description).to_upper()
	_rebuild_modulation()
	matter.restore(bus,matter_data)
	ecology.restore_authored(data.ecology)
	_spatial_requested = ecology.simulation_enabled
	set_workspace(str(data.workspace), false, false)
	_refresh_target_availability()
	_applying_composition = false
	if not saved_patch.is_empty():
		if not install_synth_patch(saved_patch):
			ui.show_message("Scene patch could not bind: " + synth_error, 8)
			return false
		bus.enabled = bool(data.get("modulation_enabled", true))
	_sync_ui()
	if is_instance_valid(synth_panel): synth_panel.refresh()
	ui.show_message("Composition restored · exact source IDs · authored histories restarted")
	return true

func _save_json(path: String, content: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		ui.show_message("Could not write " + path, 6)
		return
	file.store_string(JSON.stringify(content, "\t"))
	ui.show_message("Saved " + path.get_file() + " · " + OS.get_user_data_dir(), 8)

func _capture(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("CAPTURE_UNAVAILABLE headless mode does not render")
		return
	await RenderingServer.frame_post_draw
	var screenshot: Image = get_viewport().get_texture().get_image()
	var error: Error = screenshot.save_png(path)
	print("XENOVECTION_CAPTURE ", path, " result=", error)
	if error == OK: ui.show_message("Saved " + path.get_file())
	if _args.has("exit-after-capture"):
		get_tree().quit(0 if error == OK else 1)

func _load_build_info() -> void:
	if FileAccess.file_exists("res://build_info.json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://build_info.json"))
		if parsed is Dictionary: _build = parsed

static func _read_arguments() -> Dictionary:
	var result: Dictionary = {}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--"):
			var pair: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
			result[pair[0]] = pair[1] if pair.size() == 2 else true
	return result

static func _encode(value: Variant) -> Variant:
	if value is Vector2: return {"_type": "v2", "value": [value.x, value.y]}
	if value is Vector3: return {"_type": "v3", "value": [value.x, value.y, value.z]}
	if value is Color: return {"_type": "color", "value": [value.r, value.g, value.b, value.a]}
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[key] = _encode(value[key])
		return result
	if value is Array:
		var result: Array = []
		for element in value: result.append(_encode(element))
		return result
	return value

static func _decode(value: Variant) -> Variant:
	if value is Dictionary:
		var entries: Array = value.get("value", [])
		match str(value.get("_type", "")):
			"v2":
				if entries.size() == 2: return Vector2(float(entries[0]), float(entries[1]))
			"v3":
				if entries.size() == 3: return Vector3(float(entries[0]), float(entries[1]), float(entries[2]))
			"color":
				if entries.size() == 4: return Color(float(entries[0]), float(entries[1]), float(entries[2]), float(entries[3]))
		var result: Dictionary = {}
		for key in value: result[key] = _decode(value[key])
		return result
	if value is Array:
		var result: Array = []
		for element in value: result.append(_decode(element))
		return result
	return value
