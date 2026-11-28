extends Control
## An additive, planar artificial-life workspace within the same application.
const World = preload("res://ecology/world.gd")
const Bus = preload("res://core/modulation_bus.gd")
const Recorder = preload("res://diagnostics/frame_recorder.gd")
const COLOURS = [Color(0.53, 0.95, 0.71), Color(0.35, 0.77, 1.0), Color(0.93, 0.49, 0.76), Color(1.0, 0.72, 0.36)]
const SAVE_PATH = "user://ecosystem-configuration.json"
var world = World.new()
var bus = Bus.new()
var recorder = Recorder.new()
var panel: PanelContainer
var title_label: Label
var stats_label: Label
var inspector: Label
var message: Label
var picker: OptionButton
var tools: OptionButton
var family: OptionButton
var field_picker: OptionButton
var quality_picker: OptionButton
var seed_box: SpinBox
var pause_button: Button
var interaction_button: CheckButton
var reproduction_button: CheckButton
var mod_button: CheckButton
var sliders: Dictionary = {}
var paused: bool = false
var syncing: bool = false
var accum: float = 0.0
var dropped_steps: int = 0
var selected: int = -1
var field_mode: int = 1
var stride: int = 1
var isolated: int = -1
var frame: int = 0
var info_elapsed: float = 0.0
var args: Dictionary = {}
var automated: bool = false
var target_steps: int = 0
var profile_frames: int = 0
var completed: bool = false
var started_usec: int = 0
var build: Dictionary = {}
var last_render_usec: int = 0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var pair = arg.trim_prefix("--").split("=", true, 1)
			args[pair[0]] = pair[1] if pair.size() == 2 else true
	var initial: int = clampi(int(str(args.get("ecosystem", "0"))), 0, 5)
	world.reset(World.initial_config(initial, 7301))
	_setup_bus()
	_build_ui()
	_sync_controls()
	recorder.setup(get_viewport())
	var info = JSON.parse_string(FileAccess.get_file_as_string("res://build_info.json")) if FileAccess.file_exists("res://build_info.json") else null
	if info is Dictionary:
		build = info
	automated = args.has("eco-steps")
	target_steps = clampi(int(str(args.get("eco-steps", "0"))), 1, 36000) if automated else 0
	profile_frames = clampi(int(str(args.get("eco-frames", "0"))), 0, 1800)
	if args.has("eco-clean"):
		panel.hide()
	if args.has("eco-no-interactions"):
		world.config.interactions = false
		_sync_controls()
	started_usec = Time.get_ticks_usec()
	queue_redraw()
	print("XENOVECTION_ECOLOGY_READY ", World.NAMES[initial])

func _setup_bus() -> void:
	bus = Bus.new()
	world.register_targets(bus)
	if bool(world.config.get("lfo", false)):
		bus.register_source("eco_lfo", {"type": "lfo", "clock": "filament", "waveform": "sine", "frequency": 0.08})
		bus.add_route({"target": "eco.growth", "source": "eco_lfo", "amplitude": 0.4})
		bus.add_route({"target": "eco.excitation", "source": "eco_lfo", "amplitude": 0.35})

