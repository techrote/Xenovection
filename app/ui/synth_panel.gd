extends VBoxContainer
## Matrix authoring and live performance. All structural edits validate atomically.
const Graph = preload("res://core/synth_graph.gd")
const Examples = preload("res://core/synth_examples.gd")
const Catalogue = preload("res://convergence/composition_catalogue.gd")
const SLOT := "user://xenovection-patch.json"
const HISTORY_LIMIT := 32

class XYPad extends Control:
	signal gesture(x: float, y: float)
	var point := Vector2.ZERO
	var dragging := false
	var active := false

	func _ready() -> void:
		custom_minimum_size = Vector2(180, 170)
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.055, 0.08))
		for i in range(1, 8):
			var fraction := float(i) / 8.0
			var ink := Color(0.19, 0.38, 0.43, 0.5) if i == 4 else Color(0.1, 0.2, 0.24, 0.6)
			draw_line(Vector2(size.x * fraction, 0), Vector2(size.x * fraction, size.y), ink, 1.0)
			draw_line(Vector2(0, size.y * fraction), Vector2(size.x, size.y * fraction), ink, 1.0)
		var cursor := Vector2((point.x + 1.0) * 0.5 * size.x, (1.0 - point.y) * 0.5 * size.y)
		draw_line(Vector2(cursor.x, 0), Vector2(cursor.x, size.y), Color(0.4, 0.9, 0.85, 0.6))
		draw_line(Vector2(0, cursor.y), Vector2(size.x, cursor.y), Color(0.4, 0.9, 0.85, 0.6))
		draw_circle(cursor, 7.0, Color(0.96, 0.69, 0.46) if active else Color.GRAY)

	func set_point(value: Vector2) -> void:
		point = value.clamp(-Vector2.ONE, Vector2.ONE)
		queue_redraw()

	func _move(location: Vector2) -> void:
		set_point(Vector2(2.0 * location.x / maxf(size.x, 1.0) - 1.0, 1.0 - 2.0 * location.y / maxf(size.y, 1.0)))
		gesture.emit(point.x, point.y)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			dragging = active and event.pressed
			if dragging:
				_move(event.position)
			accept_event()
		elif event is InputEventMouseMotion and dragging:
			if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
				dragging = false
			else:
				_move(event.position)
			accept_event()


var host
var examples: Array = Examples.all()
var undo_stack: Array = []
var redo_stack: Array = []
var author: VBoxContainer
var file_controls: VBoxContainer
var edit_controls: HBoxContainer
var perform: VBoxContainer
var status: Label
var live: Label
var example_picker: OptionButton
var source_picker: OptionButton
var source_id := ""
var source_id_label: Label
var kind_picker: OptionButton
var clock_picker: OptionButton
var input_a: OptionButton
var input_b: OptionButton
var input_c: OptionButton
var rate: SpinBox
var phase: SpinBox
var value: SpinBox
var param: SpinBox
var seed: SpinBox
var steps: LineEdit
var route_picker: OptionButton
var route_id := ""
var route_id_label: Label
var route_source: OptionButton
var target_search: LineEdit
var target_category: OptionButton
var target_picker: OptionButton
var operation: OptionButton
var amplitude: SpinBox
var offset: SpinBox
var mask: SpinBox
var bypass: CheckButton
var solo: Button
var perform_controls: VBoxContainer
var pad: XYPad
var manual_controls: Dictionary = {}
var dialog: FileDialog
var importing := false
var _elapsed := 0.0


