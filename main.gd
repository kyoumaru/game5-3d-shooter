extends Node3D

const MOVE_SPEED := 6.0
const ACCEL := 12.0
const GRAVITY := 20.0
const MOUSE_SENS := 0.003
const SHOT_SPEED := 30.0          # slow enough to track
const SHOT_LIFETIME := 5.0
const FIRE_COOLDOWN := 0.25
const AIM_RANGE := 200.0
const WORLD_MASK := 1             # walls, floor, indestructible target
const ENEMY_MASK := 2             # enemies
const SHOULDER_X := 0.8

var player: CharacterBody3D
var pivot: Node3D                 # pitch pivot, camera hangs off this
var cam: Camera3D
var head: Node3D
var weapon: Node3D
var muzzle: Marker3D
var pitch := 0.0
var shoulder_side := 1.0
var cooldown := 0.0
var shots: Array = []
var aim_point := Vector3.ZERO
var shot_mat: StandardMaterial3D


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	shot_mat = _mat(Color(1.0, 0.9, 0.2), true)
	_build_world()
	_build_player()
	_build_ui()


# ---------------------------------------------------------------- helpers
func _mat(color: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _add_box(pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = WORLD_MASK
	b.collision_mask = 0
	b.position = pos
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	b.add_child(cs)
	add_child(b)
	return b


func _add_enemy(pos: Vector3) -> void:
	var color := Color(0.8, 0.25, 0.25)
	var b := StaticBody3D.new()
	b.collision_layer = ENEMY_MASK
	b.collision_mask = 0
	b.position = pos
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.8
	sm.height = 1.6
	mi.mesh = sm
	var mat := _mat(color)
	mi.material_override = mat
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.8
	cs.shape = shape
	b.add_child(cs)
	b.set_meta("hp", 3)           # 3 hits to destroy
	b.set_meta("mat", mat)
	b.set_meta("color", color)
	add_child(b)


# ---------------------------------------------------------------- world
func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.6, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.7)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)

	# floor
	_add_box(Vector3(0, -0.5, 0), Vector3(80, 1, 80), Color(0.35, 0.5, 0.35))
	# border walls
	var wall_col := Color(0.55, 0.55, 0.6)
	_add_box(Vector3(0, 3, -40), Vector3(80, 6, 1), wall_col)
	_add_box(Vector3(0, 3, 40), Vector3(80, 6, 1), wall_col)
	_add_box(Vector3(-40, 3, 0), Vector3(1, 6, 80), wall_col)
	_add_box(Vector3(40, 3, 0), Vector3(1, 6, 80), wall_col)
	# terrain to shoot at / around
	_add_box(Vector3(-8, 2, -12), Vector3(6, 4, 1), wall_col)
	_add_box(Vector3(10, 1.5, -8), Vector3(4, 3, 4), wall_col)
	_add_box(Vector3(-14, 1.5, 2), Vector3(3, 3, 3), wall_col)
	# large indestructible target (shots must land on its surface, not its center)
	_add_box(Vector3(0, 3, -34), Vector3(12, 6, 1), Color(0.8, 0.1, 0.1))

	for p in [Vector3(-6, 1, -18), Vector3(5, 1, -20), Vector3(14, 1, -2),
			Vector3(-16, 1, -24), Vector3(0, 1, -26), Vector3(18, 1, -18)]:
		_add_enemy(p)


