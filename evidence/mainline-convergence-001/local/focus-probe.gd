extends SceneTree
## Focused Godot GUI event reproduction, usable headless; not a Windows graphical gate.
## Toggle -> toggle -> focusless Step -> Space reproduces the Life transport conflict.
class InstrumentHost:
	extends Control
	var global_space: int = 0
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
			global_space += 1
			get_viewport().set_input_as_handled()

var corrected: bool = false
var step_count: int = 0

func _initialize() -> void:
	corrected = "--corrected" in OS.get_cmdline_user_args()
	run.call_deferred()

func frames(count: int) -> void:
	for i in range(count):
		await process_frame

func click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event, true)
		await frames(2)

func run() -> void:
	root.size = Vector2i(400, 300)
	var host = InstrumentHost.new()
	root.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var toggle = CheckButton.new()
	toggle.name = "EcologyActive"
	toggle.text = "Ecology active"
	toggle.position = Vector2(10, 10)
	toggle.size = Vector2(200, 40)
	toggle.button_pressed = true
	if corrected:
		toggle.focus_mode = Control.FOCUS_NONE
	host.add_child(toggle)
	var step = Button.new()
	step.name = "StepEcology"
	step.text = "Step ecology"
	step.focus_mode = Control.FOCUS_NONE
	step.position = Vector2(10, 60)
	step.size = Vector2(200, 40)
	step.pressed.connect(func(): step_count += 1)
	host.add_child(step)
	await frames(3)
	await click(Vector2(50, 25))
	await click(Vector2(50, 25))
	await click(Vector2(50, 75))
	var focus = root.gui_get_focus_owner()
	var active_before: bool = toggle.button_pressed
	for pressed in [true, false]:
		var event = InputEventKey.new()
		event.keycode = KEY_SPACE
		event.physical_keycode = KEY_SPACE
		event.pressed = pressed
		root.push_input(event, true)
		await frames(2)
	var expected: bool = step_count == 1 and active_before
	if corrected:
		expected = expected and toggle.button_pressed and host.global_space == 1
	else:
		# The press reaches transport; the focused CheckButton also toggles on
		# release. The defect is this unintended second action.
		expected = expected and not toggle.button_pressed and host.global_space == 1
	print(JSON.stringify({"schema": "xenovection.gui-focus-reproduction.v1",
		"corrected": corrected, "focus_mode": toggle.focus_mode,
		"focus_after_step": str(focus.name) if focus != null else "none",
		"step_presses": step_count, "active_before_space": active_before,
		"active_after_space": toggle.button_pressed, "global_space_events": host.global_space,
		"expected_behavior_reproduced": expected,
		"scope": "Actual Control event routing via Viewport.push_input in headless Godot; not Windows graphical qualification"}))
	quit(0 if expected else 1)
