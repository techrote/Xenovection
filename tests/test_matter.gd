extends SceneTree
const Main = preload("res://main.gd")
const Field = preload("res://matter/field_model.gd")
const Matter = preload("res://matter/laboratory.gd")
var failures: Array = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append(description)
	print("PASS " if condition else "FAIL ",description)

func _run() -> void:
	var config := {"field":5,"secondary":2,"mix":0.42,"strength":3.0,"origin":Vector3(1,0,-1)}
	var seeds := Field.seeds(73,48)
	check(seeds == Field.seeds(73,48) and seeds != Field.seeds(74,48),"Deterministic bounded seeding")
	var path := Field.path(seeds[0],129,0.1,config,true)
	check(path == Field.path(seeds[0],129,0.1,config,true),"Pathline fixed-step replay")
	check(path != Field.path(seeds[0],129,0.1,config,false),"Pathline distinct from streamline")
	var finite := true
	var point := seeds[0]
	for i in range(12000):
		point = Field.step(point,i/60.0,Field.FIXED_STEP,config)
		finite = finite and point.is_finite() and absf(point.x) <= Field.LIMIT and absf(point.y) <= Field.LIMIT and absf(point.z) <= Field.LIMIT
	check(finite,"Twelve thousand bounded midpoint steps")
	var app = Main.new()
	root.add_child(app)
	app.set_process(false)
	var revision: String = app.dataset.manifest.revision
	check(app.presets.size() == 13,"Seven accepted plus six generated presets")
	for index in range(7,13):
		app.apply_preset(index)
		app._process(1.0/60.0)
		check(app.matter.active and app.dataset.manifest.revision == revision,"Generated preset preserves original source: %d" % index)
		var metrics: Dictionary = app.matter.metrics()
		check(metrics.regions.size() == 3 and metrics.regions[0].vertices > 0,"Stable generated slot topology: %d" % index)
	app.apply_preset(11)
	var region = app.matter.regions[0]
	var before: int = region.builds
	app.set_parameter("matter.edit.condensation",0.0)
	app._process(1.0/60.0)
	check(is_equal_approx(float(region.shader.get_shader_parameter("condensation")),0.0),"Separated strand endpoint reaches shader")
	app.set_parameter("matter.edit.condensation",0.51)
	app._process(1.0/60.0)
	check(is_equal_approx(float(region.shader.get_shader_parameter("condensation")),0.51),"Intermediate state reaches shader")
	app.set_parameter("matter.edit.condensation",1.0)
	app._process(1.0/60.0)
	check(region.builds == before and is_equal_approx(float(region.shader.get_shader_parameter("condensation")),1.0),"Film endpoint changes uniform without mesh rebuild")
	app.handle_action("matter_select_1")
	app.set_parameter("matter.edit.visible",true)
	app.set_parameter("matter.edit.x",2.5)
	app._process(1.0/60.0)
	check(is_equal_approx(app.matter.regions[1].position.x,2.5) and is_zero_approx(region.position.x),"Independent region placement")
	app.handle_action("isolate")
	app._process(1.0/60.0)
	check(not region.visible and app.matter.regions[1].visible,"Region isolation")
	app.handle_action("scientific")
	app._process(1.0/60.0)
	check(not app.matter.visible and app.dataset.manifest.revision == revision,"Scientific mode hides generated material")
	app.handle_action("scientific")
	app.handle_action("reveal")
	var save_path := "user://found003-test.json"
	app.save_scene(save_path)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	check(Matter.valid_snapshot(saved.matter),"Persisted region schema is valid")
	app.set_parameter("matter.edit.x",-2.5)
	check(app.load_scene(save_path) and is_equal_approx(float(app.bus.get_base(Matter.target(1,"x"))),2.5),"Scene recall restores independent region bases")
	var bad := saved.duplicate(true)
	bad.matter.baked[0].field = 999
	var file := FileAccess.open(save_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(bad))
	file.close()
	check(not app.load_scene(save_path) and is_equal_approx(float(app.bus.get_base(Matter.target(1,"x"))),2.5),"Malformed matter rejected atomically")
	app.apply_preset(7)
	region = app.matter.regions[0]
	for frame in range(60): app._process(1.0/60.0)
	check(region.fixed_steps >= 59 and region.fixed_steps <= 60,"Bounded live particle stepping")
	var particles: PackedVector3Array = region.positions.duplicate()
	app.handle_action("pause")
	for frame in range(30): app._process(1.0/60.0)
	check(region.positions == particles,"Pause freezes particle advection")
	app.handle_action("pause")
	app.handle_action("reverse")
	for frame in range(30): app._process(1.0/60.0)
	check(region.positions == particles,"Reverse does not falsely reverse history-dependent advection")
	app.apply_preset(0)
	app._process(1.0/60.0)
	check(not app.matter.visible and app.dataset.manifest.revision == revision,"Accepted preset remains source-bound")
	app.queue_free()
	await process_frame
	print("FOUND003_MATTER_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