func _label(text_value: String, parent: Control, font_size: int = 13) -> Label:
	var l = Label.new()
	l.text = text_value
	l.add_theme_font_size_override("font_size", font_size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l

func _button(text_value: String, parent: Control, action: Callable) -> Button:
	var b = Button.new()
	b.text = text_value
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func _option(values: Array, parent: Control) -> OptionButton:
	var item = OptionButton.new()
	item.focus_mode = Control.FOCUS_NONE
	for value in values:
		item.add_item(str(value))
	parent.add_child(item)
	return item

func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -310
	panel.offset_right = -12
	panel.offset_top = 12
	panel.offset_bottom = -12
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.06, 0.085, 0.97)
	style.border_color = Color(0.22, 0.37, 0.39)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var rail = VBoxContainer.new()
	rail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rail.add_theme_constant_override("separation", 7)
	scroll.add_child(rail)
	title_label = _label("E C O S Y S T E M", rail, 20)
	title_label.add_theme_color_override("font_color", Color(0.52, 0.94, 0.84))
	_label("ARTIFICIAL LIFE / PLANAR LABORATORY", rail, 11)
	picker = _option(World.NAMES, rail)
	picker.item_selected.connect(_choose)
	var row = HBoxContainer.new()
	rail.add_child(row)
	pause_button = _button("Pause", row, _toggle_pause)
	_button("Step", row, func(): 
		paused = true
		_tick()
		_sync_controls()
		queue_redraw())
	_button("Reset", row, _reset)
	_label("Seed (apply with Reset)", rail)
	seed_box = SpinBox.new()
	seed_box.min_value = 0
	seed_box.max_value = 2147483647
	seed_box.step = 1
	rail.add_child(seed_box)
	interaction_button = CheckButton.new()
	interaction_button.text = "Shared ecological interactions"
	rail.add_child(interaction_button)
	interaction_button.toggled.connect(func(v): 
		if not syncing: world.config.interactions = v)
	reproduction_button = CheckButton.new()
	reproduction_button.text = "Birth / death / inheritance"
	rail.add_child(reproduction_button)
	reproduction_button.toggled.connect(func(v):
		if not syncing: world.config.reproduce = v)
	mod_button = CheckButton.new()
	mod_button.text = "Slow growth/excitation modulation"
	rail.add_child(mod_button)
	mod_button.toggled.connect(func(v):
		if not syncing:
			world.config.lfo = v
			_setup_bus())
	for key in World.BOUNDS:
		var bound: Vector2 = World.BOUNDS[key]
		var caption = _label(str(key).capitalize(), rail, 12)
		var slider = HSlider.new()
		slider.min_value = bound.x
		slider.max_value = bound.y
		slider.step = 0.01
		slider.custom_minimum_size.y = 18
		slider.focus_mode = Control.FOCUS_NONE
		rail.add_child(slider)
		sliders[key] = [slider, caption]
		slider.value_changed.connect(_parameter.bind(str(key)))
	_label("Spatial intervention", rail, 14)
	tools = _option(["Inspect", "Plant", "Resource source", "Resource sink", "Excite", "Inhibit"], rail)
	family = _option(World.FAMILIES, rail)
	_label("Click within the world. Source, sink and plant edits are recorded in the initial configuration; excitation is transient.", rail, 11)
	field_picker = _option(["No field", "Subtle resource", "Resource heat map", "Signal heat map"], rail)
	field_picker.select(1)
	field_picker.item_selected.connect(func(v):
		field_mode = v
		queue_redraw())
	quality_picker = _option(["Full detail", "Half trail/reef detail", "Quarter trail/reef detail"], rail)
	quality_picker.item_selected.connect(func(v):
		stride = [1, 2, 4][v]
		queue_redraw())
	_button("Isolate / reveal selected family", rail, _isolate)
	_button("Save initial configuration", rail, _save)
	_button("Recall initial configuration", rail, _load)
	_button("Export observation trace", rail, _export)
	_button("Return to source instrument", rail, func(): get_tree().change_scene_to_file("res://main.tscn"))
	stats_label = _label("", rail, 12)
	inspector = _label("No organism selected", rail, 12)
	message = _label("", rail, 12)

func _parameter(value: float, key: String) -> void:
	if syncing:
		return
	world.apply_parameter(key, value)
	bus.set_base("eco." + key, float(world.config.params[key]))
	sliders[key][1].text = "%s  %.2f" % [key.capitalize(), value]

func _sync_controls() -> void:
	syncing = true
	picker.select(int(world.config.preset))
	seed_box.value = int(world.config.seed)
	pause_button.text = "Resume" if paused else "Pause"
	interaction_button.set_pressed_no_signal(bool(world.config.interactions))
	reproduction_button.set_pressed_no_signal(bool(world.config.reproduce))
	mod_button.set_pressed_no_signal(bool(world.config.get("lfo", false)))
	for key in sliders:
		sliders[key][0].set_value_no_signal(float(world.config.params[key]))
		sliders[key][1].text = "%s  %.2f" % [key.capitalize(), float(world.config.params[key])]
	syncing = false