func setup(application) -> void:
	host = application
	name = "ModularInstrument"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 7)
	_label(self, "MODULAR SYNTHESIS", true)
	var mode := _row(self)
	_button(mode, "Patch", func(): _mode(false))
	_button(mode, "Perform", func(): _mode(true))
	example_picker = _option(self)
	for example in examples:
		example_picker.add_item(example.title)
	var recall := _row(self)
	_button(recall, "Recall example", func(): _edit(examples[example_picker.selected].patch, true))
	_button(recall, "Blank", func(): _edit(Graph.blank(host.preset_index, Catalogue.stable_id(host.presets[host.preset_index]))))
	file_controls = VBoxContainer.new()
	add_child(file_controls)
	var file_row := _row(file_controls)
	_button(file_row, "Save", func(): _save(SLOT))
	_button(file_row, "Load", func(): _load(SLOT))
	_button(file_row, "Morph", func(): _load(SLOT, true))
	var transfer := _row(file_controls)
	_button(transfer, "Import…", func(): _file(true))
	_button(transfer, "Export…", func(): _file(false))
	_button(file_controls, "Recover previous save", func(): _load(SLOT + ".bak"))
	status = _label(self, "Recall an example or create a blank patch.")
	live = _label(self, "")
	edit_controls = _row(self)
	_button(edit_controls, "Undo", _undo)
	_button(edit_controls, "Redo", _redo)
	_button(edit_controls, "Stop", func():
		host.stop_synth()
		refresh()
	)
	author = VBoxContainer.new()
	add_child(author)
	_build_author()
	perform = VBoxContainer.new()
	add_child(perform)
	perform_controls = VBoxContainer.new()
	perform.add_child(perform_controls)
	dialog = FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.json ; Xenovection patch"])
	dialog.file_selected.connect(func(path: String):
		if importing:
			_load(path)
		else:
			_save(path)
	)
	add_child(dialog)
	_mode(false)
	refresh()


func _row(parent: Control) -> HBoxContainer:
	var result := HBoxContainer.new()
	parent.add_child(result)
	return result


func _label(parent: Control, label_text: String, heading: bool = false) -> Label:
	var result := Label.new()
	result.text = label_text
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if heading:
		result.add_theme_color_override("font_color", Color(0.4, 0.88, 0.83))
	parent.add_child(result)
	return result


