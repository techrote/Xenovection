extends RefCounted
## Validate a complete saved scene before the application mutates any live state.

const SCHEMA := "xenovection.scene.v1"
const COMPOSITION_SCHEMA := "xenovection.scene.v2"
const CLOCKS := ["filament", "sky", "normal", "displacement", "palette"]
const MATERIALS := ["none", "knot", "ribbon", "membrane"]
const WAVES := ["sine", "triangle", "smooth_triangle", "cosine"]


static func validate(input, dataset: Dictionary, targets: Dictionary, filament_defaults: Dictionary, optical_defaults: Dictionary) -> Dictionary:
	if not input is Dictionary or not input.get("schema", "") in [SCHEMA, COMPOSITION_SCHEMA]:
		return _fail("Unsupported or malformed scene schema")
	if input.get("schema", "") == COMPOSITION_SCHEMA:
		if not input.get("preset_id", null) is String or input.preset_id.is_empty() or input.preset_id.length() > 96:
			return _fail("Composition requires its persistent preset identity")
	var manifest: Dictionary = dataset.get("manifest", {})
	if input.get("source_id", "") != manifest.get("source_id", "") or input.get("source_revision", "") != manifest.get("revision", ""):
		return _fail("Scene belongs to a different source identity/revision; load its exact source first")
	if input.has("source_projection_revision") and input.source_projection_revision != manifest.get("projection_revision", ""):
		return _fail("Scene belongs to a different spatial projection; restore its exact source snapshot first")
	for field in ["base_parameters", "filament_flags", "optical_flags", "selection", "camera", "clocks"]:
		if not input.get(field, null) is Dictionary:
			return _fail("Scene %s must be an object" % field)
	var result: Dictionary = input.duplicate(true)
	if input.has("replay_enabled") and not input.replay_enabled is bool:
		return _fail("Replay enable flag must be boolean")
	result.replay_enabled = input.get("replay_enabled", false)
	if input.has("preset_index") and (not _number(input.preset_index) or float(input.preset_index) != floor(float(input.preset_index)) or float(input.preset_index) < 0 or float(input.preset_index) > 63):
		return _fail("Invalid scene preset identity")
	if input.base_parameters.size() > 256:
		return _fail("Too many scene parameters")
	for name in input.base_parameters:
		if not name is String or not targets.has(name):
			return _fail("Scene contains unknown modulation target")
		var specification: Dictionary = targets[name]
		var converted := _typed_value(input.base_parameters[name], specification.base)
		if not converted.ok:
			return _fail("Invalid parameter type/value: %s" % name)
		if not _in_bounds(converted.value, specification.minimum, specification.maximum):
			return _fail("Parameter outside its declared bounds: %s" % name)
		result.base_parameters[name] = converted.value
	for group in ["filament_flags", "optical_flags"]:
		var defaults := filament_defaults if group == "filament_flags" else optical_defaults
		if input[group].size() > defaults.size():
			return _fail("Scene contains too many renderer flags")
		for name in input[group]:
			if not defaults.has(name):
				return _fail("Unknown renderer setting: %s" % name)
			var converted := _typed_value(input[group][name], defaults[name])
			if not converted.ok:
				return _fail("Invalid renderer setting: %s" % name)
			result[group][name] = converted.value
			if name == "palette" and not str(converted.value) in ["glacier", "ember", "pearl"]:
				return _fail("Unknown cyclic palette")
			if name == "fibres" and (float(converted.value) != floor(float(converted.value)) or float(converted.value) < 0 or float(converted.value) > 4):
				return _fail("Decorative fibre population exceeds its bound")
			if name == "segments" and (float(converted.value) != floor(float(converted.value)) or float(converted.value) < 1 or float(converted.value) > 128):
				return _fail("Filament tessellation exceeds its bound")
	var selection: Dictionary = input.selection
	if not selection.get("node_ids", null) is Array or not selection.get("edge_ids", null) is Array or not selection.get("hidden_layers", null) is Array:
		return _fail("Scene selection must contain node, edge and layer arrays")
	if selection.node_ids.size() > dataset.nodes.size() or selection.edge_ids.size() > dataset.edges.size() or selection.hidden_layers.size() > 1025:
		return _fail("Scene selection exceeds source capacity")
	var node_ids: Dictionary = {}
	var edge_ids: Dictionary = {}
	for node in dataset.nodes:
		node_ids[node.id] = true
	for edge in dataset.edges:
		edge_ids[edge.id] = true
	for pair in [["node_ids", node_ids], ["edge_ids", edge_ids]]:
		var seen: Dictionary = {}
		for id in selection[pair[0]]:
			if not id is String or not pair[1].has(id) or seen.has(id):
				return _fail("Scene selection contains a missing or duplicate source ID")
			seen[id] = true
	for layer in selection.hidden_layers:
		if not _number(layer) or float(layer) != floor(float(layer)) or float(layer) < 0 or float(layer) > 1024:
			return _fail("Scene hidden layer index is invalid")
	if not selection.get("isolate", null) is bool or not str(selection.get("materialisation", "")) in MATERIALS:
		return _fail("Invalid scene selection/isolation state")
	var camera: Dictionary = input.camera
	var pivot := _typed_value(camera.get("pivot", null), Vector3.ZERO)
	if not pivot.ok or not _in_bounds(pivot.value, -1.0e6, 1.0e6):
		return _fail("Scene camera pivot is invalid")
	result.camera.pivot = pivot.value
	for range_spec in [["distance", 0.12, 250.0], ["yaw", -1.0e6, 1.0e6], ["pitch", -1.48, 1.48], ["fov", 15.0, 110.0]]:
		var value = camera.get(range_spec[0], null)
		if not _number(value) or float(value) < range_spec[1] or float(value) > range_spec[2]:
			return _fail("Invalid camera parameter: %s" % range_spec[0])
	if camera.has("position"):
		var position := _typed_value(camera.position, Vector3.ZERO)
		if not position.ok:
			return _fail("Invalid camera position")
		result.camera.position = position.value
	if input.clocks.size() != CLOCKS.size():
		return _fail("Scene must contain every independent visual clock")
	for name in input.clocks:
		if not name in CLOCKS or not input.clocks[name] is Dictionary:
			return _fail("Unknown or malformed visual clock")
		var clock: Dictionary = input.clocks[name]
		if not clock.get("paused", null) is bool or not _number(clock.get("rate", null)) or not _number(clock.get("time", null)):
			return _fail("Visual clock settings have invalid types")
		if absf(float(clock.rate)) > 8.0 or absf(float(clock.time)) > 86400.0:
			return _fail("Visual clock settings exceed supported ranges")
	for name in ["scientific", "paused", "modulation_enabled"]:
		if not input.get(name, null) is bool:
			return _fail("Scene transport flags must be boolean")
	for name in ["mod_depth", "mod_frequency"]:
		if not _number(input.get(name, null)) or float(input[name]) < 0.0 or float(input[name]) > 2.0:
			return _fail("Scene modulation parameter is invalid")
	if not str(input.get("mod_waveform", "")) in WAVES:
		return _fail("Unknown modulation waveform")
	return {"ok": true, "scene": result}


