extends SceneTree
var app
var checks := 0
var failures := []
func _initialize():
    run.call_deferred()
func frames(n):
    for i in range(n): await process_frame
func check(value, label):
    checks += 1
    if not value: failures.append(label)
func key(code, control=false, character=0):
    for pressed in [true,false]:
        var e=InputEventKey.new()
        e.keycode=code
        e.physical_keycode=code
        e.ctrl_pressed=control
        e.unicode=character
        e.pressed=pressed
        root.push_input(e,true)
        await frames(2)
func click(point):
    var move=InputEventMouseMotion.new()
    move.position=point
    move.global_position=point
    root.push_input(move,true)
    await frames(1)
    for pressed in [true,false]:
        var e=InputEventMouseButton.new()
        e.position=point
        e.global_position=point
        e.button_index=MOUSE_BUTTON_LEFT
        e.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
        e.pressed=pressed
        root.push_input(e,true)
        await frames(2)
func find_button(node,label):
    if node is Button and node.text==label: return node
    for child in node.get_children():
        var found=find_button(child,label)
        if found!=null: return found
    return null
func run():
    root.size=Vector2i(1440,900)
    app=load("res://main.tscn").instantiate()
    root.add_child(app)
    await frames(5)
    await key(KEY_F4)
    var life=app.life_panel
    var old_seed=int(app.ecology.world.config.seed)
    var edit=life.seed_control.get_line_edit()
    await click(edit.get_global_rect().get_center())
    await key(KEY_A,true)
    for c in "81234": await key(c.unicode_at(0),false,c.unicode_at(0))
    await create_timer(0.7).timeout
    check(edit.text=="81234","Typed seed text survives actual HUD refresh before Enter")
    await key(KEY_ENTER)
    await create_timer(0.7).timeout
    check(int(life.seed_control.value)==81234 and int(app.ecology.seed_box.value)==81234 and int(app.ecology.world.config.seed)==old_seed,"Committed pending seed survives actual HUD refresh without changing solver seed")
    await click(find_button(life,"Reset ecology").get_global_rect().get_center())
    check(int(app.ecology.world.config.seed)==81234 and app.ecology.world.tick==0,"Actual Reset button uses pending seed")
    var picker=app.ui.preset_picker
    await click(picker.get_global_rect().get_center())
    var popup=picker.get_popup()
    check(popup.visible,"Actual pointer opens scene recall")
    var chosen = app.Catalogue.index_of(app.presets,"composition.light_terrarium")
    var expected_seed = int(app.presets[chosen].ecology_config.seed)
    for i in range(picker.item_count+3):
        if popup.get_focused_item()==chosen: break
        await key(KEY_DOWN if popup.get_focused_item()<chosen else KEY_UP)
    await key(KEY_ENTER)
    await frames(3)
    await key(KEY_F4)
    check(app.preset_index==chosen and int(app.ecology.world.config.seed)==expected_seed and int(app.ecology.seed_box.value)==expected_seed and int(life.seed_control.value)==expected_seed,"Actual scene recall resets both pending and displayed seed")
    print("LIFE_SEED_AUTHORING ",JSON.stringify({"checks":checks,"failures":failures,"status":"PASS" if failures.is_empty() else "FAIL","typed_seed":81234,"recalled_seed":app.ecology.world.config.seed,"scope":"Headless actual Control event routing via Viewport.push_input; Windows graphical suite remains required"}))
    app.set_process(false)
    root.remove_child(app)
    app.free()
    await frames(2)
    quit(0 if failures.is_empty() else 1)
