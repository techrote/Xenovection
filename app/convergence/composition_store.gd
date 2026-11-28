extends RefCounted
## V2 stores authored state and initial ecology, never transient simulation
## histories. Validation/migration happens before the application mutates state.
const SCHEMA := "xenovection.scene.v2"
const MAX_BYTES := 4 * 1024 * 1024
const Catalogue = preload("res://convergence/composition_catalogue.gd")
const World = preload("res://ecology/world.gd")
const Matter = preload("res://matter/laboratory.gd")
const EcologyPatch = preload("res://convergence/ecology_patch.gd")


static func default_ecology() -> Dictionary:
	return {"enabled": false, "paused": false, "configuration": World.initial_config(0, 7301),
		"representation": {"mode": "spatial", "quality": 0, "field_mode": 1, "selected": -1, "isolated": -1}}


static func encode_scene(scene: Dictionary, presets: Array, ecology: Dictionary = {}, workspace: String = "instrument") -> Dictionary:
	var result := scene.duplicate(true)
	result.schema = SCHEMA
	var index := clampi(int(result.get("preset_index", 0)), 0, presets.size() - 1)
	result.preset_id = Catalogue.stable_id(presets[index])
	result.ecology = ecology.duplicate(true) if not ecology.is_empty() else default_ecology()
	result.workspace = workspace
	result.history_scope = "Authored configuration; graph delays, particles and organism histories restart on recall."
	if result.get("synth_patch", {}) is Dictionary and not result.get("synth_patch", {}).is_empty():
		result.synth_patch.preset_id = result.preset_id
		result.synth_patch.preset = index
	return result


static func normalize(input, presets: Array, default_bases: Dictionary, filament_defaults: Dictionary, optical_defaults: Dictionary) -> Dictionary:
	if not input is Dictionary or not input.get("schema", "") in [SCHEMA, "xenovection.scene.v1"]:
		return _fail("Unsupported composition schema")
	if input.has("preset_index") and not World.valid_integer(input.preset_index, 0, 63):
		return _fail("Invalid scene preset identity")
	var identity := Catalogue.resolve_scene(input, presets)
	if not identity.ok:
		return identity
	var result: Dictionary = input.duplicate(true)
	if not result.get("base_parameters") is Dictionary or not result.get("filament_flags") is Dictionary or not result.get("optical_flags") is Dictionary:
		return _fail("Composition requires parameter and renderer objects")
	# Defaults come from registration, never from the currently playing scene.
	var bases := default_bases.duplicate(true)
	bases.merge(result.base_parameters, true)
	result.base_parameters = bases
	var filament := filament_defaults.duplicate(true)
	filament.merge(result.filament_flags, true)
	result.filament_flags = filament
	var optical := optical_defaults.duplicate(true)
	optical.merge(result.optical_flags, true)
	result.optical_flags = optical
	result.preset_id = identity.id
	result.preset_index = identity.index
	var matter = result.get("matter", {"schema": Matter.SCHEMA, "active": false, "selected": 0, "isolated": false, "baked": []})
	if not Matter.valid_snapshot(matter):
		return _fail("Malformed procedural matter snapshot")
	result.matter = matter
	var patch = result.get("synth_patch", {})
	if not patch is Dictionary:
		return _fail("Malformed synthesis patch")
	if not patch.is_empty():
		if not World.valid_integer(patch.get("preset"), 0, 63):
			return _fail("Invalid patch scene index")
		if patch.has("preset_id") and Catalogue.index_of(presets, str(patch.preset_id)) != int(identity.index):
			return _fail("Patch belongs to a different composition")
		if input.get("schema") == "xenovection.scene.v1" and int(patch.preset) != int(input.get("preset_index", 0)):
			return _fail("Legacy patch belongs to a different scene")
	var migrated_patch := Catalogue.migrate_patch(patch, presets, identity.id)
	if not migrated_patch.ok:
		return migrated_patch
	result.synth_patch = migrated_patch.patch
	var ecology := validate_ecology(result.get("ecology", default_ecology()))
	if not ecology.ok:
		return ecology
	result.ecology = ecology.value
	if bool(result.ecology.configuration.get("lfo", false)):
		var ecology_patch := EcologyPatch.with_lfo(result.synth_patch, int(identity.index), str(identity.id), true)
		if not ecology_patch.ok:
			return ecology_patch
		result.synth_patch = ecology_patch.patch
	var workspace = result.get("workspace", "instrument")
	if not workspace is String or not workspace in ["instrument", "planar", "spatial"]:
		return _fail("Unknown authoring workspace")
	result.workspace = workspace
	result.replay_enabled = result.get("replay_enabled", false)
	# The inherited numerical/source validator remains the authority for its
	# complete field population; it accepts the canonical V1 inner structure.
	result.schema = "xenovection.scene.v1"
	return {"ok": true, "scene": result, "schema": SCHEMA, "migrated": identity.migrated}


static func validate_ecology(value) -> Dictionary:
	if not value is Dictionary:
		return _fail("Ecology state must be an object")
	var result := default_ecology()
	result.merge(value, true)
	if not result.enabled is bool or not result.paused is bool or not result.configuration is Dictionary:
		return _fail("Ecology authored state has invalid types")
	var world = World.new()
	if not world.validate(result.configuration):
		return _fail(world.last_error)
	if not result.representation is Dictionary:
		return _fail("Ecology representation must be an object")
	var rep: Dictionary = default_ecology().representation
	rep.merge(result.representation, true)
	if not rep.mode is String or not rep.mode in ["spatial", "planar"]:
		return _fail("Unknown ecology representation mode")
	for entry in [["quality", 0, 2], ["field_mode", 0, 3], ["selected", -1, 2147483647], ["isolated", -1, 3]]:
		if not World.valid_integer(rep.get(entry[0]), entry[1], entry[2]):
			return _fail("Invalid ecology representation setting: " + str(entry[0]))
	result.representation = rep
	return {"ok": true, "value": result}


static func read(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return null
	return JSON.parse_string(file.get_as_text())


static func write(path: String, scene: Dictionary) -> bool:
	# Same temporary-file/previous-save discipline as qualified patch saves,
	# with the wider bounded scene envelope.
	var encoded := JSON.stringify(scene, "\t", false, true)
	if encoded.to_utf8_buffer().size() > MAX_BYTES:
		return false
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(encoded)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return false
	var absolute := ProjectSettings.globalize_path(path)
	var backup := absolute + ".bak"
	if FileAccess.file_exists(absolute):
		if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK:
			return false
		if DirAccess.rename_absolute(absolute, backup) != OK:
			return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), absolute) != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, absolute)
		return false
	return true


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
