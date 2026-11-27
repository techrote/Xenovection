extends CanvasLayer
## The canvas remains the main instrument; controls are a collapsible side rail.

signal action_requested(action: String)
signal parameter_changed(target: String, value: Variant)
signal preset_selected(index: int)
signal clock_changed(clock: String, setting: Dictionary)

const INK := Color(0.035, 0.065, 0.10, 0.94)
const LINE := Color(0.16, 0.28, 0.33, 0.7)
const MINT := Color(0.40, 0.88, 0.83)
const CORAL := Color(0.96, 0.54, 0.45)
const TEXT := Color(0.84, 0.90, 0.92)
const MUTED := Color(0.46, 0.61, 0.68)

var root: Control
var rail: PanelContainer
var inspector: PanelContainer
var title_label: Label
var subtitle_label: Label
var selection_label: Label
var measurement_label: Label
var performance_label: Label
var source_label: Label
var toast_label: Label
var mode_button: Button
var pause_button: Button
var preset_picker: OptionButton
var _controls: Dictionary = {}
var _clock_rates: Dictionary = {}
var _clock_pauses: Dictionary = {}
var _toast_until: int = 0
var _box: Rect2 = Rect2()
var _box_control: Control
var _show_box: bool = false
var clean_view: bool = false
var tabs: TabContainer
var source_layers: VBoxContainer

func _ready() -> void:
	layer = 8
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_build_header()
	_build_rail()
	_build_inspector()
	_build_footer()
	_box_control = Control.new()
	_box_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_box_control)
	_box_control.draw.connect(_draw_box)

func _style(fill: Color = INK, border: Color = LINE, radius: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 14
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", MINT)
	theme.set_stylebox("normal", "Button", _style(Color(0.05, 0.09, 0.13, 0.95)))
	theme.set_stylebox("hover", "Button", _style(Color(0.09, 0.18, 0.21, 0.98), MINT))
	theme.set_stylebox("pressed", "Button", _style(Color(0.08, 0.23, 0.24, 0.98), MINT))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_stylebox("panel", "PanelContainer", _style())
	theme.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())
	theme.set_color("font_selected_color", "TabContainer", MINT)
	theme.set_font_size("font_size", "TabContainer", 13)
	theme.set_stylebox("tab_selected", "TabContainer", _style(Color(0.07, 0.14, 0.18, 1.0), LINE, 5))
	theme.set_stylebox("tab_unselected", "TabContainer", _style(Color(0.035, 0.065, 0.10, 1.0), Color.TRANSPARENT, 5))
	theme.set_stylebox("normal", "OptionButton", _style(Color(0.05, 0.09, 0.13, 1.0)))
	theme.set_stylebox("hover", "OptionButton", _style(Color(0.09, 0.16, 0.20, 1.0), MINT))
	return theme

func _label(text_value: String, size: int = 14, colour: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	return label

func _button(parent: Control, text_value: String, action: String, tooltip: String = "") -> Button:
	var button := Button.new()
	button.text = text_value
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func(): action_requested.emit(action))
	parent.add_child(button)
	return button

func _build_header() -> void:
	var header := HBoxContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 26
	header.offset_right = -26
	header.offset_top = 20
	header.offset_bottom = 68
	header.add_theme_constant_override("separation", 18)
	root.add_child(header)
	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_box)
	title_label = _label("X E N O V E C T I O N", 23, MINT)
	name_box.add_child(title_label)
	subtitle_label = _label("FILAMENTS  /  FIELDS  /  OPTICAL MATTER", 11, MUTED)
	name_box.add_child(subtitle_label)
	preset_picker = OptionButton.new()
	preset_picker.custom_minimum_size.x = 216
	preset_picker.item_selected.connect(func(index: int): preset_selected.emit(index))
	preset_picker.focus_mode = Control.FOCUS_NONE
	header.add_child(preset_picker)
	mode_button = _button(header, "Scientific  [G]", "scientific", "Disable every decorative system while keeping the exact source selection.")
	pause_button = _button(header, "Pause  [Space]", "pause")
	_button(header, "↶", "reverse", "Reverse all five visual clocks [V]")
	_button(header, "☰", "panel", "Toggle instrument controls [Tab]")