func _button(parent: Control, label_text: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = label_text
	result.focus_mode = Control.FOCUS_NONE
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.pressed.connect(callback)
	parent.add_child(result)
	return result


func _option(parent: Control) -> OptionButton:
	var result := OptionButton.new()
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.fit_to_longest_item = false
	result.clip_text = true
	parent.add_child(result)
	return result


func _number(parent: Control, label_text: String, minimum: float, maximum: float, step: float) -> SpinBox:
	var row := _row(parent)
	var label := _label(row, label_text)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var result := SpinBox.new()
	result.min_value = minimum
	result.max_value = maximum
	result.step = step
	result.custom_minimum_size.x = 100
	row.add_child(result)
	return result


func _items(picker: OptionButton, choices: Array, selected: String = "", none: bool = false) -> void:
	picker.clear()
	if none:
		picker.add_item("— unassigned —")
		picker.set_item_metadata(0, "")
	for choice in choices:
		picker.add_item(str(choice))
		picker.set_item_metadata(picker.item_count - 1, str(choice))
	if picker.item_count > 0:
		picker.select(0)
		for i in range(picker.item_count):
			if picker.get_item_metadata(i) == selected:
				picker.select(i)
				break


func _selected(picker: OptionButton) -> String:
	return str(picker.get_item_metadata(picker.selected)) if picker.selected >= 0 else ""


func _mode(performance: bool) -> void:
	author.visible = not performance
	file_controls.visible = not performance
	edit_controls.visible = not performance
	perform.visible = performance


func _data() -> Dictionary:
	var data: Dictionary = host.synth.snapshot(host.bus) if not host.synth.patch.is_empty() else Graph.blank(host.preset_index)
	data.preset_id = Catalogue.stable_id(host.presets[host.preset_index])
	return data


func _edit(candidate: Dictionary, recall: bool = false, morph: bool = false) -> bool:
	var before := _data()
	if not host.install_synth_patch(candidate, recall, morph):
		status.text = host.synth_error
		return false
	undo_stack.append(before)
	if undo_stack.size() > HISTORY_LIMIT:
		undo_stack.pop_front()
	redo_stack.clear()
	status.text = host.synth_error if not host.synth_error.is_empty() else "Patch updated."
	refresh()
	return true


func _undo() -> void:
	if undo_stack.is_empty():
		return
	var before := _data()
	var candidate: Dictionary = undo_stack.back()
	if host.install_synth_patch(candidate, int(candidate.preset) != host.preset_index):
		undo_stack.pop_back()
		redo_stack.append(before)
		status.text = "Patch edit undone."
		refresh()
	else:
		status.text = host.synth_error


func _redo() -> void:
	if redo_stack.is_empty():
		return
	var before := _data()
	var candidate: Dictionary = redo_stack.back()
	if host.install_synth_patch(candidate, int(candidate.preset) != host.preset_index):
		redo_stack.pop_back()
		undo_stack.append(before)
		status.text = "Patch edit restored."
		refresh()
	else:
		status.text = host.synth_error


func _save(path: String) -> void:
	if host.synth.patch.is_empty():
		status.text = "Create a patch first."
		return
	status.text = "Saved " + path.get_file() if Graph.write_patch(path, _data()) else "Patch save refused."


func _load(path: String, morph: bool = false) -> void:
	var candidate = Graph.read_patch(path)
	if not candidate is Dictionary:
		status.text = "Invalid or missing patch; current patch retained."
		return
	_edit(candidate, true, morph)


func _file(reading: bool) -> void:
	importing = reading
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE if reading else FileDialog.FILE_MODE_SAVE_FILE
	dialog.current_file = "xenovection-patch.json"
	dialog.popup_centered_ratio(0.7)


func _build_author() -> void:
	_label(author, "COMPONENTS", true)
	source_picker = _option(author)
	source_picker.item_selected.connect(func(_index: int): _show_source(_selected(source_picker)))
	_button(author, "New component", func(): _show_source(""))
	source_id_label = _label(author, "")
	kind_picker = _option(author)
	_items(kind_picker, Graph.KINDS)
	clock_picker = _option(author)
	_items(clock_picker, Graph.CLOCKS)
	rate = _number(author, "Rate / duration", -100, 100, 0.001)
	phase = _number(author, "Phase · cycles", -1000, 1000, 0.01)
	value = _number(author, "Value / offset", -16, 16, 0.01)
	param = _number(author, "Shape / gain / τ", -16, 16, 0.01)
	seed = _number(author, "Seed", 0, 2147483647, 1)
	_label(author, "Input A")
	input_a = _option(author)
	_label(author, "Input B")
	input_b = _option(author)
	_label(author, "Input C")
	input_c = _option(author)
	_label(author, "Sequencer steps (comma-separated)")
	steps = LineEdit.new()
	steps.max_length = 512
	author.add_child(steps)
	var source_actions := _row(author)
	_button(source_actions, "Apply component", _apply_source)
	_button(source_actions, "Delete", _remove_source)
	_label(author, "ROUTES", true)
	route_picker = _option(author)
	route_picker.item_selected.connect(func(_index: int): _show_route(_selected(route_picker)))
	_button(author, "New route", func(): _show_route(""))
	route_id_label = _label(author, "")
	_label(author, "Signal")
	route_source = _option(author)
	_label(author, "Target domain")
	target_category = _option(author)
	_items(target_category, ["all", "filament", "optical", "matter", "eco"])
	target_category.item_selected.connect(func(_index: int): _targets(_selected(target_picker)))
	_label(author, "Search continuous targets")
	target_search = LineEdit.new()
	target_search.placeholder_text = "e.g. displacement"
	author.add_child(target_search)
	target_picker = _option(author)
	target_search.text_changed.connect(func(_text: String): _targets(_selected(target_picker)))
	operation = _option(author)
	_items(operation, ["add", "multiply"])
	amplitude = _number(author, "Signed depth", -1000, 1000, 0.001)
	offset = _number(author, "Offset", -1000, 1000, 0.001)
	mask = _number(author, "Route gain", 0, 1, 0.01)
	bypass = CheckButton.new()
	bypass.text = "Bypass"
	author.add_child(bypass)
	var route_actions := _row(author)
	_button(route_actions, "Apply route", _apply_route)
	_button(route_actions, "Delete", _remove_route)
	solo = _button(author, "Solo / clear solo", _solo)
	_label(author, "Patch undo restores authored graph edits; it does not reverse simulation. Discrete topology is excluded. Target limits clamp the result.")


func _next_id(items: Array, prefix: String) -> String:
	var used: Array = []
	for item in items:
		used.append(item.id)
	for i in range(1, 10000):
		var id := prefix + str(i)
		if not id in used:
			return id
	return prefix + "overflow"


func _find(items: Array, id: String) -> Dictionary:
	for item in items:
		if item.id == id:
			return item
	return {}


func _ids(items: Array) -> Array:
	var result: Array = []
	for item in items:
		result.append(item.id)
	return result


func _show_source(id: String) -> void:
	var data := _data()
	var n := _find(data.sources, id)
	if n.is_empty():
		n = Graph.source_defaults(_next_id(data.sources, "source"))
	source_id = n.id
	source_id_label.text = "Component: " + source_id
	_items(kind_picker, Graph.KINDS, n.kind)
	_items(clock_picker, Graph.CLOCKS, n.clock)
	rate.value = n.rate
	phase.value = n.phase
	value.value = n.value
	param.value = n.param
	seed.value = n.seed
	var ids := _ids(data.sources)
	if not source_id in ids:
		ids.append(source_id)
	_items(input_a, ids, n.a, true)
	_items(input_b, ids, n.b, true)
	_items(input_c, ids, n.c, true)
	var parts := PackedStringArray()
	for step in n.steps:
		parts.append(str(step))
	steps.text = ", ".join(parts)


func _apply_source() -> void:
	var data := _data()
	var sequence: Array = []
	for token in steps.text.split(","):
		var cleaned := token.strip_edges()
		if not cleaned.is_valid_float():
			status.text = "Invalid sequencer number."
			return
		sequence.append(cleaned.to_float())
	var n := Graph.source_defaults(source_id, _selected(kind_picker))
	n.merge({"clock": _selected(clock_picker), "rate": rate.value, "phase": phase.value,
		"value": value.value, "param": param.value, "seed": int(seed.value),
		"a": _selected(input_a), "b": _selected(input_b), "c": _selected(input_c), "steps": sequence}, true)
	var updated := false
	for i in range(data.sources.size()):
		if data.sources[i].id == source_id:
			data.sources[i] = n
			updated = true
			break
	if not updated:
		data.sources.append(n)
	_edit(data)


func _remove_source() -> void:
	var data := _data()
	for i in range(data.sources.size()):
		if data.sources[i].id == source_id:
			data.sources.remove_at(i)
			for axis in range(2):
				if data.xy[axis] == source_id:
					data.xy[axis] = ""
			_edit(data)
			return


func _targets(selected: String = "") -> void:
	var catalogue := Graph.target_catalogue(host.bus)
	var complete := Graph.target_catalogue(host.bus, true)
	var choices: Array = []
	var query := target_search.text.to_lower()
	var category := _selected(target_category) if is_instance_valid(target_category) else "all"
	for id in catalogue:
		# An empty search is the normal route-authoring state and must expose
		# the complete continuous-target catalogue. GDScript's empty-string
		# containment test is not a reliable substitute for this explicit case.
		if (category == "all" or str(catalogue[id].category) == category) and (query.is_empty() or query in str(id).to_lower()):
			choices.append(id)
	# A recalled route into an inactive domain remains visibly selected; never
	# replace its destination with the first unrelated active target.
	if query.is_empty() and category == "all" and complete.has(selected) and not selected in choices:
		choices.append(selected)
	choices.sort()
	_items(target_picker, choices, selected)
	for i in range(target_picker.item_count):
		var id := str(target_picker.get_item_metadata(i))
		if complete.has(id) and not bool(complete[id].available):
			target_picker.set_item_text(i, id + " [inactive]")


func _show_route(id: String) -> void:
	var data := _data()
	var route := _find(data.routes, id)
	if route.is_empty():
		route = {"id": _next_id(data.routes, "route"), "source": "", "target": "", "operation": "add", "amplitude": 0.1, "offset": 0.0, "mask": 1.0, "enabled": true}
	route_id = route.id
	route_id_label.text = "Route: " + route_id
	_items(route_source, _ids(data.sources), route.source)
	_items(target_category, ["all", "filament", "optical", "matter", "eco"], "all")
	target_search.text = ""
	_targets(route.target)
	_items(operation, ["add", "multiply"], route.operation)
	amplitude.value = route.amplitude
	offset.value = route.offset
	mask.value = route.mask
	bypass.button_pressed = not route.enabled


func _apply_route() -> void:
	var data := _data()
	var route := {"id": route_id, "source": _selected(route_source), "target": _selected(target_picker),
		"operation": _selected(operation), "amplitude": amplitude.value, "offset": offset.value, "mask": mask.value, "enabled": not bypass.button_pressed}
	var updated := false
	for i in range(data.routes.size()):
		if data.routes[i].id == route_id:
			data.routes[i] = route
			updated = true
			break
	if not updated:
		data.routes.append(route)
	_edit(data)


func _remove_route() -> void:
	var data := _data()
	for i in range(data.routes.size()):
		if data.routes[i].id == route_id:
			data.routes.remove_at(i)
			_edit(data)
			return


func _solo() -> void:
	if not host.synth.route_by_id.has(route_id):
		return
	host.synth.solo_id = "" if host.synth.solo_id == route_id else route_id
	status.text = "Solo: " + host.synth.solo_id if not host.synth.solo_id.is_empty() else "All patch routes."


func refresh() -> void:
	if not is_instance_valid(source_picker):
		return
	var data := _data()
	var source_ids := _ids(data.sources)
	var route_ids := _ids(data.routes)
	_items(source_picker, source_ids, source_id)
	_show_source(_selected(source_picker))
	_items(route_picker, route_ids, route_id)
	_show_route(_selected(route_picker))
	_build_performance(data)


func _set_manual(id: String, number: float) -> void:
	if host.synth.set_manual(id, number) and manual_controls.has(id):
		manual_controls[id].set_value_no_signal(number)


func _assign_xy(axis: int, id: String) -> void:
	var data := _data()
	data.xy[axis] = id
	if not _edit(data):
		refresh()


func _build_performance(data: Dictionary) -> void:
	for child in perform_controls.get_children():
		perform_controls.remove_child(child)
		child.queue_free()
	manual_controls.clear()
	_label(perform_controls, "PLAY · MANUAL MODULATION", true)
	var manual_ids: Array = []
	for n in data.sources:
		if n.kind == "manual":
			manual_ids.append(n.id)
			_label(perform_controls, n.id)
			var slider := HSlider.new()
			slider.min_value = -1.0
			slider.max_value = 1.0
			slider.step = 0.002
			slider.value = clampf(float(n.value), -1.0, 1.0)
			slider.focus_mode = Control.FOCUS_NONE
			slider.custom_minimum_size.y = 22
			perform_controls.add_child(slider)
			manual_controls[n.id] = slider
			var id: String = n.id
			slider.value_changed.connect(func(number: float): _set_manual(id, number))
		elif n.kind == "envelope":
			var id: String = n.id
			_button(perform_controls, "Trigger · " + id, func(): host.synth.trigger(id))
	var xy_title := _label(perform_controls, "XY PERFORMANCE SURFACE", true)
	_label(perform_controls, "X → manual source")
	var x := _option(perform_controls)
	_items(x, manual_ids, data.xy[0], true)
	x.item_selected.connect(func(_index: int): _assign_xy(0, _selected(x)))
	_label(perform_controls, "Y → manual source")
	var y := _option(perform_controls)
	_items(y, manual_ids, data.xy[1], true)
	y.item_selected.connect(func(_index: int): _assign_xy(1, _selected(y)))
	pad = XYPad.new()
	perform_controls.add_child(pad)
	perform_controls.move_child(xy_title, 0)
	perform_controls.move_child(pad, 1)
	pad.active = not data.xy[0].is_empty() or not data.xy[1].is_empty()
	pad.gesture.connect(func(xx: float, yy: float):
		if not host.synth.patch.is_empty():
			_set_manual(host.synth.patch.xy[0], xx)
			_set_manual(host.synth.patch.xy[1], yy)
	)
	_label(perform_controls, "TRANSPORT", true)
	var transport := _row(perform_controls)
	_button(transport, "Pause / play", func(): host.handle_action("pause"))
	_button(transport, "Reset", func(): host.handle_action("reset_time"))
	var bpm := _number(perform_controls, "Tempo BPM", 20, 300, 0.5)
	bpm.value = data.bpm
	_button(perform_controls, "Apply tempo", func():
		var candidate := _data()
		candidate.bpm = bpm.value
		_edit(candidate)
	)
	for clock in Graph.CLOCKS:
		if clock == "beat":
			continue
		var row := _row(perform_controls)
		var title := _label(row, clock)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var speed := SpinBox.new()
		speed.min_value = -8
		speed.max_value = 8
		speed.step = 0.1
		speed.value = host.bus.clocks[clock].rate
		speed.custom_minimum_size.x = 85
		row.add_child(speed)
		var pause := CheckButton.new()
		pause.button_pressed = host.bus.clocks[clock].paused
		row.add_child(pause)
		var clock_id: String = clock
		speed.value_changed.connect(func(number: float):
			host.bus.set_clock(clock_id, {"rate": number})
			host.ui.sync_clocks(host.bus.clocks)
		)
		pause.toggled.connect(func(active: bool):
			host.bus.set_clock(clock_id, {"paused": active})
			host.ui.sync_clocks(host.bus.clocks)
		)
	_label(perform_controls, "Beat clock follows filament rate/pause × BPM. Stateful modules do not run backward through history.")


func _process(delta: float) -> void:
	if not is_instance_valid(live):
		return
	_elapsed += delta
	if _elapsed < 0.15:
		return
	_elapsed = 0.0
	if host.synth.patch.is_empty():
		live.text = "Original preset · no patch active"
		return
	var graph = host.synth
	var signal_value = graph.values.get(source_id, null)
	var active_route: Dictionary = graph.route_by_id.get(route_id, {})
	var target_value = host.bus.get_parameters().get(active_route.get("target", ""), null)
	live.text = "%d sources · %d routes · %d ticks\n%s: %s\n%s: %s" % [
		graph.nodes.size(), graph.patch.routes.size(), graph.ticks, source_id, str(signal_value),
		active_route.get("target", "No route"), str(target_value)]
	if not graph.missing_targets.is_empty():
		live.text += "\nMissing: " + str(graph.missing_targets)
	var diagnostic: Dictionary = host.bus.diagnostics
	if not diagnostic.get("unavailable", []).is_empty():
		live.text += "\nInactive domain: " + str(diagnostic.unavailable)
	if not diagnostic.get("clamped", []).is_empty():
		live.text += "\nAt target limits: " + str(diagnostic.clamped)
	if is_instance_valid(pad) and not pad.dragging:
		var axes: Array = graph.patch.xy
		pad.set_point(Vector2(float(graph.nodes.get(axes[0], {}).get("value", 0)), float(graph.nodes.get(axes[1], {}).get("value", 0))))
