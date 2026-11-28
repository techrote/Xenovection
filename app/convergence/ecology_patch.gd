extends RefCounted
## Legacy ecology's authored slow modulation belongs to the common graph. The
## toggle changes ordinary visible components/routes, never a second bus.
const Graph = preload("res://core/synth_graph.gd")
const Examples = preload("res://core/synth_examples.gd")
const SOURCE := "ecology_lfo"
const GROWTH := "ecology_lfo_growth"
const EXCITATION := "ecology_lfo_excitation"


static func with_lfo(patch: Dictionary, preset_index: int, preset_id: String, enabled: bool) -> Dictionary:
	var result := Graph.blank(preset_index, preset_id) if patch.is_empty() else patch.duplicate(true)
	if not result.get("sources") is Array or not result.get("routes") is Array:
		return {"ok": false, "error": "Malformed shared graph"}
	var source_index := -1
	for i in range(result.sources.size()):
		if not result.sources[i] is Dictionary:
			return {"ok": false, "error": "Malformed graph component"}
		if str(result.sources[i].get("id", "")) == SOURCE:
			source_index = i
			if result.sources[i].get("kind") != "sine":
				return {"ok": false, "error": "The ecology_lfo identity is already used by another component"}
	for i in range(result.routes.size() - 1, -1, -1):
		var route = result.routes[i]
		if not route is Dictionary:
			return {"ok": false, "error": "Malformed graph route"}
		if str(route.get("id", "")) in [GROWTH, EXCITATION]:
			var target := "eco.growth" if route.id == GROWTH else "eco.excitation"
			if route.get("source") != SOURCE or route.get("target") != target:
				return {"ok": false, "error": "Ecology modulation route identity collision"}
			result.routes.remove_at(i)
	if enabled:
		if source_index < 0:
			result.sources.append(Examples.node(SOURCE, "sine", {"clock": "filament", "rate": 0.08}))
		result.routes.append(Examples.route(GROWTH, SOURCE, "eco.growth", 0.4))
		result.routes.append(Examples.route(EXCITATION, SOURCE, "eco.excitation", 0.35))
	elif source_index >= 0:
		var referenced := false
		for route in result.routes:
			referenced = referenced or route.get("source") == SOURCE
		for source in result.sources:
			for port in ["a", "b", "c"]:
				referenced = referenced or source.get(port, "") == SOURCE
		if not referenced:
			result.sources.remove_at(source_index)
	if result.sources.size() > Graph.MAX_NODES or result.routes.size() > Graph.MAX_ROUTES:
		return {"ok": false, "error": "Ecology modulation exceeds the shared 48-source/96-route graph budget"}
	result.preset = preset_index
	result.preset_id = preset_id
	return {"ok": true, "patch": result}
