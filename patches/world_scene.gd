class_name JourneyWorld
extends Control
signal collected
signal stumbled

var rules: JourneyRules
var world_index := 0
var animation_time := 0.0
var road_offset := 0.0
var jump_height := 0.0
var jump_speed := 0.0
var stumble_time := 0.0
var celebrate := 0.0
var reduced_motion := false
var decorative := true
var items: Array = []
var last_state := ""
var segment_index := 0
var visual_gap_ratio := 0.90

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func reset_segment() -> void:
	segment_index += 1
	items = [{"x":720.0,"type":"scroll","hit":false},{"x":980.0,"type":"rock","hit":false},{"x":1110.0,"type":"scroll","hit":false},{"x":1350.0,"type":"scroll","hit":false}]
	jump_height = 0
	jump_speed = 0
	if rules:
		rules.available_scrolls += 3

func jump() -> void:
	if rules and rules.state == "running" and jump_height <= 1:
		jump_speed = 480

func step(delta: float) -> void:
	if rules and rules.state in ["paused","feedback","result"] and not decorative:
		return
	animation_time += delta * (0.35 if reduced_motion else 1.0)
	# Smooth the pursuer's visible approach so the chase reads as intentional,
	# not as a storm snapping to the traveller. The logical gap still owns timing.
	var target_gap_ratio := 0.90
	if not decorative and rules:
		var display_state: String = rules.previous_state if rules.state == "paused" else rules.state
		if display_state in ["preparation","question_running","thinking","feedback"]:
			target_gap_ratio = clampf(rules.gap / maxf(rules.initial_gap, 0.001), 0.0, 1.0)
			if display_state == "feedback" and not rules.result.get("correct",false):
				target_gap_ratio = 0.05
	var chase_lerp := 2.2 if not reduced_motion else 1.4
	visual_gap_ratio = lerpf(visual_gap_ratio,target_gap_ratio,clampf(delta*chase_lerp,0.0,1.0))
	if decorative:
		road_offset += delta * 25
	elif rules:
		if rules.state == "running":
			road_offset += delta * 180
			jump_height += jump_speed * delta
			jump_speed -= delta * 1250
			if jump_height < 0:
				jump_height = 0
				jump_speed = 0
			for item in items:
				item.x -= delta * 240
				if not item.hit and absf(item.x - size.x * 0.62) < 30:
					item.hit = true
					if item.type == "scroll":
						rules.scrolls += 1
						collected.emit()
					elif jump_height < 42:
						stumble_time = 0.5
						stumbled.emit()
		elif rules.state in ["preparation","question_running"]:
			road_offset += delta * 100
		stumble_time = maxf(0,stumble_time - delta)
	celebrate = maxf(0,celebrate - delta)
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	var ground := h * 0.80
	var skies := [Color("b7d6d2"),Color("dfcbaa"),Color("a7d2df")]
	var sky: Color = skies[world_index % 3]
	for i in 24:
		var col := sky.lerp(Color("f6e9cc"),float(i)/24)
		draw_rect(Rect2(0,float(i)*h/24,w,h/24+1),col)
	draw_circle(Vector2(w*0.80,h*0.22),31,Color("fff0bb"))
	draw_circle(Vector2(w*0.80,h*0.22),45,Color(1,0.93,0.7,0.14))
	for layer in 3:
		var points := PackedVector2Array([Vector2(-250,h)])
		for i in range(-1,9):
			var x := float(i)*100 - fmod(road_offset * (0.025 + layer * 0.025),100)
			var y := ground - 40 - layer*12 - sin(float(i)*1.2 + world_index)* (22+layer*9)
			points.append(Vector2(x,y))
		points.append(Vector2(w+400,h))
		var hill: Color = [Color("a5b99b"),Color("c5af8a"),Color("7db1b2")][world_index % 3]
		draw_colored_polygon(points,hill.darkened(layer*0.075))
	if world_index == 1:
		for i in 3:
			var x := float(i)*170+210-fmod(road_offset*0.04,170)
			draw_colored_polygon(PackedVector2Array([Vector2(x-60,ground-35),Vector2(x,ground-120),Vector2(x+70,ground-35)]),Color("b68e68"))
	else:
		for i in 5:
			var x := float(i)*120-40-fmod(road_offset*0.09,120)
			var ht := 45+sin(float(i)*3.0)*15
			draw_rect(Rect2(x,ground-ht-25,65,ht),Color("d6c3a1") if world_index==0 else Color("d9c6a5"))
			draw_colored_polygon(PackedVector2Array([Vector2(x-5,ground-ht-25),Vector2(x+32,ground-ht-42),Vector2(x+70,ground-ht-25)]),Color("a57555"))
			draw_rect(Rect2(x+23,ground-55,15,30),Color("947657"))
			for j in 2:
				draw_rect(Rect2(x+9+j*31,ground-ht-14,10,12),Color("947657"))
	if world_index == 2:
		draw_rect(Rect2(0,ground-22,w,37),Color("72a8b0"))
		for i in 8:
			var x := fmod(float(i)*88-road_offset*0.3+w*20,w+70)
			draw_line(Vector2(x,ground-12),Vector2(x+30,ground-12),Color("c4e5df"),2)
	draw_rect(Rect2(0,ground,w,h-ground),Color("c99e70"))
	draw_rect(Rect2(0,ground,w,8),Color("ebc795"))
	for i in 12:
		var x := fmod(float(i)*63-road_offset+w*100,w+63)
		draw_line(Vector2(x,ground+25),Vector2(x+22,ground+23),Color("b68a5d"),2)
	var display_state: String = rules.previous_state if rules and rules.state == "paused" else (rules.state if rules else "idle")
	var position := Vector2(w*0.62,ground-jump_height)
	if decorative:position.x=w*0.65
	var ratio := visual_gap_ratio
	# Three readable chase bands: safe (roughly 35% of screen behind), warning
	# (about 22%), and critical (about 15%). The whirlwind never sits directly
	# on the traveller during normal play, so there is always visible breathing room.
	var critical_gap := w * 0.15
	var safe_extra_gap := w * 0.22
	var eased_ratio := smoothstep(0.0,1.0,ratio)
	var whirlwind_x := position.x - critical_gap - eased_ratio * safe_extra_gap
	# The pursuer follows the traveller's chase line but stays grounded. It only
	# reacts slightly to jumps so it never looks physically attached to the runner.
	var tracking_y := ground - minf(jump_height * 0.10, h * 0.018)
	draw_whirlwind(Vector2(whirlwind_x,tracking_y),ground,h,ratio)
	if not decorative and rules and display_state == "running":
		for item in items:
			if item.hit:continue
			if item.type=="rock":
				draw_circle(Vector2(item.x,ground+3),24,Color("86735c"))
				draw_circle(Vector2(item.x-5,ground-4),17,Color("a28c6e"))
			else:
				draw_scroll(Vector2(item.x,ground-45+sin(animation_time*3+item.x)*3))
	var running := decorative or (rules and display_state in ["running","preparation","question_running"])
	var stride := sin(animation_time*12) if running else 0.0
	if reduced_motion:stride *= 0.55
	draw_traveller(position,stride,1.2 if decorative else 1.0)
	if celebrate > 0:
		for i in 9:
			var theta := float(i)*TAU/9
			var point := position+Vector2(cos(theta),sin(theta))*(38+(1-celebrate)*32)+Vector2(0,-52)
			draw_circle(point,3,Color("fff2bc"))
	# Ground foliage in the foreground.
	if world_index != 1:
		for i in 4:
			var x := float(i)*165+55-fmod(road_offset*0.4,165)
			for j in 3:
				draw_line(Vector2(x,ground+2),Vector2(x+float(j-1)*8,ground-15-j*3),Color("637b55"),3)

