extends CharacterBody3D

const MOVE_SPEED := 6.0
const ACCEL := 12.0
const GRAVITY := 20.0
const MOUSE_SENS := 0.003
const SHOT_SPEED := 30.0
const SHOT_LIFETIME := 5.0
const FIRE_COOLDOWN := 0.25
const AIM_RANGE := 200.0
const WORLD_MASK := 1
const ENEMY_MASK := 2
const SHOULDER_X := 0.8

var pitch := 0.0
var shoulder_side := 1.0
var cooldown := 0.0
var shots: Array = []
var aim_point := Vector3.ZERO
var shot_mat: StandardMaterial3D

# Visual nodes linked from Player.tscn
@onready var head: Node3D = $Head
@onready var weapon: Node3D = $Gun
@onready var muzzle: Marker3D = $Gun/Muzzle
@onready var pivot: Node3D = $Camera
@onready var cam: Camera3D = $Camera/Camera3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	shot_mat = _mat(Color(1.0, 0.9, 0.2), true)

func _mat(color: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		pitch = clampf(pitch - event.relative.y * MOUSE_SENS, deg_to_rad(-60), deg_to_rad(60))
		pivot.rotation.x = pitch
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		elif event.keycode == KEY_Q:
			shoulder_side *= -1.0
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	_move(delta)

	cam.position.x = lerpf(cam.position.x, SHOULDER_X * shoulder_side, 8.0 * delta)

	_update_aim()

	cooldown -= delta
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and cooldown <= 0.0:
		_fire()
		cooldown = FIRE_COOLDOWN

	_update_shots(delta)

func _move(delta: float) -> void:
	var x := int(Input.is_key_pressed(KEY_D)) - int(Input.is_key_pressed(KEY_A))
	var z := int(Input.is_key_pressed(KEY_S)) - int(Input.is_key_pressed(KEY_W))
	var dir := global_transform.basis * Vector3(x, 0, z)
	dir.y = 0.0
	dir = dir.normalized()

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	horiz = horiz.lerp(dir * MOVE_SPEED, clampf(ACCEL * delta, 0.0, 1.0))
	velocity.x = horiz.x
	velocity.z = horiz.z

	if is_on_floor():
		velocity.y = -0.1
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

func _update_aim() -> void:
	var space := get_world_3d().direct_space_state
	var center := get_viewport().get_visible_rect().size * 0.5
	var from := cam.project_ray_origin(center)
	var dir := cam.project_ray_normal(center)
	var q := PhysicsRayQueryParameters3D.create(
		from, from + dir * AIM_RANGE, WORLD_MASK | ENEMY_MASK, [get_rid()])
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		aim_point = from + dir * AIM_RANGE
	else:
		aim_point = hit["position"]

	var d := _shot_dir(weapon.global_position)
	_look(head, d)
	_look(weapon, d)

func _shot_dir(from_pos: Vector3) -> Vector3:
	var cam_fwd := -cam.global_transform.basis.z
	var d := (aim_point - from_pos).normalized()
	if d.dot(cam_fwd) < 0.3:
		d = cam_fwd
	return d

func _look(n: Node3D, dir: Vector3) -> void:
	var up := Vector3.UP
	if absf(dir.y) > 0.99:
		up = Vector3.RIGHT
	n.look_at(n.global_position + dir, up)

func _fire() -> void:
	var dir := _shot_dir(muzzle.global_position)
	var node := Node3D.new()
	get_tree().root.add_child(node) # Spawn in world root so shots don't move with player
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
			from, to, WORLD_MASK | ENEMY_MASK, [get_rid()])
		var hit: Dictionary = space.intersect_ray(q)

		if not hit.is_empty():
			_explode(hit["position"], 0.4)
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
	get_tree().root.add_child(m)
	m.global_position = pos
	m.scale = Vector3.ONE * radius * 0.3

	var t := create_tween().set_parallel(true)
	t.tween_property(m, "scale", Vector3.ONE * radius, 0.25)
	t.tween_property(mat, "albedo_color:a", 0.0, 0.25)
	t.chain().tween_callback(m.queue_free)