func _choose(index: int) -> void:
	world.reset(World.initial_config(index, int(seed_box.value)))
	_after_reset()

func _reset() -> void:
	var candidate: Dictionary = world.config.duplicate(true)
	candidate.seed = int(seed_box.value)
	world.reset(candidate)
	_after_reset()

func _after_reset() -> void:
	_setup_bus()
	selected = -1
	isolated = -1
	accum = 0.0
	dropped_steps = 0
	_sync_controls()
	_refresh_stats()
	queue_redraw()

func _toggle_pause() -> void:
	paused = not paused
	accum = 0.0
	pause_button.text = "Resume" if paused else "Pause"

func _tick() -> void:
	world.apply_effective(bus.advance(World.DT))
	world.step()

func _area() -> Rect2:
	var available = Vector2(maxf(100.0, size.x - (324.0 if panel.visible else 0.0) - 36.0), maxf(100.0, size.y - 90.0))
	var side = minf(available.x, available.y)
	return Rect2(Vector2(18, 62) + (available - Vector2.ONE * side) * 0.5, Vector2.ONE * side)

func _screen(p: Vector2, area: Rect2) -> Vector2:
	return area.position + p * area.size

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	var area = _area()
	if not area.has_point(event.position):
		return
	var p = (event.position - area.position) / area.size
	match tools.selected:
		0:
			var best: float = 0.075
			selected = -1
			for o in world.organisms:
				if isolated >= 0 and isolated != o.kind:
					continue
				var dist: float = p.distance_to(o.p)
				if dist < best:
					best = dist
					selected = o.id
		1: message.text = "Planted" if world.plant(family.selected, p) else "Plant limit reached"
		2: message.text = "Resource source added" if world.source_at(p, 1.0) else "Source limit reached"
		3: message.text = "Resource sink added" if world.source_at(p, -0.8) else "Source limit reached"
		4: world.perturb(p, 0.95)
		5: world.perturb(p, -0.95)
	_refresh_stats()
	queue_redraw()
	accept_event()

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_SPACE: _toggle_pause()
		KEY_R: _reset()
		KEY_F5: _save()
		KEY_F6: _load()
		KEY_F10: _export()
		KEY_TAB: panel.visible = not panel.visible
		KEY_ESCAPE:
			if not panel.visible:
				panel.show()
			else:
				get_tree().change_scene_to_file("res://main.tscn")
		_: return
	queue_redraw()
	get_viewport().set_input_as_handled()

func _isolate() -> void:
	if isolated >= 0:
		isolated = -1
	else:
		for o in world.organisms:
			if o.id == selected:
				isolated = int(o.kind)
				break
	queue_redraw()

func _save() -> void:
	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		message.text = "Configuration write failed"
		return
	var candidate: Dictionary = world.config.duplicate(true)
	candidate.seed = int(seed_box.value)
	f.store_string(JSON.stringify(candidate, "\t"))
	message.text = "Initial configuration saved; not live state"

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		message.text = "No saved configuration"
		return
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null or file.get_length() > 65536:
		message.text = "Configuration unreadable or exceeds 64 KiB"
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not world.reset(parsed):
		message.text = "Invalid configuration; current ecology preserved"
		return
	_after_reset()
	message.text = "Recalled authored initial conditions"

func _export() -> void:
	var error = _write_receipt("user://ecosystem-observations.json")
	message.text = "Observation trace exported" if error == OK else "Export failed"

