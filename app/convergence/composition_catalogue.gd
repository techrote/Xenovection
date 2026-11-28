extends RefCounted
## Persistent composition identity is independent of the picker order. Legacy
## names remain in receipts; the stable names distinguish every feature domain.
const BASE_IDS := ["hybrid", "filaments", "optical", "membrane", "scientific", "stress", "flow"]
const MATTER_IDS := ["nursery", "garden", "living", "films", "condensation", "ecosystem"]
const OPTICAL_IDS := ["optical_dichroic", "optical_weather", "optical_lens", "optical_garden", "optical_microfibres", "optical_ecosystem"]


static func stable_id(preset: Dictionary) -> String:
	if preset.has("stable_id"):
		return str(preset.stable_id)
	var id := str(preset.get("id", ""))
	if id.begins_with("integrated_"):
		return "composition." + id.trim_prefix("integrated_")
	if id in MATTER_IDS:
		return "matter." + id
	if id in OPTICAL_IDS:
		return "optical." + id.trim_prefix("optical_")
	return "source." + id


static func decorate(presets: Array) -> Array:
	var result: Array = []
	for original in presets:
		var preset: Dictionary = original.duplicate(true)
		preset.stable_id = stable_id(preset)
		preset.category = str(preset.stable_id).get_slice(".", 0)
		var title := str(preset.get("title", preset.id)).strip_edges()
		var prefix := title.get_slice(" ", 0)
		if prefix.is_valid_int():
			title = title.substr(prefix.length()).strip_edges()
		preset.title = "%02d  %s" % [result.size() + 1, title]
		result.append(preset)
	return result


static func index_of(presets: Array, id: String) -> int:
	for i in range(presets.size()):
		if stable_id(presets[i]) == id or str(presets[i].get("id", "")) == id:
			return i
	return -1


static func validate(presets: Array) -> Dictionary:
	var stable: Dictionary = {}
	var legacy: Dictionary = {}
	for preset in presets:
		if not preset is Dictionary or str(preset.get("id", "")).is_empty():
			return {"ok": false, "error": "Composition requires a stable identity"}
		var id := stable_id(preset)
		if stable.has(id) or legacy.has(str(preset.id)):
			return {"ok": false, "error": "Duplicate composition identity: " + id}
		stable[id] = true
		legacy[str(preset.id)] = true
	return {"ok": true, "count": presets.size(), "ids": stable.keys()}


static func resolve_scene(scene: Dictionary, presets: Array) -> Dictionary:
	var index := -1
	var migrated := false
	if scene.has("preset_id"):
		if not scene.preset_id is String:
			return {"ok": false, "error": "Composition identity must be text"}
		index = index_of(presets, scene.preset_id)
	elif scene.get("schema", "") == "xenovection.scene.v1":
		var old = scene.get("preset_index", 0)
		if not (old is int or old is float) or not is_finite(float(old)) or float(old) != floorf(float(old)) or old < 0 or old > 12:
			return {"ok": false, "error": "Unknown legacy composition index"}
		var id := ""
		if int(old) < BASE_IDS.size():
			id = BASE_IDS[int(old)]
		elif scene.has("matter"):
			# Every qualified FOUND save wrote its matter snapshot, including
			# inactive state; OPTICAL saves did not have that field.
			id = MATTER_IDS[int(old) - BASE_IDS.size()]
		elif scene.get("base_parameters", {}) is Dictionary and scene.get("base_parameters", {}).has("optical.optical_mix"):
			id = OPTICAL_IDS[int(old) - BASE_IDS.size()]
		else:
			return {"ok": false, "error": "Ambiguous legacy 08–13 composition; add its qualified preset_id"}
		index = index_of(presets, id)
		migrated = true
	if index < 0:
		return {"ok": false, "error": "Composition identity is unavailable"}
	return {"ok": true, "index": index, "id": stable_id(presets[index]), "migrated": migrated}


static func migrate_patch(patch: Dictionary, presets: Array, scene_id: String = "") -> Dictionary:
	var result := patch.duplicate(true)
	if result.is_empty():
		return {"ok": true, "patch": result}
	var identity := str(result.get("preset_id", scene_id))
	if identity.is_empty():
		# Qualified SYNTH patches used only the seven accepted baseline scenes.
		var old = result.get("preset", -1)
		if not (old is int or old is float) or not is_finite(float(old)) or float(old) != floorf(float(old)) or old < 0 or old >= BASE_IDS.size():
			return {"ok": false, "error": "Patch needs a persistent composition identity"}
		identity = "source." + BASE_IDS[int(old)]
	var index := index_of(presets, identity)
	if index < 0:
		return {"ok": false, "error": "Patch composition is unavailable: " + identity}
	result.preset = index
	result.preset_id = stable_id(presets[index])
	return {"ok": true, "patch": result}