func _page(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	return box

func _section(parent: Control, heading: String, note: String = "") -> void:
	var title := _label(heading.to_upper(), 11, MINT)
	title.custom_minimum_size.y = 24
	parent.add_child(title)
	if not note.is_empty():
		var label := _label(note, 12, MUTED)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(label)

func _slider(parent: Control, label_text: String, key: String, minimum: float, maximum: float, step: float, initial: float) -> void:
	var box := VBoxContainer.new()
	parent.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	var label := _label(label_text, 13)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value := _label("%.2f" % initial, 12, MUTED)
	value.custom_minimum_size.x = 42
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = initial
	slider.focus_mode = Control.FOCUS_NONE
	slider.custom_minimum_size.y = 17
	slider.value_changed.connect(func(number: float):
		value.text = "%.2f" % number
		parameter_changed.emit(key, number))
	box.add_child(slider)
	_controls[key] = {"input": slider, "value": value}

func _toggle(parent: Control, label_text: String, key: String, initial: bool = true) -> void:
	var toggle := CheckButton.new()
	toggle.text = label_text
	toggle.button_pressed = initial
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.toggled.connect(func(active: bool): parameter_changed.emit(key, active))
	parent.add_child(toggle)
	_controls[key] = {"input": toggle}

func _build_rail() -> void:
	rail = PanelContainer.new()
	rail.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	rail.offset_left = -326
	rail.offset_right = -24
	rail.offset_top = 86
	rail.offset_bottom = -76
	root.add_child(rail)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	rail.add_child(content)
	content.add_child(_label("THE INSTRUMENT", 11, MUTED))
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(tabs)
	var strands := _page(tabs, "Strands")
	_section(strands, "Hairline structure", "Exact connections. Secondary fibres are artistic.")
	_slider(strands, "Width · pixels", "filament.line_width_px", 0.15, 1.5, 0.01, 0.62)
	_slider(strands, "Coverage / opacity", "filament.opacity", 0.02, 0.8, 0.01, 0.30)
	_slider(strands, "Travelling phase", "filament.phase_speed", -3, 3, 0.02, 0.70)
	_slider(strands, "Wave amplitude", "filament.wave_amplitude", 0, 0.7, 0.005, 0.11)
	_slider(strands, "Braid radius", "filament.braid_radius", 0, 0.3, 0.002, 0.065)
	_slider(strands, "Torsion turns", "filament.braid_turns", 0, 6, 0.05, 2.0)
	_slider(strands, "Resonance", "filament.resonance", 0, 0.3, 0.002, 0.04)
	_slider(strands, "Turbulence", "filament.turbulence", 0, 0.25, 0.002, 0.025)
	_toggle(strands, "Secondary fibres", "fibres_enabled")
	_toggle(strands, "Opposing flows", "filament.counterflow")
	_toggle(strands, "Tiny source markers", "filament.nodes_visible")
	_toggle(strands, "Filament layer", "filament.enabled")
	var optics := _page(tabs, "Optics")
	_section(optics, "Spectral environment", "One analytic field drives the environment and reflected illumination.")
	_slider(optics, "Frequency X", "optical.sky_frequency_x", 0.1, 8, 0.02, 1.6)
	_slider(optics, "Frequency Y", "optical.sky_frequency_y", 0.1, 8, 0.02, 2.1)
	_slider(optics, "Environment speed", "optical.sky_speed", -3, 3, 0.01, 0.55)
	_slider(optics, "Diagonal wave", "optical.sky_diagonal", -3, 3, 0.01, 0.65)
	_slider(optics, "Radial wave", "optical.sky_radius", 0, 6, 0.01, 1.7)
	_slider(optics, "Field warp", "optical.sky_warp", 0, 2, 0.01, 0.38)
	_slider(optics, "Field contrast", "optical.sky_contrast", 0.2, 4, 0.01, 1.7)
	_slider(optics, "HDR radiance", "optical.sky_intensity", 0, 6, 0.02, 2.3)
	_slider(optics, "Environment rotation", "optical.sky_rotation", -3.14, 3.14, 0.01, 0)
	_slider(optics, "Environment pan X", "optical.sky_pan_x", -6, 6, 0.02, 0)
	_slider(optics, "Environment pan Y", "optical.sky_pan_y", -6, 6, 0.02, 0)
	_section(optics, "Surface / weather")
	_slider(optics, "Roughness", "optical.roughness", 0.02, 1, 0.01, 0.19)
	_slider(optics, "Normal detail", "optical.normal_strength", 0, 1, 0.01, 0.24)
	_slider(optics, "Geometric displacement", "optical.displacement", 0, 0.65, 0.005, 0.12)
	_slider(optics, "Reflection-domain warp", "optical.domain_warp", 0, 1, 0.01, 0.12)
	_slider(optics, "Surface opacity", "optical.surface_opacity", 0.1, 1, 0.01, 1)
	_slider(optics, "Metal response", "optical.metallic", 0, 1, 0.01, 0.92)
	_slider(optics, "Palette phase", "optical.palette_phase", -2, 2, 0.01, 0)
	var tint_row := HBoxContainer.new()
	optics.add_child(tint_row)
	var tint_label := _label("Material tint", 13)
	tint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tint_row.add_child(tint_label)
	var tint := ColorPickerButton.new()
	tint.custom_minimum_size = Vector2(86, 28)
	tint.edit_alpha = false
	tint.color_changed.connect(func(value: Color): parameter_changed.emit("optical.material_tint", value))
	tint_row.add_child(tint)
	_controls["optical.material_tint"] = {"input": tint}
	var palette := OptionButton.new()
	for label in ["Glacier / coral", "Molten ember", "Pearl spectrum"]:
		palette.add_item(label)
	palette.item_selected.connect(func(index: int): parameter_changed.emit("optical.palette", ["glacier", "ember", "pearl"][index]))
	optics.add_child(palette)
	_controls["optical.palette"] = {"input": palette}
	_toggle(optics, "Environment backdrop", "optical.sky_visible")
	_toggle(optics, "Optical layer", "optical.enabled")
	var clocks := _page(tabs, "Clocks")
	_section(clocks, "Independent transport", "Negative rates reverse time. Pausing one clock leaves the others playing.")
	for clock: String in ["filament", "sky", "normal", "displacement", "palette"]:
		var row := HBoxContainer.new()
		clocks.add_child(row)
		var label := _label(clock.capitalize(), 13)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var rate := SpinBox.new()
		rate.min_value = -4
		rate.max_value = 4
		rate.step = 0.1
		rate.value = 1
		rate.custom_minimum_size.x = 86
		rate.value_changed.connect(func(value: float): clock_changed.emit(clock, {"rate": value}))
		row.add_child(rate)
		_clock_rates[clock] = rate
		var pause := CheckButton.new()
		pause.tooltip_text = "Pause " + clock
		pause.toggled.connect(func(active: bool): clock_changed.emit(clock, {"paused": active}))
		row.add_child(pause)
		_clock_pauses[clock] = pause
	_section(clocks, "Shared modulation", "A reusable LFO routes into strand motion and optical fields. Stored bases stay unchanged.")
	_toggle(clocks, "Modulation enabled", "modulation.enabled", true)
	_slider(clocks, "LFO frequency · Hz", "modulation.frequency", 0, 2, 0.005, 0.08)
	_slider(clocks, "Modulation depth", "modulation.depth", 0, 2, 0.02, 1)
	var waveform := OptionButton.new()
	for label in ["Sine", "Triangle", "Soft triangle", "Cosine"]:
		waveform.add_item(label)
	waveform.item_selected.connect(func(index: int): parameter_changed.emit("modulation.waveform", ["sine", "triangle", "smooth_triangle", "cosine"][index]))
	clocks.add_child(waveform)
	_controls["modulation.waveform"] = {"input": waveform}
	var row := HBoxContainer.new()
	clocks.add_child(row)
	_button(row, "Reset time", "reset_time")
	_button(row, "Reverse", "reverse")
	var data := _page(tabs, "Source")
	_section(data, "Read-only provenance")
	source_label = _label("Loading source…", 12, MUTED)
	source_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	data.add_child(source_label)
	_section(data, "Scene density")
	for definition: Array in [["Sparse · 2,880 edges", "density24"], ["Recovered · 11,520 edges", "density48"], ["Dense · 46,080 edges", "density96"], ["Extreme · 81,920 edges", "density128"]]:
		_button(data, definition[0], definition[1])
	_section(data, "Source layer visibility")
	source_layers = VBoxContainer.new()
	data.add_child(source_layers)
	_section(data, "Selection / source")
	_button(data, "Select central region", "select_region")
	_button(data, "Load source JSON…", "import")
	_button(data, "Export exact selection", "export_selection")
	_button(data, "Export source snapshot", "export_source")
	_section(data, "Source sample replay", "Derived calibration samples drive two artistic targets; stored source values stay unchanged.")
	_toggle(data, "Replay → phase + field", "replay.enabled", false)
	_button(data, "Export replay recording", "export_replay")
	_section(data, "Reproducible scenes")
	_button(data, "Save scene  [F5]", "save_scene")
	_button(data, "Recall scene  [F6]", "load_scene")
	_button(data, "Save performance receipt  [F10]", "profile")

func _build_inspector() -> void:
	inspector = PanelContainer.new()
	inspector.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	inspector.offset_left = 26
	inspector.offset_right = 595
	inspector.offset_top = -216
	inspector.offset_bottom = -76
	root.add_child(inspector)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	inspector.add_child(box)
	selection_label = _label("Select a source point or drag a region", 14, MINT)
	box.add_child(selection_label)
	measurement_label = _label("Exact source IDs survive every change of visual material.", 12, MUTED)
	measurement_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(measurement_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	for definition: Array in [["Knot", "knot"], ["Ribbon", "ribbon"], ["Membrane", "membrane"], ["Filaments", "unmaterialise"], ["Isolate", "isolate"], ["Focus", "focus"], ["Reveal", "reveal"]]:
		_button(row, definition[0], definition[1])
	var foot := _label("Click: source ID  ·  Drag: through-depth region  ·  Shift: add  ·  Ctrl+Z: undo", 11, MUTED)
	box.add_child(foot)

func _build_footer() -> void:
	var footer := VBoxContainer.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_left = 26
	footer.offset_right = -26
	footer.offset_top = -60
	footer.offset_bottom = -14
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(footer)
	performance_label = _label("Measuring frame times…", 12, MUTED)
	footer.add_child(performance_label)
	footer.add_child(_label("MMB orbit  ·  Shift+MMB pan  ·  RMB + WASD/QE fly  ·  Wheel zoom  ·  F focus  ·  R reset  ·  H clean view", 11, MUTED))
	toast_label = _label("", 14, MINT)
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toast_label.offset_top = 78
	toast_label.offset_left = -370
	toast_label.offset_right = 370
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_label)

func set_presets(presets: Array) -> void:
	preset_picker.clear()
	for preset: Dictionary in presets:
		preset_picker.add_item(preset.title)

func set_source_layers(layer_ids: Array) -> void:
	for child in source_layers.get_children():
		source_layers.remove_child(child)
		child.queue_free()
	for key in _controls.keys():
		if str(key).begins_with("layer."):
			_controls.erase(key)
	for layer in layer_ids:
		_toggle(source_layers, "Layer %d" % int(layer), "layer.%d" % int(layer), true)

func set_tab(index: int) -> void:
	tabs.current_tab = clampi(index, 0, tabs.get_tab_count() - 1)

func sync_value(key: String, value: Variant) -> void:
	if not _controls.has(key):
		return
	var widget: Dictionary = _controls[key]
	if widget.input is Range:
		widget.input.set_value_no_signal(float(value))
		if widget.has("value"):
			widget.value.text = "%.2f" % float(value)
	elif widget.input is OptionButton and key == "optical.palette":
		widget.input.select(["glacier", "ember", "pearl"].find(str(value)))
	elif widget.input is OptionButton and key == "modulation.waveform":
		widget.input.select(["sine", "triangle", "smooth_triangle", "cosine"].find(str(value)))
	elif widget.input is ColorPickerButton:
		widget.input.color = value
	elif widget.input is BaseButton:
		widget.input.set_pressed_no_signal(bool(value))

func sync_clocks(clocks: Dictionary) -> void:
	for key in _clock_rates:
		_clock_rates[key].set_value_no_signal(float(clocks[key].rate))
		_clock_pauses[key].set_pressed_no_signal(bool(clocks[key].paused))

func set_transport(scientific: bool, paused: bool) -> void:
	mode_button.text = "Scientific · ON  [G]" if scientific else "Scientific  [G]"
	mode_button.modulate = MINT if scientific else Color.WHITE
	pause_button.text = "Play  [Space]" if paused else "Pause  [Space]"

func show_message(message: String, seconds: float = 4.0) -> void:
	toast_label.text = message
	_toast_until = Time.get_ticks_msec() + int(seconds * 1000)

func _process(_delta: float) -> void:
	if _toast_until > 0 and Time.get_ticks_msec() > _toast_until:
		toast_label.text = ""
		_toast_until = 0

func toggle_panel() -> void:
	rail.visible = not rail.visible

func toggle_clean() -> void:
	clean_view = not clean_view
	root.visible = not clean_view

func show_selection_box(rectangle: Rect2, active: bool) -> void:
	_box = rectangle.abs()
	_show_box = active
	_box_control.queue_redraw()

func _draw_box() -> void:
	if _show_box:
		_box_control.draw_rect(_box, Color(MINT, 0.075), true)
		_box_control.draw_rect(_box, Color(MINT, 0.8), false, 1.0)