func draw_whirlwind(center: Vector2, ground: float, h: float, gap_ratio: float) -> void:
	# A compact tapered funnel. It should read as a pursuer, not a screen-wide hazard.
	var height := h * 0.28
	var top_y := center.y - height
	var base_y := ground + 4.0
	var body := Color("a97858")
	var dust := Color("d3ab82")
	var dark_dust := Color("805d47")
	# Wider, slower rings at the top; tight fast rings toward the base.
	for i in 9:
		var t := float(i) / 8.0
		var y := lerpf(top_y, base_y - 8.0, t)
		var radius := lerpf(size.x * 0.062, size.x * 0.018, t)
		var wobble := sin(animation_time * (2.0 + t * 3.0) + float(i) * 1.4) * radius * 0.18
		var ring_center := Vector2(center.x + wobble, y)
		draw_arc(ring_center,radius,0.10,TAU-0.15,30,body.lightened(0.08+t*0.10),5.0 if i < 4 else 3.5)
		draw_arc(ring_center,radius*0.72,PI*0.45,PI*1.75,22,dark_dust.lightened(t*0.12),2.0)
	# Dense core gives the funnel a readable silhouette on small phone screens.
	var funnel := PackedVector2Array([
		Vector2(center.x-size.x*0.046,top_y+10),
		Vector2(center.x+size.x*0.046,top_y+10),
		Vector2(center.x+size.x*0.014,base_y-5),
		Vector2(center.x-size.x*0.012,base_y-5)
	])
	draw_colored_polygon(funnel,Color(body.r,body.g,body.b,0.18))
	# Orbiting dust stays local to the whirlwind instead of spanning the screen.
	for i in 14:
		var t := float(i) / 13.0
		var py := lerpf(top_y+8.0,base_y-12.0,t)
		var orbit := lerpf(size.x*0.072,size.x*0.021,t)
		var phase := animation_time * (1.8 + t*2.4) + float(i)*1.7
		var px := center.x + cos(phase) * orbit
		draw_circle(Vector2(px,py),3.0 + float(i%3),dust.lightened(0.08))
	# Ground dust communicates speed, but remains narrower than the traveller-whirlwind gap.
	var ground_spread := size.x * 0.075
	for i in 6:
		var px := center.x-ground_spread*0.5 + fmod(float(i)*19.0+animation_time*28.0,ground_spread)
		draw_arc(Vector2(px,ground+2.0),8.0+float(i%2)*4.0,PI,TAU,10,dust,2.0)
	# The closer the chase, the stronger the subtle outer swirl; never enlarge it to full width.
	var urgency := 1.0-gap_ratio
	if urgency > 0.55:
		draw_arc(Vector2(center.x,top_y+height*0.42),size.x*0.075,0.0,TAU,34,Color(dust.r,dust.g,dust.b,0.28*urgency),3.0)

