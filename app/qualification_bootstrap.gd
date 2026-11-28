extends Node
## Export templates do not implement the editor's --script command-line option.
## The exact packaged SceneTree tests instead run on this application's own tree.

const ALLOWED_SCRIPTS := [
	"test_core.gd", "test_integration.gd", "test_matter.gd", "test_synth.gd",
	"test_ecology.gd", "test_compositions.gd", "test_matter_optics.gd",
	"test_convergence_ecology.gd", "test_convergence.gd", "test_soak.gd",
	"verify_filaments.gd", "verify_optical.gd", "export_source_bits.gd",
	"gui_material_probe.gd", "gui_spatial_ecology_probe.gd", "gui_convergence_probe.gd",
	"gui_synth_probe.gd", "gui_input_probe.gd", "gui_ecology_probe.gd", "verify_captures.gd",
]

func _ready() -> void:
	var requests: Array[String] = []
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--qualification-script="):
			requests.append(argument.trim_prefix("--qualification-script="))
		elif argument == "--qualification-script":
			requests.append("")
	if requests.is_empty():
		_start_application.call_deferred()
		return
	if requests.size() != 1 or not requests[0] in ALLOWED_SCRIPTS:
		_fail("Qualification requires one exact allowlisted script filename")
		return
	_start_qualification.call_deferred(requests[0])

func _start_application() -> void:
	var error := get_tree().change_scene_to_file("res://main.tscn")
	if error != OK:
		_fail("Cannot start the Xenovection application: " + error_string(error))

func _start_qualification(filename: String) -> void:
	var path := "res://qualification/" + filename
	if not FileAccess.file_exists("res://qualification/SOURCE.json"):
		_fail("Exact qualification source manifest is absent")
		return
	if not ResourceLoader.exists(path, "Script"):
		_fail("Exact qualification resource is absent: " + filename)
		return
	var qualified_script: Script = load(path)
	if qualified_script == null or qualified_script.get_instance_base_type() != "SceneTree":
		_fail("Qualification resource must be an exact SceneTree script: " + filename)
		return
	var tree := get_tree()
	# Remove only the startup node before deferred test initialization. A test may
	# then load main.tscn normally without encountering another dispatcher.
	if tree.current_scene == self:
		tree.current_scene = null
	get_parent().remove_child(self)
	queue_free()
	print("XENOVECTION_QUALIFICATION_SCRIPT_STARTED ", filename)
	tree.set_script(qualified_script)
	tree.call_deferred("_initialize")

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(2)