static func _typed_value(value, template) -> Dictionary:
	if template is bool:
		return {"ok": value is bool, "value": value}
	if template is int or template is float:
		return {"ok": _number(value), "value": value}
	if template is String:
		return {"ok": value is String and value.length() <= 128, "value": value}
	var type := "v2" if template is Vector2 else ("v3" if template is Vector3 else "color")
	var count := 2 if template is Vector2 else (3 if template is Vector3 else 4)
	var entries: Array = []
	if (template is Vector2 and value is Vector2) or (template is Vector3 and value is Vector3):
		return {"ok": value.is_finite(), "value": value}
	if template is Color and value is Color:
		return {"ok": is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a), "value": value}
	if not value is Dictionary or value.get("_type", "") != type or not value.get("value", null) is Array:
		return {"ok": false, "value": null}
	entries = value.value
	if entries.size() != count:
		return {"ok": false, "value": null}
	for component in entries:
		if not _number(component):
			return {"ok": false, "value": null}
	if count == 2:
		var vector := Vector2(float(entries[0]), float(entries[1]))
		return {"ok": vector.is_finite(), "value": vector}
	if count == 3:
		var vector := Vector3(float(entries[0]), float(entries[1]), float(entries[2]))
		return {"ok": vector.is_finite(), "value": vector}
	var colour := Color(float(entries[0]), float(entries[1]), float(entries[2]), float(entries[3]))
	return {"ok": is_finite(colour.r) and is_finite(colour.g) and is_finite(colour.b) and is_finite(colour.a), "value": colour}


static func _in_bounds(value, minimum, maximum) -> bool:
	if _number(value):
		return float(value) >= float(minimum) and float(value) <= float(maximum)
	if value is Vector2:
		var lo: Vector2 = Vector2.ONE * float(minimum) if _number(minimum) else minimum
		var hi: Vector2 = Vector2.ONE * float(maximum) if _number(maximum) else maximum
		return value.x >= lo.x and value.y >= lo.y and value.x <= hi.x and value.y <= hi.y
	if value is Vector3:
		var lo: Vector3 = Vector3.ONE * float(minimum) if _number(minimum) else minimum
		var hi: Vector3 = Vector3.ONE * float(maximum) if _number(maximum) else maximum
		return value.x >= lo.x and value.y >= lo.y and value.z >= lo.z and value.x <= hi.x and value.y <= hi.y and value.z <= hi.z
	if value is Color:
		for component in [value.r, value.g, value.b, value.a]:
			if component < float(minimum) or component > float(maximum):
				return false
		return true
	return false


static func _number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
