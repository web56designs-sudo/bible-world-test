extends Node

const LANES := [-2.35, 0.0, 2.35]
const PLAYER_Z := 0.0
const BASE_SPEED := 12.0
const ENCOUNTER_COUNT := 6

var world_root: Node3D
var runner: Node3D
var runner_body: Node3D
var camera: Camera3D
var whirlwind: Node3D
var track_nodes: Array[Node3D] = []
var obstacle_nodes: Array[Dictionary] = []
var pickup_nodes: Array[Dictionary] = []

var lane := 1
var target_x := 0.0
var jump_y := 0.0
var jump_velocity := 0.0
var slide_left := 0.0
var run_time := 0.0
var distance_run := 0.0
var next_spawn_z := -28.0
var shields := 3
var score := 0
var waymarks := 0
var encounter_index := 0
var encounter_active := false
var thinking := false
var paused := false
var feedback_left := 0.0
var feedback_correct := false
var finished := false

# Expected Decision Time system.
var encounter_elapsed := 0.0
var encounter_edt := 6.0
var encounter_timeout := 10.0
var pace_scale := 1.0
var current_encounter: Dictionary = {}
var encounters: Array = []

var touch_start := Vector2.ZERO
var touch_active := false
var mouse_start := Vector2.ZERO
var mouse_active := false

var ui: CanvasLayer
var hud: Control
var shield_label: Label
var score_label: Label
var progress_bar: ProgressBar
var chase_bar: ProgressBar
var chase_label: Label
var message_label: Label
var encounter_panel: PanelContainer
var clue_label: Label
var answer_box: VBoxContainer
var think_button: Button
var pause_button: Button
var feedback_panel: PanelContainer
var feedback_label: Label

func _ready() -> void:
	load_encounters()
	build_world()
	build_ui()
	reset_track()
	show_message("SWIPE to move • UP jump • DOWN slide", 3.5)

func load_encounters() -> void:
	var file := FileAccess.open("res://content/encounters.json", FileAccess.READ)
	if file == null:
		push_error("Missing encounters.json")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		encounters = parsed