func draw_scroll(pos: Vector2) -> void:
	draw_circle(pos,20,Color(1,0.85,0.45,0.15))
	draw_rect(Rect2(pos+Vector2(-12,-13),Vector2(24,27)),Color("fff0c4"))
	draw_line(pos+Vector2(-7,-5),pos+Vector2(6,-5),Color("c6924b"),2)
	draw_line(pos+Vector2(-7,1),pos+Vector2(6,1),Color("c6924b"),2)
	draw_line(pos+Vector2(-7,7),pos+Vector2(3,7),Color("c6924b"),2)
	draw_circle(pos+Vector2(-13,-13),4,Color("e3b66b"))
	draw_circle(pos+Vector2(13,13),4,Color("e3b66b"))

func draw_traveller(origin: Vector2, stride: float, scale_value: float) -> void:
	draw_set_transform(origin+Vector2(0,4),0,Vector2(scale_value,scale_value*0.25))
	draw_circle(Vector2.ZERO,26,Color(0.3,0.2,0.12,0.2))
	draw_set_transform(origin,0,Vector2.ONE*scale_value)
	var skin := Color("9b6342")
	var dark := Color("29484e")
	# Two boots and the moving legs.
	draw_line(Vector2(-4,-29),Vector2(-12-stride*13,-4),dark,9)
	draw_line(Vector2(9,-29),Vector2(14+stride*13,-4),dark,9)
	draw_line(Vector2(-14-stride*13,-3),Vector2(-4-stride*13,-3),Color("61432e"),8)
	draw_line(Vector2(12+stride*13,-3),Vector2(23+stride*13,-3),Color("61432e"),8)
	draw_colored_polygon(PackedVector2Array([Vector2(-12,-60),Vector2(12,-60),Vector2(18,-28),Vector2(-15,-28)]),Color("dfa65e"))
	draw_line(Vector2(-9,-55),Vector2(-18+stride*12,-34),skin,7)
	draw_line(Vector2(10,-55),Vector2(22-stride*10,-37),skin,7)
	draw_circle(Vector2(0,-72),15,skin)
	draw_circle(Vector2(11,-71),6,skin)
	draw_circle(Vector2(0,-80),15,dark)
	draw_rect(Rect2(-16,-83,32,8),Color("ead7ae"))
	draw_line(Vector2(-12,-78),Vector2(-20,-59),Color("ead7ae"),7)
	draw_circle(Vector2(9,-74),1.7,Color("17272e"))
	draw_line(Vector2(7,-66),Vector2(13,-65),Color("623d2c"),1.4)
	draw_line(Vector2(-8,-59),Vector2(14,-30),Color("705138"),3)
	draw_rect(Rect2(8,-43,18,17),Color("825738"))
	draw_rect(Rect2(7,-45,20,6),Color("a27746"))
	draw_circle(Vector2(17,-39),2,Color("edc575"))
	draw_set_transform(Vector2.ZERO)

func draw_ellipse_shadow() -> void:
	draw_set_transform(Vector2(0,4),0,Vector2(1,0.25))
	draw_circle(Vector2.ZERO,26,Color(0.3,0.2,0.12,0.2))
	draw_set_transform(Vector2.ZERO)

func snapshot() -> Dictionary:
	return {"scene_height":size.y,"items":items.duplicate(true),"jump_height":jump_height,"jump_speed":jump_speed,"stumble_time":stumble_time,"road_offset":road_offset,"animation_time":animation_time,"segment_index":segment_index}

func restore(d: Dictionary) -> void:
	if d.has("scene_height"):size.y = d.scene_height
	for key in ["items","jump_height","jump_speed","stumble_time","road_offset","animation_time","segment_index"]:
		if d.has(key):set(key,d[key])