# ---------------------------------------------------------------- player
func _build_player() -> void:
	player = CharacterBody3D.new()
	player.collision_layer = 4
	player.collision_mask = WORLD_MASK | ENEMY_MASK
	player.position = Vector3(0, 0.95, 12)
	add_child(player)

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	player.add_child(cs)

	# main body
	var body := MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.4
	bm.height = 1.8
	body.mesh = bm
	body.material_override = _mat(Color(0.2, 0.7, 0.3))
	player.add_child(body)
	var chest := MeshInstance3D.new()      
	var chm := BoxMesh.new()
	chm.size = Vector3(0.4, 0.2, 0.1)
	chest.mesh = chm
	chest.material_override = _mat(Color(0.1, 0.3, 0.1))
	chest.position = Vector3(0, 0.3, -0.38)
	player.add_child(chest)

	# head (rotates toward aim point)
	head = Node3D.new()
	head.position = Vector3(0, 1.1, 0)
	player.add_child(head)
	var hm := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	hm.mesh = sm
	hm.material_override = _mat(Color(0.9, 0.75, 0.6))
	head.add_child(hm)
	var nose := MeshInstance3D.new()
	var nm := BoxMesh.new()
	nm.size = Vector3(0.08, 0.08, 0.15)
	nose.mesh = nm
	nose.material_override = _mat(Color(0.6, 0.4, 0.3))
	nose.position = Vector3(0, 0, -0.22)
	head.add_child(nose)

	# weapon (rotates toward aim point)
	weapon = Node3D.new()
	weapon.position = Vector3(0.35, 0.4, -0.3)
	player.add_child(weapon)
	var wm := MeshInstance3D.new()
	var wbm := BoxMesh.new()
	wbm.size = Vector3(0.1, 0.12, 0.6)
	wm.mesh = wbm
	wm.material_override = _mat(Color(0.15, 0.15, 0.15))
	wm.position = Vector3(0, 0, -0.3)
	weapon.add_child(wm)
	muzzle = Marker3D.new()
	muzzle.position = Vector3(0, 0, -0.65)
	weapon.add_child(muzzle)

	# camera: fixed offset from the pivot, always faces the same way as the body
	pivot = Node3D.new()
	pivot.position = Vector3(0, 1.1, 0)
	player.add_child(pivot)
	cam = Camera3D.new()
	cam.position = Vector3(SHOULDER_X, 0.4, 3.0)
	cam.far = 500.0
	pivot.add_child(cam)
	cam.make_current()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 32)
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(cross)
	cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var help := Label.new()
	help.text = "WASD move | Mouse aim | LMB shoot | Q switch shoulder | Esc release mouse"
	help.position = Vector2(12, 8)
	layer.add_child(help)


# ---------------------------------------------------------------- input
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# yaw turns the whole actor (camera is its child), pitch only tilts the pivot
		player.rotate_y(-event.relative.x * MOUSE_SENS)
		pitch = clampf(pitch - event.relative.y * MOUSE_SENS, deg_to_rad(-60), deg_to_rad(60))
		pivot.rotation.x = pitch
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.keycode == KEY_Q:
			shoulder_side *= -1.0
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------- loop
func _physics_process(delta: float) -> void:
	_move(delta)

	# optional shoulder switch cuz fun
	cam.position.x = lerpf(cam.position.x, SHOULDER_X * shoulder_side, 8.0 * delta)

	_update_aim()

	cooldown -= delta
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and cooldown <= 0.0:
		_fire()
		cooldown = FIRE_COOLDOWN

	_update_shots(delta)


func _move(delta: float) -> void:
	var x := int(Input.is_key_pressed(KEY_D)) - int(Input.is_key_pressed(KEY_A))
	var z := int(Input.is_key_pressed(KEY_S)) - int(Input.is_key_pressed(KEY_W))
	# camera yaw == player yaw, so this is movement relative to the camera
	var dir := player.global_transform.basis * Vector3(x, 0, z)
	dir.y = 0.0
	dir = dir.normalized()

	var horiz := Vector3(player.velocity.x, 0.0, player.velocity.z)
	horiz = horiz.lerp(dir * MOVE_SPEED, clampf(ACCEL * delta, 0.0, 1.0))
	player.velocity.x = horiz.x
	player.velocity.z = horiz.z

	if player.is_on_floor():
		player.velocity.y = -0.1
	else:
		player.velocity.y -= GRAVITY * delta
	player.move_and_slide()