func build_world() -> void:
	world_root = Node3D.new()
	add_child(world_root)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("9ec9d8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("ffe6b8")
	env.ambient_light_energy = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color("d8bd91")
	env.fog_density = 0.012
	env_node.environment = env
	world_root.add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color("fff0c7")
	sun.light_energy = 1.5
	sun.rotation_degrees = Vector3(-48, -28, 0)
	sun.shadow_enabled = true
	world_root.add_child(sun)

	camera = Camera3D.new()
	camera.position = Vector3(0, 5.8, 9.2)
	camera.fov = 62.0
	camera.look_at_from_position(camera.position, Vector3(0, 1.1, -10.0))
	world_root.add_child(camera)

	build_scenery()
	build_runner()
	build_whirlwind()

func build_scenery() -> void:
	for i in 8:
		var segment := Node3D.new()
		segment.position.z = -float(i) * 14.0 + 7.0
		world_root.add_child(segment)
		track_nodes.append(segment)

		var road := mesh_instance(BoxMesh.new(), Vector3(7.8, 0.22, 14.2), Color("c99862"))
		road.position.y = -0.18
		segment.add_child(road)

		for lx in [-3.95, 3.95]:
			var edge := mesh_instance(BoxMesh.new(), Vector3(0.15, 0.08, 14.2), Color("e8c489"))
			edge.position = Vector3(lx, 0.02, 0)
			segment.add_child(edge)

		for lane_line in [-1.18, 1.18]:
			for d in 7:
				var dash := mesh_instance(BoxMesh.new(), Vector3(0.055, 0.025, 0.9), Color("efd9ab"))
				dash.position = Vector3(lane_line, 0.01, -5.5 + d * 2.0)
				segment.add_child(dash)

		# Stylised Egyptian roadside silhouettes.
		for side in [-1, 1]:
			var x := float(side) * 6.0
			var pillar := mesh_instance(CylinderMesh.new(), Vector3(0.65, 3.0, 0.65), Color("c8a06d"))
			pillar.position = Vector3(x, 1.5, -3.0)
			segment.add_child(pillar)
			var cap := mesh_instance(BoxMesh.new(), Vector3(1.1, 0.35, 1.1), Color("b48351"))
			cap.position = Vector3(x, 3.05, -3.0)
			segment.add_child(cap)

	var sun_disc := mesh_instance(SphereMesh.new(), Vector3(2.3, 2.3, 2.3), Color("ffd67a"), true)
	sun_disc.position = Vector3(11, 11, -32)
	world_root.add_child(sun_disc)

func build_runner() -> void:
	runner = Node3D.new()
	runner.position = Vector3(0, 0, PLAYER_Z)
	world_root.add_child(runner)
	runner_body = Node3D.new()
	runner.add_child(runner_body)

	var torso := mesh_instance(CapsuleMesh.new(), Vector3(0.78, 1.15, 0.58), Color("d89b54"))
	torso.position.y = 1.15
	runner_body.add_child(torso)
	var head := mesh_instance(SphereMesh.new(), Vector3(0.52, 0.52, 0.52), Color("9a6040"))
	head.position = Vector3(0, 2.03, 0)
	runner_body.add_child(head)
	var scarf := mesh_instance(BoxMesh.new(), Vector3(0.75, 0.14, 0.24), Color("2d5960"))
	scarf.position = Vector3(0, 1.65, 0.08)
	runner_body.add_child(scarf)
	for x in [-0.22, 0.22]:
		var leg := mesh_instance(CapsuleMesh.new(), Vector3(0.22, 0.72, 0.22), Color("27454c"))
		leg.position = Vector3(x, 0.43, 0)
		runner_body.add_child(leg)

func build_whirlwind() -> void:
	whirlwind = Node3D.new()
	whirlwind.position = Vector3(0, 0, 4.8)
	world_root.add_child(whirlwind)

	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 1.25
	cone_mesh.bottom_radius = 0.22
	cone_mesh.height = 3.3
	var core := mesh_instance(cone_mesh, Vector3.ONE, Color(0.58,0.38,0.25,0.42), true)
	core.position.y = 1.65
	whirlwind.add_child(core)
	for i in 5:
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.42 + float(i) * 0.09
		ring_mesh.outer_radius = 0.58 + float(i) * 0.13
		var ring := mesh_instance(ring_mesh, Vector3.ONE, Color(0.78,0.58,0.38,0.68), true)
		ring.position.y = 0.45 + float(i) * 0.58
		ring.rotation_degrees.x = 90
		ring.set_meta("spin", 1.0 + float(i) * 0.35)
		whirlwind.add_child(ring)

func mesh_instance(mesh: Mesh, scale_value: Vector3, color: Color, transparent := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.scale = scale_value
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.82
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = mat
	return node

func build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)

	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(hud)

	var top := HBoxContainer.new()
	top.position = Vector2(18, 18)
	top.size = Vector2(504, 52)
	top.add_theme_constant_override("separation", 14)
	hud.add_child(top)

	shield_label = Label.new()
	shield_label.text = "SHIELDS ◆◆◆"
	shield_label.add_theme_font_size_override("font_size", 20)
	top.add_child(shield_label)

	score_label = Label.new()
	score_label.text = "0"
	score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.add_theme_font_size_override("font_size", 20)
	top.add_child(score_label)

	pause_button = Button.new()
	pause_button.text = "Ⅱ"
	pause_button.custom_minimum_size = Vector2(52, 46)
	pause_button.pressed.connect(toggle_pause)
	top.add_child(pause_button)

	progress_bar = ProgressBar.new()
	progress_bar.position = Vector2(18, 75)
	progress_bar.size = Vector2(504, 10)
	progress_bar.max_value = ENCOUNTER_COUNT
	progress_bar.show_percentage = false
	hud.add_child(progress_bar)

	chase_label = Label.new()
	chase_label.text = "WHIRLWIND DISTANCE"
	chase_label.position = Vector2(18, 92)
	chase_label.add_theme_font_size_override("font_size", 12)
	hud.add_child(chase_label)
	chase_bar = ProgressBar.new()
	chase_bar.position = Vector2(18, 112)
	chase_bar.size = Vector2(504, 15)
	chase_bar.min_value = 0
	chase_bar.max_value = 100
	chase_bar.value = 100
	chase_bar.show_percentage = false
	hud.add_child(chase_bar)

	message_label = Label.new()
	message_label.position = Vector2(20, 150)
	message_label.size = Vector2(500, 60)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 22)
	message_label.modulate = Color("fff0bd")
	hud.add_child(message_label)

	encounter_panel = PanelContainer.new()
	encounter_panel.position = Vector2(20, 485)
	encounter_panel.size = Vector2(500, 430)
	encounter_panel.visible = false
	encounter_panel.add_theme_stylebox_override("panel", panel_style(Color(0.055,0.09,0.11,0.94), 22))
	hud.add_child(encounter_panel)
	var encounter_margin := MarginContainer.new()
	encounter_margin.add_theme_constant_override("margin_left", 20)
	encounter_margin.add_theme_constant_override("margin_right", 20)
	encounter_margin.add_theme_constant_override("margin_top", 16)
	encounter_margin.add_theme_constant_override("margin_bottom", 16)
	encounter_panel.add_child(encounter_margin)
	var encounter_v := VBoxContainer.new()
	encounter_v.add_theme_constant_override("separation", 10)
	encounter_margin.add_child(encounter_v)
	var title := Label.new()
	title.text = "BIBLE ENCOUNTER"
	title.add_theme_font_size_override("font_size", 16)
	title.modulate = Color("efbd69")
	encounter_v.add_child(title)
	clue_label = Label.new()
	clue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	clue_label.add_theme_font_size_override("font_size", 18)
	clue_label.custom_minimum_size.y = 122
	encounter_v.add_child(clue_label)
	answer_box = VBoxContainer.new()
	answer_box.add_theme_constant_override("separation", 8)
	encounter_v.add_child(answer_box)
	think_button = Button.new()
	think_button.text = "THINK — stop running, whirlwind keeps coming"
	think_button.custom_minimum_size.y = 48
	think_button.pressed.connect(toggle_think)
	encounter_v.add_child(think_button)

	feedback_panel = PanelContainer.new()
	feedback_panel.position = Vector2(24, 565)
	feedback_panel.size = Vector2(492, 285)
	feedback_panel.visible = false
	feedback_panel.add_theme_stylebox_override("panel", panel_style(Color(0.04,0.07,0.08,0.97), 22))
	hud.add_child(feedback_panel)
	var fm := MarginContainer.new()
	fm.add_theme_constant_override("margin_left", 22)
	fm.add_theme_constant_override("margin_right", 22)
	fm.add_theme_constant_override("margin_top", 22)
	fm.add_theme_constant_override("margin_bottom", 22)
	feedback_panel.add_child(fm)
	feedback_label = Label.new()
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	feedback_label.add_theme_font_size_override("font_size", 18)
	fm.add_child(feedback_label)

