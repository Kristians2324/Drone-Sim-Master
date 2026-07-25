extends Node3D
class_name Terrain

@export var size: Vector2 = Vector2(4000, 4000)

func _ready() -> void:
	_apply_dynamic_materials()

func _apply_dynamic_materials() -> void:
	var grass_mat := StandardMaterial3D.new()
	grass_mat.albedo_color = Color(0.18, 0.28, 0.14, 1)
	grass_mat.roughness = 0.95
	grass_mat.metallic_specular = 0.05
	
	if FileAccess.file_exists("res://assets/textures/grass/Grass001_1K-JPG_Color.jpg"):
		var albedo_tex = load("res://assets/textures/grass/Grass001_1K-JPG_Color.jpg")
		if albedo_tex:
			grass_mat.albedo_texture = albedo_tex
			grass_mat.albedo_color = Color.WHITE
		
	if FileAccess.file_exists("res://assets/textures/grass/Grass001_1K-JPG_NormalGL.jpg"):
		var normal_tex = load("res://assets/textures/grass/Grass001_1K-JPG_NormalGL.jpg")
		if normal_tex:
			grass_mat.normal_enabled = true
			grass_mat.normal_texture = normal_tex
		
	if FileAccess.file_exists("res://assets/textures/grass/Grass001_1K-JPG_Roughness.jpg"):
		var roughness_tex = load("res://assets/textures/grass/Grass001_1K-JPG_Roughness.jpg")
		if roughness_tex:
			grass_mat.roughness_texture = roughness_tex
		
	if FileAccess.file_exists("res://assets/textures/grass/Grass001_1K-JPG_AmbientOcclusion.jpg"):
		var ao_tex = load("res://assets/textures/grass/Grass001_1K-JPG_AmbientOcclusion.jpg")
		if ao_tex:
			grass_mat.ao_enabled = true
			grass_mat.ao_light_affect = 1.0
			grass_mat.ao_texture = ao_tex
		
	grass_mat.uv1_scale = Vector3(28, 28, 28)
	grass_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	
	var floor_mesh = get_node_or_null("FallbackFloor/MeshInstance3D")
	if floor_mesh:
		floor_mesh.material_override = grass_mat

	var mountain_mat := StandardMaterial3D.new()
	mountain_mat.albedo_color = Color(0.24, 0.24, 0.26, 1)
	mountain_mat.roughness = 0.95
	mountain_mat.metallic_specular = 0.05
	mountain_mat.uv1_scale = Vector3(15, 15, 15)
	mountain_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	
	var landform = get_node_or_null("Landform")
	if landform:
		for child in landform.get_children():
			if child is CSGShape3D and child.name.begins_with("Hill"):
				child.material = mountain_mat

func generate() -> void:
	pass
