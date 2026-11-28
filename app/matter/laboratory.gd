extends Node3D
## Three stable generated region slots; no source IDs are manufactured.
const Region = preload("res://matter/region.gd")
const COUNT := 3
const SCHEMA := "xenovection.matter.v1"
# base, minimum, maximum; discrete topology targets are sampled from bases
# only on explicit user edits/reintegrate. Continuous targets are evaluated live.
const SPECS := {
	"visible": [0.0,0.0,1.0], "mode": [1.0,0.0,1.0], "seed": [73.0,0.0,9999.0],
	"count": [96.0,24.0,192.0], "field": [0.0,0.0,6.0], "secondary": [2.0,0.0,6.0],
	"mix": [0.42,0.0,1.0], "integration": [0.055,0.005,0.12], "pathline": [0.0,0.0,1.0],
	"strength": [1.0,0.0,3.0], "origin_x": [0.0,-4.0,4.0], "origin_y": [0.0,-4.0,4.0], "origin_z": [0.0,-4.0,4.0],
	"condensation": [0.7,0.0,1.0], "shell": [0.0,0.0,1.0], "deformation": [0.45,0.0,1.5],
	"pore_size": [0.22,0.0,0.47], "growth": [1.0,0.0,1.0], "thickness": [0.42,0.0,1.0],
	"roughness": [0.26,0.0,1.0], "absorption": [0.2,0.0,2.0], "opacity": [0.45,0.0,1.0],
	"line_width": [0.65,0.2,3.0], "hue": [0.0,0.0,1.0], "trails": [0.35,0.0,1.0],
	"particles": [0.0,0.0,1.0], "x": [0.0,-9.0,9.0], "y": [0.0,-9.0,9.0], "z": [0.0,-9.0,9.0],
	"rotation": [0.0,-3.14,3.14], "scale": [1.0,0.2,2.0]
}
const TOPOLOGY := ["mode","seed","count","field","secondary","integration","pathline","mix","strength","origin_x","origin_y","origin_z"]
var regions: Array = []
var active := false
var selected := 0
var isolated := false
var history: Array = []
var redo_history: Array = []
var baked: Array = []

func _ready() -> void:
	for i in range(COUNT):
		var region = Region.new()
		region.name = "GeneratedRegion%d" % i
		add_child(region)
		region.hide()
		regions.append(region)
		baked.append({})

static func target(slot: int, key: String) -> String:
	return "matter.region%d.%s" % [slot,key]

func register_targets(bus) -> void:
	for i in range(COUNT):
		for key in SPECS:
			var s: Array = SPECS[key]
			bus.register_target(target(i,key), s[0], s[1], s[2])

func params(bus, slot: int, effective: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}
	for key in SPECS:
		var name := target(slot,key)
		result[key] = effective.get(name, bus.get_base(name))
	return result

func set_defaults(bus, preset: Dictionary) -> void:
	active = preset.has("matter")
	selected = 0
	isolated = false
	history.clear()
	redo_history.clear()
	for i in range(COUNT):
		var overrides: Dictionary = {}
		var layers: Array = preset.get("matter", [])
		if i < layers.size(): overrides = layers[i]
		for key in SPECS:
			bus.set_base(target(i,key), float(overrides.get(key,SPECS[key][0])))
		if active: rebuild(bus,i)
		else: regions[i].hide()
	visible = active

func rebuild(bus, slot: int) -> void:
	var p := params(bus,slot)
	baked[slot] = {}
	for key in TOPOLOGY: baked[slot][key] = p[key]
	regions[slot].rebuild(p)

func update(bus, effective: Dictionary, clocks: Dictionary, delta: float, scientific: bool, disabled: bool = false) -> void:
	visible = active and not scientific and not disabled
	if not visible: return
	var clock: Dictionary = bus.clocks.filament
	for i in range(COUNT):
		var p := params(bus,i,effective)
		# Discrete and baked topology cannot silently change from signal routes.
		for key in ["mode","seed","count","field","secondary","integration","pathline"]:
			p[key] = baked[i].get(key,p[key])
		regions[i].update(p,clocks,delta * maxf(0.0,float(clock.rate)),not bus.paused and not clock.paused and clock.rate > 0.0,not isolated or i == selected)

