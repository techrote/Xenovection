extends RefCounted
## Exact numerical inspection of the preserved synthetic tanh specimen.
## Evaluated on user selection, never on every graphics frame.

var specimen: Dictionary = {}
var baseline: Array = []
var perturbed: Array = []
var deltas: Array = []
var selected_input: int = 16
var epsilon: float = 0.125

func load_specimen(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or parsed.get("schema", "") != "frankenfield.synthetic-dense-tanh.v1":
		return false
	specimen = parsed
	epsilon = float(specimen.epsilon)
	baseline = forward(specimen.input)
	probe(selected_input, epsilon)
	return true

func forward(input_values: Array) -> Array:
	var states: Array = [input_values.duplicate()]
	for matrix: Array in specimen.get("weights", []):
		var next: Array = []
		var previous: Array = states[-1]
		for row: Array in matrix:
			var total: float = 0.0
			for i in range(row.size()):
				total += float(row[i]) * float(previous[i])
			next.append(tanh(total))
		states.append(next)
	return states

func probe(channel: int, amount: float = 0.125) -> Dictionary:
	if specimen.is_empty():
		return {}
	selected_input = clampi(channel, 0, int(specimen.channels) - 1)
	epsilon = clampf(amount, -1.0, 1.0)
	var changed: Array = specimen.input.duplicate()
	changed[selected_input] = float(changed[selected_input]) + epsilon
	perturbed = forward(changed)
	deltas.clear()
	for layer in range(baseline.size()):
		var delta: Array = []
		for index in range(baseline[layer].size()):
			delta.append(float(perturbed[layer][index]) - float(baseline[layer][index]))
		deltas.append(delta)
	return {"input_channel": selected_input, "epsilon": epsilon, "baseline": baseline,
		"perturbed": perturbed, "deltas": deltas, "value_kind": "derived",
		"method": "forward(x + epsilon * unit_vector) - forward(x)"}

func node_measurement(layer: int, channel: int) -> Dictionary:
	if layer < 0 or layer >= baseline.size() or channel < 0 or channel >= baseline[layer].size():
		return {}
	return {"activation": baseline[layer][channel], "delta": deltas[layer][channel],
		"value_kind": "derived", "input_channel": selected_input, "epsilon": epsilon}

func edge_measurement(layer: int, output: int, input: int) -> Dictionary:
	if layer < 0 or layer >= specimen.get("weights", []).size():
		return {}
	var matrix: Array = specimen.weights[layer]
	if output < 0 or output >= matrix.size() or input < 0 or input >= matrix[output].size():
		return {}
	var weight: float = matrix[output][input]
	return {"weight": weight, "weight_kind": "synthetic-source",
		"signed_flow": weight * float(deltas[layer][input]), "flow_kind": "derived",
		"method": "W[layer][output][input] * delta_h[layer][input]"}