func panel_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.92,0.70,0.34,0.45)
	return style

func _process(delta: float) -> void:
	if paused or finished:
		animate_whirlwind(delta * 0.18)
		return

	run_time += delta
	if feedback_left > 0.0:
		feedback_left -= delta
		animate_whirlwind(delta * 0.35)
		if feedback_left <= 0.0:
			feedback_panel.visible = false
			if shields <= 0:
				end_run(false)
			else:
				resume_after_feedback()
		return

	var speed := BASE_SPEED
	if encounter_active:
		encounter_elapsed += delta
		if thinking:
			speed = 0.0
		else:
			speed = BASE_SPEED * 0.78
		update_encounter_pressure()
		if encounter_elapsed >= encounter_timeout:
			resolve_answer(-1)
	else:
		distance_run += speed * delta
		if distance_run > 54.0 + float(encounter_index) * 58.0 and encounter_index < min(ENCOUNTER_COUNT, encounters.size()):
			start_encounter()

	move_world(delta, speed)
	move_runner(delta)
	animate_whirlwind(delta)
	update_hud()

func move_world(delta: float, speed: float) -> void:
	for segment in track_nodes:
		segment.position.z += speed * delta
		if segment.position.z > 14.0:
			segment.position.z -= 112.0

	if not encounter_active:
		ensure_obstacles()
	for item in obstacle_nodes.duplicate():
		var node: Node3D = item.node
		node.position.z += speed * delta
		if node.position.z > 4.0:
			obstacle_nodes.erase(item)
			node.queue_free()
			continue
		if not item.hit and node.position.z > -0.55 and node.position.z < 0.65 and int(item.lane) == lane:
			item.hit = true
			var avoided := false
			if item.type == "jump":
				avoided = jump_y > 0.82
			elif item.type == "slide":
				avoided = slide_left > 0.05
			else:
				avoided = false
			if not avoided:
				movement_mistake()
			else:
				score += 25

	for item in pickup_nodes.duplicate():
		var node: Node3D = item.node
		node.position.z += speed * delta
		node.rotate_y(delta * 2.7)
		if node.position.z > 4.0:
			pickup_nodes.erase(item)
			node.queue_free()
		elif node.position.z > -0.5 and node.position.z < 0.7 and int(item.lane) == lane:
			waymarks += 1
			score += 10
			pickup_nodes.erase(item)
			node.queue_free()

