extends VBoxContainer
## Authoring controls for the persistent ecology hosted by the shared instrument.
const World = preload("res://ecology/world.gd")
var application
var enabled_control: CheckButton
var edit_control: CheckButton
var preset_picker: OptionButton
var tool_picker: OptionButton
var family_picker: OptionButton
var quality_picker: OptionButton
var seed_control: SpinBox
var pause_control: Button
var status: Label
var inspector: Label
var parameters: Dictionary = {}
var syncing := false

func setup(host) -> void:
	application = host
	add_theme_constant_override("separation", 8)
	_note("LIVING MATTER", 16)
	_note("One planar numerical world, with spatial optical presentation and a planar diagnostic view. Both views retain the same organisms and seed.")
	_button("Open Ecosystem", func(): application.set_workspace("planar"))
	_button("Show spatial ecology", func(): application.set_workspace("spatial", true))
	enabled_control = CheckButton.new()
	enabled_control.text = "Ecology active"
	enabled_control.focus_mode = Control.FOCUS_NONE
	enabled_control.set_meta("target", "ecology.enabled")
	add_child(enabled_control)
	enabled_control.toggled.connect(func(value):
		if not syncing: application.set_ecology_enabled(value))
	edit_control = CheckButton.new()
	edit_control.text = "Edit ecology in viewport"
	edit_control.focus_mode = Control.FOCUS_NONE
	edit_control.button_pressed = true
	edit_control.tooltip_text = "While Life is selected, left clicks map to the fixed numerical plane. Camera navigation keeps its own mouse buttons."
	add_child(edit_control)
	_note("Seeded starting configuration")
	preset_picker = _option(World.NAMES)
	preset_picker.set_meta("target", "ecology.preset")
	preset_picker.item_selected.connect(func(index):
		if not syncing:
			application.ecology._choose(index)
			application.set_ecology_enabled(true)
			refresh())
	seed_control = SpinBox.new()
	seed_control.min_value = 0
	seed_control.max_value = 2147483647
	seed_control.step = 1
	seed_control.set_meta("target", "ecology.seed")
	add_child(seed_control)
	seed_control.value_changed.connect(func(value):
		if not syncing: application.ecology.seed_box.value = value)
	var row := HBoxContainer.new()
	add_child(row)
	pause_control = _button("Pause ecology", func():
		application.ecology._toggle_pause()
		refresh(), row)
	_button("Step ecology", func():
		application.ecology.paused = true
		application._step_ecology_manual()
		refresh(), row)
	_button("Reset ecology", func():
		application.ecology._reset()
		refresh())
	_note("Spatial tool · clicks use the visible domain boundary")
	tool_picker = _option(["Inspect", "Plant", "Resource source", "Resource sink", "Excite", "Inhibit"])
	tool_picker.set_meta("target", "ecology.tool")
	tool_picker.item_selected.connect(func(index): application.ecology.tools.select(index))
	family_picker = _option(World.FAMILIES)
	family_picker.set_meta("target", "ecology.family")
	family_picker.item_selected.connect(func(index): application.ecology.family.select(index))
	_button("Isolate / reveal selected family", func():
		application.ecology._isolate()
		refresh())
	_note("Representation detail changes only drawing")
	quality_picker = _option(["Full detail", "Half trail detail", "Quarter trail detail"])
	quality_picker.set_meta("target", "ecology.quality")
	quality_picker.item_selected.connect(func(index):
		application.ecology.stride = [1, 2, 4][index]
		application.ecology.quality_picker.select(index))
	_note("Bounded numerical parameters · shared Synth targets")
	for key in World.BOUNDS:
		var label := _note(str(key).capitalize())
		var slider := HSlider.new()
		slider.min_value = World.BOUNDS[key].x
		slider.max_value = World.BOUNDS[key].y
		slider.step = 0.01
		slider.focus_mode = Control.FOCUS_NONE
		slider.set_meta("target", "eco." + str(key))
		add_child(slider)
		slider.value_changed.connect(func(value):
			if not syncing:
				application.ecology._parameter(value, str(key))
				label.text = "%s  %.2f" % [str(key).capitalize(), value])
		parameters[key] = {"input": slider, "label": label}
	_button("Save composition [F5]", func(): application.save_scene("user://scene.json"))
	_button("Recall composition [F6]", func(): application.load_scene("user://scene.json"))
	_note("Scene recall restores authored initial conditions. It restarts organism and particle histories. Planar F5/F6 retains its separate configuration file.")
	status = _note("")
	inspector = _note("")
	refresh()

func _note(text_value: String, font_size := 12) -> Label:
	var label := Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	add_child(label)
	return label

func _button(text_value: String, action: Callable, parent: Control = null) -> Button:
	var button := Button.new()
	button.text = text_value
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	(parent if parent != null else self).add_child(button)
	return button

func _option(values: Array) -> OptionButton:
	var picker := OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE
	for value in values:
		picker.add_item(str(value))
	add_child(picker)
	return picker

func refresh() -> void:
	if application == null or not is_instance_valid(application.ecology) or status == null:
		return
	var ecology = application.ecology
	syncing = true
	enabled_control.set_pressed_no_signal(ecology.simulation_enabled)
	preset_picker.select(int(ecology.world.config.preset))
	seed_control.set_value_no_signal(float(ecology.seed_box.value))
	pause_control.text = "Resume ecology" if ecology.paused else "Pause ecology"
	tool_picker.select(ecology.tools.selected)
	family_picker.select(ecology.family.selected)
	quality_picker.select([1, 2, 4].find(ecology.stride))
	for key in parameters:
		parameters[key].input.set_value_no_signal(float(ecology.world.config.params[key]))
		parameters[key].label.text = "%s  %.2f" % [str(key).capitalize(), float(ecology.world.config.params[key])]
	var m: Dictionary = ecology.world.metrics()
	status.text = "30 Hz world · 10 Hz fields · 5 Hz growth\nTick %d · %d organisms · %d lineages\nResource %.3f · Signal %.3f\n%s" % [m.tick, m.population, m.lineages, m.resource_mean, m.signal_mean, "Paused" if ecology.paused else ("Running" if ecology.simulation_enabled else "Inactive; state retained")]
	ecology._refresh_stats()
	inspector.text = ecology.inspector.text
	syncing = false

func owns_spatial_pointer() -> bool:
	return edit_control.button_pressed and is_visible_in_tree() and application.ecology.simulation_enabled
