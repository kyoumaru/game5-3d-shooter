extends Node3D

const WORLD_MASK := 1             # walls, floor, indestructible target
const ENEMY_MASK := 2             # enemies
const ENEMY_ENTITY = preload("res://enemy.tscn")

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_build_world()
	_build_ui()


# ---------------------------------------------------------------- helpers
func _mat(color: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _add_enemy(pos: Vector3) -> void:
	# 1. Instance your Player scene as the enemy
	var enemy := ENEMY_ENTITY.instantiate()
	enemy.position = pos
	
	# 2. Remove the player script so it acts like a static target (doesn't move/listen to input)
	enemy.set_script(null)
	
	# 3. Change its collision layer to the enemy mask (so bullets can hit it)
	enemy.collision_layer = ENEMY_MASK
	enemy.collision_mask = 0
	
	# 4. Find the body mesh and change its color to red
	var color := Color(0.8, 0.25, 0.25)
	var mat := _mat(color)
	
	# Assuming your MeshInstance3D in Player.tscn is named "BodyMesh"
	var body_mesh := enemy.get_node_or_null("BodyMesh") as MeshInstance3D
	if body_mesh:
		body_mesh.material_override = mat
		
	# 5. Attach the metadata so shooting and damage calculations still work
	enemy.set_meta("hp", 3)          # 3 hits to destroy
	enemy.set_meta("mat", mat)
	enemy.set_meta("color", color)
	
	add_child(enemy)


# ---------------------------------------------------------------- world
func _build_world() -> void:
	for p in [Vector3(-6, 1, -18), Vector3(5, 1, -20), Vector3(14, 1, -2),
			Vector3(-16, 1, -24), Vector3(0, 1, -26), Vector3(18, 1, -18)]:
		_add_enemy(p)

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