func ensure_obstacles() -> void:
	if obstacle_nodes.size() + pickup_nodes.size() > 9:
		return
	var farthest := -12.0
	for item in obstacle_nodes:
		farthest = minf(farthest, float(item.node.position.z))
	for item in pickup_nodes:
		farthest = minf(farthest, float(item.node.position.z))
	while obstacle_nodes.size() + pickup_nodes.size() < 9:
		farthest -= randf_range(5.5, 8.5)
		var pick := randi() % 5
		var spawn_lane := randi() % 3
		if pick <= 2:
			spawn_obstacle(spawn_lane, farthest, "jump" if pick < 2 else "slide")
		else:
			spawn_pickup(spawn_lane, farthest)

func spawn_obstacle(spawn_lane: int, z: float, kind: String) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(LANES[spawn_lane], 0, z)
	world_root.add_child(holder)
	if kind == "jump":
		var rock := mesh_instance(BoxMesh.new(), Vector3(1.35, 0.85, 0.72), Color("7d6752"))
		rock.position.y = 0.43
		holder.add_child(rock)
	else:
		for x in [-0.68, 0.68]:
			var post := mesh_instance(BoxMesh.new(), Vector3(0.18, 2.25, 0.22), Color("765138"))
			post.position = Vector3(x, 1.12, 0)
			holder.add_child(post)
		var beam := mesh_instance(BoxMesh.new(), Vector3(1.65, 0.28, 0.34), Color("9a693f"))
		beam.position.y = 1.55
		holder.add_child(beam)
	obstacle_nodes.append({"node":holder,"lane":spawn_lane,"type":kind,"hit":false})

func spawn_pickup(spawn_lane: int, z: float) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(LANES[spawn_lane], 1.0, z)
	world_root.add_child(holder)
	var gem := mesh_instance(OctahedronMesh.new(), Vector3(0.34,0.50,0.34), Color("f0c05e"), true)
	holder.add_child(gem)
	pickup_nodes.append({"node":holder,"lane":spawn_lane})

func move_runner(delta: float) -> void:
	target_x = LANES[lane]
	runner.position.x = lerpf(runner.position.x, target_x, clampf(delta * 12.0, 0, 1))
	if jump_y > 0.0 or jump_velocity > 0.0:
		jump_velocity -= 18.5 * delta
		jump_y = maxf(0.0, jump_y + jump_velocity * delta)
		if jump_y <= 0.0 and jump_velocity < 0:
			jump_velocity = 0.0
	runner.position.y = jump_y
	slide_left = maxf(0.0, slide_left - delta)
	var slide_amount := 0.48 if slide_left > 0 else 1.0
	runner_body.scale.y = lerpf(runner_body.scale.y, slide_amount, clampf(delta * 15.0,0,1))
	var bob := sin(run_time * 14.0) * 0.045 if not thinking else 0.0
	runner_body.position.y = bob
	runner_body.rotation_degrees.z = lerpf(runner_body.rotation_degrees.z, (runner.position.x-target_x)*-8.0, clampf(delta*8.0,0,1))