func _write_receipt(path: String) -> Error:
	return recorder.save(path, {"ecology_schema": "xenovection.ecology.observations.v1", "build": build, "configuration": world.config, "simulation": world.metrics(), "history": world.history, "digest": world.digest(), "spatial_digest": world.spatial_digest(), "fixed_step_hz": 30, "field_step_hz": 10, "growth_step_hz": 5, "dropped_catchup_steps": dropped_steps, "render_detail_stride": stride, "canvas_render_scope": "Planar CanvasItem geometry; no 3D primitive count claim", "mode": "fixed_steps" if automated else "wall_clock", "draw_submission_us_last": last_render_usec})

func _refresh_stats() -> void:
	var m: Dictionary = world.metrics()
	stats_label.text = "Tick %d · %d organisms · %d lineages\n%d births / %d deaths · %d branches\nResource %.3f · Signal %.3f\nPhase order %.3f · %d interactions\n%d candidates · sim %.2f ms\nField %.2f ms · growth %.2f ms\nDropped catch-up %d" % [m.tick, m.population, m.lineages, m.births, m.deaths, m.segments, m.resource_mean, m.signal_mean, m.synchrony, m.events, m.queries, float(m.step_us) / 1000.0, float(m.field_us) / 1000.0, float(m.growth_us) / 1000.0, dropped_steps]
	inspector.text = "No organism selected"
	for o in world.organisms:
		if o.id == selected:
			inspector.text = "%s #%d · lineage %d\nParent %d · generation %d\nAge %.1fs · energy %.3f\nTrait %.3f · branches %d" % [World.FAMILIES[o.kind], o.id, o.lineage, o.parent, o.generation, float(o.age) * World.DT, o.energy, o.trait, int(o.segments.size() / 2)]
			break

func _process(delta: float) -> void:
	if completed:
		return
	var start = Time.get_ticks_usec()
	frame += 1
	if automated:
		for j in range(mini(4, target_steps - world.tick)):
			_tick()
	else:
		if not paused:
			accum += minf(delta, 0.25)
			var steps = 0
			while accum >= World.DT and steps < 4:
				_tick()
				accum -= World.DT
				steps += 1
			if accum >= World.DT:
				dropped_steps += int(accum / World.DT)
				accum = fposmod(accum, World.DT)
	info_elapsed += delta
	if info_elapsed > 0.3:
		info_elapsed = 0.0
		_refresh_stats()
	queue_redraw()
	if frame == 30:
		recorder.reset()
	elif frame > 30:
		recorder.sample(Time.get_ticks_usec() - start)
	if (automated and world.tick >= target_steps) or (profile_frames > 0 and not automated and frame >= 30 + profile_frames):
		completed = true
		_finish()

func _finish() -> void:
	var ok = true
	if args.has("eco-capture"):
		if DisplayServer.get_name() == "headless":
			ok = false
		else:
			await RenderingServer.frame_post_draw
			ok = get_viewport().get_texture().get_image().save_png(str(args["eco-capture"])) == OK
	if args.has("eco-profile"):
		ok = _write_receipt(str(args["eco-profile"])) == OK and ok
	print("XENOVECTION_ECOLOGY_FINISHED ", JSON.stringify(world.metrics()))
	get_tree().quit(0 if ok else 1)

