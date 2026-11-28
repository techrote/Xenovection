extends SceneTree
var app
func _initialize(): run.call_deferred()
func frames(n):
	for i in range(n): await process_frame
func inspect(label):
	var e=app.ecology
	var rows=[]
	for control in [e.panel,e.interaction_button,e.reproduction_button,e.mod_button,e.spatial_button,e.return_button]:
		rows.append({"name":control.name,"text":control.text if control is Button else "panel","minimum":str(control.get_combined_minimum_size()),"rect":str(control.get_global_rect())})
	print("PLANAR_RAIL ",JSON.stringify({"case":label,"viewport":str(root.get_visible_rect()),"workspace":str(e.get_global_rect()),"controls":rows}))
func run():
	root.size=Vector2i(1440,900)
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames(6)
	app.set_workspace("planar")
	await frames(6)
	inspect("current hosted labels")
	app.ecology.mod_button.text="Slow growth/excitation modulation"
	await frames(6)
	inspect("original qualified modulation label")
	root.remove_child(app)
	app.free()
	await frames(2)
	quit()