func animate_whirlwind(delta: float) -> void:
	for child in whirlwind.get_children():
		if child.has_meta("spin"):
			child.rotate_z(delta * float(child.get_meta("spin")) * 3.0)
	whirlwind.position.x = lerpf(whirlwind.position.x, runner.position.x, clampf(delta*3.5,0,1))

func movement_mistake() -> void:
	score = maxi(0, score - 20)
	camera.fov = 68.0
	show_message("STUMBLE — the whirlwind gains!", 1.1)
	if not encounter_active:
		whirlwind.position.z = maxf(1.8, whirlwind.position.z - 0.55)

func start_encounter() -> void:
	clear_hazards()
	encounter_active = true
	thinking = false
	encounter_elapsed = 0.0
	current_encounter = encounters[encounter_index]
	encounter_edt = calculate_edt(current_encounter)
	encounter_timeout = clampf(encounter_edt * 1.48 + 1.1, 7.0, 14.5)
	whirlwind.position.z = 4.8
	show_encounter()
	show_message("READ • RECOGNISE • ANSWER", 1.2)

func calculate_edt(q: Dictionary) -> float:
	var words := 0
	for clue in q.clues:
		words += String(clue).split(" ", false).size()
	for option in q.options:
		words += String(option).split(" ", false).size()
	# Prototype baseline: ~190 words/min plus comprehension/choice allowance.
	var reading_seconds := float(words) / 3.15
	var comprehension := 1.35 + float(q.get("difficulty",1.0)) * 0.85
	var raw := reading_seconds + comprehension
	# Personal pace adaptation is deliberately bounded to avoid punishing slower readers.
	return clampf(raw * pace_scale, 4.8, 10.5)

func update_encounter_pressure() -> void:
	var p := clampf(encounter_elapsed / encounter_timeout, 0.0, 1.0)
	# Gentle while reading; increasingly urgent near the expected decision point.
	var curved := pow(p, 1.55)
	var z_far := 4.8
	var z_near := 0.72
	whirlwind.position.z = lerpf(z_far, z_near, curved)
	chase_bar.value = (1.0 - curved) * 100.0
	if encounter_elapsed >= encounter_edt:
		camera.fov = lerpf(camera.fov, 67.0 + p*5.0, 0.10)
		chase_label.text = "WHIRLWIND CLOSING — ANSWER!"
	else:
		camera.fov = lerpf(camera.fov, 62.0, 0.08)
		chase_label.text = "WHIRLWIND DISTANCE"

func show_encounter() -> void:
	encounter_panel.visible = true
	clue_label.text = "1  %s\n2  %s\n3  %s" % [current_encounter.clues[0], current_encounter.clues[1], current_encounter.clues[2]]
	for child in answer_box.get_children():
		child.queue_free()
	for i in current_encounter.options.size():
		var button := Button.new()
		button.text = "%d   %s" % [i+1, current_encounter.options[i]]
		button.custom_minimum_size.y = 49
		button.add_theme_font_size_override("font_size", 18)
		button.pressed.connect(func(): resolve_answer(i))
		answer_box.add_child(button)
	think_button.text = "THINK — stop running, whirlwind keeps coming"

func resolve_answer(choice: int) -> void:
	if not encounter_active:
		return
	var correct := choice == int(current_encounter.answer)
	var response_time := encounter_elapsed
	encounter_active = false
	thinking = false
	encounter_panel.visible = false

	# Slowly learn the player's interaction pace, bounded to ±15%.
	var observed_ratio := clampf(response_time / maxf(encounter_edt,0.1), 0.75, 1.35)
	var target_scale := clampf(0.88 + observed_ratio * 0.12, 0.90, 1.15)
	pace_scale = lerpf(pace_scale, target_scale, 0.18)

	if correct:
		feedback_correct = true
		var mastery := clampf(1.0 - response_time / encounter_timeout, 0.0, 1.0)
		score += 120 + int(mastery * 80.0)
		whirlwind.position.z = 5.6
		show_message("CORRECT — ESCAPE BURST!  %s" % current_encounter.reference, 2.2)
		encounter_index += 1
		progress_bar.value = encounter_index
		if encounter_index >= ENCOUNTER_COUNT:
			feedback_left = 1.7
		else:
			feedback_left = 1.2
	else:
		feedback_correct = false
		shields -= 1
		whirlwind.position.z = 1.0
		feedback_panel.visible = true
		var prefix := "TIME UP" if choice < 0 else "NOT QUITE"
		feedback_label.text = "%s\n\n%s\n\n%s\n\n%s" % [prefix, current_encounter.explanation, current_encounter.reference, "Danger is frozen while you read this explanation."]
		feedback_left = 5.2
		encounter_index += 1
		progress_bar.value = encounter_index
	update_hud()