func _draw() -> void:
	if not is_instance_valid(panel):
		return
	var start = Time.get_ticks_usec()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.006, 0.015, 0.026))
	var area = _area()
	draw_rect(area, Color(0.009, 0.025, 0.036))
	var font = ThemeDB.fallback_font
	draw_string(font, Vector2(22, 28), "X E N O V E C T I O N   /   " + World.NAMES[int(world.config.preset)].to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.55, 0.92, 0.88))
	draw_string(font, Vector2(22, 49), "SHARED FIELDS   ·   %d ORGANISMS   ·   t %.1f s" % [world.organisms.size(), world.tick * World.DT], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.47, 0.63, 0.69))
	if field_mode > 0:
		var grid = world.signal_field if field_mode == 3 else world.resource
		var cell_size = area.size / World.N
		for y in range(World.N):
			for x in range(World.N):
				var v: float = grid[y * World.N + x]
				var colour = Color(0.12, 0.60, 0.50, v * 0.09)
				if field_mode == 2:
					colour = Color(0.12 + v * 0.45, 0.35 + v * 0.45, 0.25, 0.12 + v * 0.5)
				elif field_mode == 3:
					colour = Color(0.60 + v * 0.35, 0.18 + v * 0.35, 0.42, v * 0.8)
				draw_rect(Rect2(area.position + Vector2(x, y) * cell_size, cell_size + Vector2.ONE * 0.5), colour)
	for src in world.config.sources:
		var p = _screen(Vector2(src[0], src[1]), area)
		var col = Color(0.37, 0.8, 0.67, 0.35) if src[2] > 0 else Color(0.95, 0.45, 0.41, 0.35)
		draw_arc(p, 7.0, 0.0, TAU, 24, col, 1.0, true)
	for o in world.organisms:
		if isolated >= 0 and o.kind != isolated:
			continue
		var p = _screen(o.p, area)
		var col: Color = COLOURS[o.kind].lerp(Color(0.95, 0.99, 1.0), clampf(float(o.trait) - 0.5, 0.0, 1.0) * 0.3)
		var brightness = clampf(0.28 + float(o.energy) * 0.68, 0.2, 0.96)
		brightness *= clampf(float(world.effective.material), 0.15, 1.4)
		col.a = clampf(brightness, 0.08, 1.0)
		match int(o.kind):
			0:
				var points = PackedVector2Array()
				for q in o.segments:
					points.append(_screen(q, area))
				if points.size() >= 2:
					draw_multiline(points, Color(col.r, col.g, col.b, col.a * 0.22), 2.3, true)
					draw_multiline(points, col, 0.85, true)
				for tip in o.tips:
					draw_circle(_screen(tip, area), 1.6, col, true, -1.0, true)
				draw_circle(p, 2.0, col, true, -1.0, true)
			1:
				var trail = PackedVector2Array()
				for j in range(0, o.trail.size(), stride):
					trail.append(_screen(o.trail[j], area))
				trail.append(p)
				if trail.size() >= 2:
					draw_polyline(trail, Color(col.r, col.g, col.b, col.a * 0.32), 2.5, true)
					draw_polyline(trail, col, 0.8, true)
				draw_circle(p, 1.8, col, true, -1.0, true)
				var v: Vector2 = o.v
				draw_line(p, p + v * 43.0, col, 0.8, true)
			2:
				var radius: float = float(o.radius) * area.size.x
				draw_circle(p, radius, Color(col.r, col.g, col.b, col.a * 0.065), true, -1.0, true)
				var arcs = maxi(12, int(40.0 / stride))
				for j in range(3):
					var rad = radius * (1.0 - j * 0.22)
					var a: float = float(o.phase) * 0.18 + float(j)
					draw_arc(p, rad, a, a + TAU * 0.86, arcs, Color(col.r, col.g, col.b, col.a * (0.6 - j * 0.12)), 0.85, true)
				for j in range(0, 12, stride):
					var a = float(j) * TAU / 12.0 + float(o.phase) * 0.2
					var hole = p + Vector2.from_angle(a) * radius * 0.67
					draw_arc(hole, maxf(1.0, radius * 0.105), 0.0, TAU, 10, Color(col.r, col.g, col.b, col.a * 0.6), 0.75, true)
			3:
				var excitation: float = float(o.excited)
				var radius = 3.0 + excitation * 13.0
				draw_circle(p, radius, Color(col.r, col.g, col.b, 0.07 + excitation * 0.23), true, -1.0, true)
				draw_arc(p, radius, 0.0, TAU, 20, Color(col.r, col.g, col.b, 0.18 + excitation * 0.72), 1.0, true)
				draw_circle(p, 1.5 + excitation, col, true, -1.0, true)
		if selected == o.id:
			draw_arc(p, 11.0, 0.0, TAU, 30, Color.WHITE, 1.0, true)
	draw_rect(area, Color(0.25, 0.42, 0.48, 0.7), false, 1.0)
	last_render_usec = Time.get_ticks_usec() - start
