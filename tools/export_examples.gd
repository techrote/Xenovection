extends SceneTree
## Export editable authored examples from the exact application being packaged.
const Main = preload("res://main.gd")
const Examples = preload("res://core/synth_examples.gd")
const Graph = preload("res://core/synth_graph.gd")
var output := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-directory="):
			output = argument.trim_prefix("--output-directory=")
	_run.call_deferred()

func _run() -> void:
	if output.is_empty():
		push_error("An explicit package sample directory is required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output.path_join("scenes"))
	DirAccess.make_dir_recursive_absolute(output.path_join("patches"))
	var application = Main.new()
	root.add_child(application)
	application.set_process(false)
	application.ecology.set_process(false)
	var rows: Array = []
	var patches: Array = []
	for index in range(application.presets.size()):
		application.apply_preset(index)
		application._process(0.0)
		var preset: Dictionary = application.presets[index]
		var filename: String = str(preset.stable_id) + ".json"
		var path := output.path_join("scenes").path_join(filename)
		application.save_scene(path)
		if not FileAccess.file_exists(path):
			push_error("Missing generated scene: " + filename)
			quit(1)
			return
		rows.append({"id": preset.stable_id, "title": preset.title, "scene": "scenes/" + filename})
		if not application.synth.patch.is_empty():
			if not Graph.write_patch(output.path_join("patches").path_join(filename), application.synth.snapshot(application.bus)):
				push_error("Could not export integrated patch: " + filename)
				quit(1)
				return
			patches.append({"id": "patch." + str(preset.stable_id), "title": preset.title,
				"preset_id": preset.stable_id, "patch": "patches/" + filename})
	var instruments: Array = Examples.all()
	for index in range(instruments.size()):
		if not application.install_synth_patch(instruments[index].patch, true):
			push_error("Cannot export retained instrument: " + application.synth_error)
			quit(1)
			return
		var patch_filename := "synth-%02d.json" % (index + 1)
		var authored: Dictionary = application.synth.snapshot(application.bus)
		if not Graph.write_patch(output.path_join("patches").path_join(patch_filename), authored):
			quit(1)
			return
		patches.append({"id": "patch.synth.%02d" % (index + 1), "title": instruments[index].title,
			"preset_id": authored.preset_id, "patch": "patches/" + patch_filename})
	var manifest := FileAccess.open(output.path_join("INDEX.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"schema": "xenovection.examples.v1", "scenes": rows, "patches": patches,
		"history_scope": "Authored initial states; transient numerical histories restart.",
		"patch_recall_scope": "Patch recall reapplies its referenced composition; use a whole scene to retain matter, optical and ecology initial authoring together."}, "\t"))
	manifest.close()
	root.remove_child(application)
	application.free()
	print("EXPORTED_EXAMPLES ", rows.size(), " compositions; ", patches.size(), " indexed patches")
	quit(0)