func resume_after_feedback() -> void:
	camera.fov = 62.0
	chase_label.text = "WHIRLWIND DISTANCE"
	chase_bar.value = 100
	whirlwind.position.z = 4.5
	if encounter_index >= ENCOUNTER_COUNT:
		end_run(shields > 0)
	else:
		show_message("RUN!", 0.8)

func toggle_think() -> void:
	if not encounter_active or paused:
		return
	thinking = not thinking
	think_button.text = "RESUME RUNNING" if thinking else "THINK — stop running, whirlwind keeps coming"
	show_message("YOU STOPPED. THE WHIRLWIND DIDN'T." if thinking else "RUNNING AGAIN", 0.9)

func toggle_pause() -> void:
	if finished:
		return
	paused = not paused
	pause_button.text = "▶" if paused else "Ⅱ"
	show_message("PAUSED — everything is frozen" if paused else "GO!", 1.0)

func clear_hazards() -> void:
	for item in obstacle_nodes:
		if is_instance_valid(item.node): item.node.queue_free()
	for item in pickup_nodes:
		if is_instance_valid(item.node): item.node.queue_free()
	obstacle_nodes.clear()
	pickup_nodes.clear()

func reset_track() -> void:
	lane = 1
	runner.position = Vector3.ZERO
	whirlwind.position = Vector3(0,0,4.8)
	ensure_obstacles()

func end_run(success: bool) -> void:
	finished = true
	clear_hazards()
	encounter_panel.visible = false
	feedback_panel.visible = true
	if success:
		feedback_label.text = "JOURNEY COMPLETE\n\nYou reached the destination with %d shield(s) remaining.\n\nMovement score: %d\nWaymarks: %d\n\nBible World 3D vertical slice" % [shields, score, waymarks]
	else:
		feedback_label.text = "THE WHIRLWIND CAUGHT UP\n\nThis is a gameplay result, not a measure of faith.\n\nRestart the page to try the vertical slice again."

func update_hud() -> void:
	shield_label.text = "SHIELDS " + "◆".repeat(maxi(0,shields)) + "◇".repeat(maxi(0,3-shields))
	score_label.text = "%06d  ✦%d" % [score, waymarks]
	if not encounter_active:
		chase_bar.value = clampf((whirlwind.position.z-0.7)/(4.8-0.7)*100.0,0,100)
	camera.fov = lerpf(camera.fov, 62.0, 0.025) if not encounter_active else camera.fov

var message_left := 0.0
func show_message(text: String, duration: float) -> void:
	message_label.text = text
	message_left = duration

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_start = event.position
			touch_active = true
		else:
			if touch_active:
				handle_swipe(event.position - touch_start)
			touch_active = false
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			mouse_start = event.position
			mouse_active = true
		else:
			if mouse_active:
				handle_swipe(event.position - mouse_start)
			mouse_active = false

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or paused or finished or encounter_active:
		return
	if event.is_action("move_left"): change_lane(-1)
	elif event.is_action("move_right"): change_lane(1)
	elif event.is_action("jump"): do_jump()
	elif event.is_action("slide"): do_slide()

func handle_swipe(delta: Vector2) -> void:
	if paused or finished or encounter_active or delta.length() < 42.0:
		return
	if absf(delta.x) > absf(delta.y):
		change_lane(-1 if delta.x < 0 else 1)
	else:
		if delta.y < 0: do_jump()
		else: do_slide()

func change_lane(direction: int) -> void:
	lane = clampi(lane + direction, 0, 2)

func do_jump() -> void:
	if jump_y <= 0.02 and slide_left <= 0:
		jump_velocity = 7.4

func do_slide() -> void:
	if jump_y <= 0.02:
		slide_left = 0.82
