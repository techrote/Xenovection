extends SceneTree
var checks=0
var failures=[]
var cases=[]
func _initialize(): run.call_deferred()
func frames(n):
	for i in range(n): await process_frame
func check(ok,label):
	checks+=1
	if not ok: failures.append(label)
func click(point):
	var motion=InputEventMouseMotion.new()
	motion.position=point
	motion.global_position=point
	root.push_input(motion,true)
	for pressed in [true,false]:
		var event=InputEventMouseButton.new()
		event.position=point
		event.global_position=point
		event.button_index=MOUSE_BUTTON_LEFT
		event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed=pressed
		root.push_input(event,true)
	await frames(2)
func rv(r): return [r.position.x,r.position.y,r.size.x,r.size.y]
func run():
	root.min_size=Vector2i.ZERO
	root.content_scale_size=Vector2i.ZERO
	for dimensions in [Vector2i(1000,625),Vector2i(1440,900),Vector2i(1000,900)]:
		root.size=dimensions
		var app=load("res://main.tscn").instantiate()
		root.add_child(app)
		await frames(6)
		app.set_workspace("planar")
		app.ecology.paused=true
		await frames(6)
		var e=app.ecology
		var viewport=root.get_visible_rect()
		var panel=e.panel.get_global_rect()
		var area=e._area()
		var clip=e.panel.get_child(0).get_global_rect()
		var fits=true
		var controls=[e.interaction_button,e.reproduction_button,e.mod_button]
		for row in e.sliders.values(): controls.append(row[0])
		for c in controls:
			var r=c.get_global_rect()
			fits= fits and r.position.x>=clip.position.x and r.end.x<=clip.end.x
		check(viewport.encloses(panel) and panel.end.x<=viewport.end.x-11 and panel.size.x>=e.panel.get_combined_minimum_size().x,str(dimensions)+" rail minimum/right bound")
		check(fits,str(dimensions)+" eleven control horizontal bounds")
		check(Rect2(Vector2.ZERO,e.size).encloses(area) and area.end.x<e.panel.position.x,str(dimensions)+" world excludes actual rail")
		var maxerror=0.0
		for p in [Vector2(.05,.05),Vector2(.5,.5),Vector2(.95,.95)]: maxerror=maxf(maxerror,p.distance_to((e._screen(p,area)-area.position)/area.size))
		check(maxerror<.000001,str(dimensions)+" coordinate roundtrip")
		var original=e.world.config.interactions
		var toggle=e.interaction_button.get_global_rect()
		var point=Vector2(toggle.end.x-12,toggle.get_center().y)
		await click(point)
		check(e.world.config.interactions!=original,str(dimensions)+" actual far-right checkbox toggles")
		await click(point)
		check(e.world.config.interactions==original,str(dimensions)+" actual far-right checkbox restores")
		var slider=e.sliders.growth[0].get_global_rect()
		await click(Vector2(slider.end.x-1,slider.get_center().y))
		check(e.world.config.params.growth>1.99,str(dimensions)+" actual far-right slider reaches maximum")
		e.tools.select(1)
		e.family.select(2)
		var count=e.world.organisms.size()
		await click(e._screen(Vector2(.5,.5),area))
		var organism=e.world.organisms[-1]
		check(e.world.organisms.size()==count+1 and organism.p.distance_to(Vector2(.5,.5))<.00001,str(dimensions)+" actual canvas plant maps to intended coordinate")
		e.tools.select(0)
		await click(e._screen(organism.p,area))
		check(e.selected==organism.id,str(dimensions)+" actual canvas selects planted identity")
		cases.append({"requested":str(dimensions),"viewport":rv(viewport),"panel":rv(panel),"minimum_width":e.panel.get_combined_minimum_size().x,"world_area":rv(area),"roundtrip_error":maxerror,"plant_error":organism.p.distance_to(Vector2(.5,.5))})
		root.remove_child(app)
		app.free()
		await frames(2)
	print("PLANAR_LAYOUT_INPUT ",JSON.stringify({"checks":checks,"failures":failures,"status":"PASS" if failures.is_empty() else "FAIL","cases":cases,"scope":"Headless actual Control event routing via Viewport.push_input; full Windows graphical qualification remains required"}))
	quit(0 if failures.is_empty() else 1)