func edit(bus, key: String, value: Variant) -> void:
	if not active or not SPECS.has(key): return
	var old: float = bus.get_base(target(selected,key))
	var next := clampf(float(value),SPECS[key][1],SPECS[key][2])
	if old == next: return
	# Consecutive slider changes for the same target coalesce into one undo.
	if history.is_empty() or history.back().slot != selected or history.back().key != key or Time.get_ticks_msec() - int(history.back().time) > 350:
		history.append({"slot":selected,"key":key,"old":old,"new":next,"time":Time.get_ticks_msec()})
	else:
		history.back().new = next
		history.back().time = Time.get_ticks_msec()
	if history.size() > 48: history.pop_front()
	redo_history.clear()
	_apply(bus,selected,key,next)

func _apply(bus, slot: int, key: String, value: float) -> void:
	bus.set_base(target(slot,key),value)
	if key in ["mode","seed","count","field","secondary","integration","pathline"]:
		rebuild(bus,slot)

func undo(bus, redo: bool) -> void:
	var source_history: Array = redo_history if redo else history
	var destination_history: Array = history if redo else redo_history
	if source_history.is_empty(): return
	var item: Dictionary = source_history.pop_back()
	_apply(bus,int(item.slot),str(item.key),float(item.new if redo else item.old))
	destination_history.append(item)
	selected = int(item.slot)

func pick(camera: Camera3D, screen: Vector2) -> void:
	# Region-centre picking, not an exact procedural surface hit.
	var best := 180.0
	for i in range(COUNT):
		if not regions[i].visible or camera.is_position_behind(regions[i].global_position): continue
		var distance := camera.unproject_position(regions[i].global_position).distance_to(screen)
		if distance < best:
			best = distance
			selected = i

func focus_points() -> PackedVector3Array:
	var p: Vector3 = regions[selected].global_position
	var extent: float = regions[selected].scale.x * 2.8
	return PackedVector3Array([p-Vector3.ONE*extent,p+Vector3.ONE*extent])

func snapshot() -> Dictionary:
	return {"schema":SCHEMA,"active":active,"selected":selected,"isolated":isolated,"baked":baked.duplicate(true) if active else []}

static func valid_snapshot(value: Variant) -> bool:
	if not value is Dictionary or value.get("schema","") != SCHEMA or not value.get("active",null) is bool or not value.get("isolated",null) is bool: return false
	var sel = value.get("selected",null)
	if not (sel is int or sel is float) or not is_finite(float(sel)) or float(sel) != floor(float(sel)) or sel < 0 or sel >= COUNT: return false
	if not value.get("baked",null) is Array or value.baked.size() != (COUNT if value.active else 0): return false
	for entry in value.baked:
		if not entry is Dictionary or entry.size() != TOPOLOGY.size(): return false
		for key in TOPOLOGY:
			var v = entry.get(key,null)
			if not (v is int or v is float) or not is_finite(float(v)) or v < SPECS[key][1] or v > SPECS[key][2]: return false
	return true

func restore(bus, data: Dictionary) -> void:
	active = data.active
	selected = int(data.selected)
	isolated = data.isolated
	history.clear()
	redo_history.clear()
	visible = active
	if active:
		for i in range(COUNT):
			var p := params(bus,i)
			baked[i] = data.baked[i].duplicate(true)
			for key in TOPOLOGY: p[key] = baked[i][key]
			regions[i].rebuild(p)
	else:
		for region in regions: region.hide()

func reset_particles(bus) -> void:
	if active:
		for i in range(COUNT): regions[i].reset_particles(int(baked[i].seed))

func metrics() -> Dictionary:
	var result: Array = []
	if active:
		for i in range(COUNT):
			var m: Dictionary = regions[i].metrics()
			m.id = "generated-region-%d" % i
			result.append(m)
	return {"schema":SCHEMA,"active":active,"visible":visible,"selected":selected,"regions":result}