# ---------------------------------------------------------------- aiming
func _update_aim() -> void:
	var space := get_world_3d().direct_space_state
	var center := get_viewport().get_visible_rect().size * 0.5
	var from := cam.project_ray_origin(center)
	var dir := cam.project_ray_normal(center)
	var q := PhysicsRayQueryParameters3D.create(
		from, from + dir * AIM_RANGE, WORLD_MASK | ENEMY_MASK, [player.get_rid()])
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		aim_point = from + dir * AIM_RANGE     # nothing hit: effectively "straight ahead"
	else:
		aim_point = hit["position"]

	# head and weapon look where the shot will go; the main body never does
	var d := _shot_dir(weapon.global_position)
	_look(head, d)
	_look(weapon, d)


func _shot_dir(from_pos: Vector3) -> Vector3:
	var cam_fwd := -cam.global_transform.basis.z
	var d := (aim_point - from_pos).normalized()
	# target too close / beside the actor: fall back to camera forward
	if d.dot(cam_fwd) < 0.3:
		d = cam_fwd
	return d


func _look(n: Node3D, dir: Vector3) -> void:
	var up := Vector3.UP
	if absf(dir.y) > 0.99:
		up = Vector3.RIGHT
	n.look_at(n.global_position + dir, up)


# ---------------------------------------------------------------- shooting
func _fire() -> void:
	var dir := _shot_dir(muzzle.global_position)
	var node := Node3D.new()
	add_child(node)
	node.global_position = muzzle.global_position

	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.3
	core.mesh = sm
	core.material_override = shot_mat
	node.add_child(core)

	var trail := MeshInstance3D.new()          
	var cm := CapsuleMesh.new()
	cm.radius = 0.06
	cm.height = 1.4
	trail.mesh = cm
	trail.material_override = shot_mat
	trail.rotation_degrees.x = 90.0
	trail.position = Vector3(0, 0, 0.7)
	node.add_child(trail)

	var up := Vector3.UP
	if absf(dir.y) > 0.99:
		up = Vector3.RIGHT
	node.look_at(node.global_position + dir, up)

	shots.append({"node": node, "dir": dir, "life": SHOT_LIFETIME})


func _update_shots(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	for i in range(shots.size() - 1, -1, -1):
		var s: Dictionary = shots[i]
		var node: Node3D = s["node"]
		var dir: Vector3 = s["dir"]
		s["life"] = float(s["life"]) - delta

		var from := node.global_position
		var to := from + dir * SHOT_SPEED * delta   
		var q := PhysicsRayQueryParameters3D.create(
			from, to, WORLD_MASK | ENEMY_MASK, [player.get_rid()])
		var hit: Dictionary = space.intersect_ray(q)

		if not hit.is_empty():
			_explode(hit["position"], 0.4)         # small explosion at impact
			var c: Node = hit["collider"]
			if c.has_meta("hp"):
				_damage_enemy(c as Node3D)
			node.queue_free()
			shots.remove_at(i)
		elif float(s["life"]) <= 0.0:
			node.queue_free()
			shots.remove_at(i)
		else:
			node.global_position = to


func _damage_enemy(e: Node3D) -> void:
	var hp: int = int(e.get_meta("hp")) - 1
	e.set_meta("hp", hp)
	if hp <= 0:
		_explode(e.global_position, 1.8)          
		e.queue_free()
		return
	var mat: StandardMaterial3D = e.get_meta("mat")
	var base: Color = e.get_meta("color")
	mat.albedo_color = Color.WHITE
	get_tree().create_timer(0.08).timeout.connect(func(): mat.albedo_color = base)


func _explode(pos: Vector3, radius: float) -> void:
	var m := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	m.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.55, 0.1, 0.9)
	m.material_override = mat
	add_child(m)
	m.global_position = pos
	m.scale = Vector3.ONE * radius * 0.3

	var t := create_tween().set_parallel(true)
	t.tween_property(m, "scale", Vector3.ONE * radius, 0.25)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.25)
	t.chain().tween_callback(m.queue_free)
