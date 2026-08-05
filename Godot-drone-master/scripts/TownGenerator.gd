extends Node3D

@export var grid_size: int = 9
@export var spacing: float = 48.0
@export_file("*.tscn") var house_scene_path: String = "res://scenes/House.tscn"

var house_scene: PackedScene
var _cached_building_scenes: Dictionary = {}

func _ready() -> void:
	if house_scene_path != "":
		house_scene = load(house_scene_path)

func _get_glb_files(path: String) -> Array[String]:
	var files: Array[String] = []
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".glb"):
				files.append(path + "/" + file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	return files

func _get_ground_height(x: float, z: float) -> float:
	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return 0.0
	var from := Vector3(x, 800.0, z)
	var to := Vector3(x, -200.0, z)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 2 # ONLY collide with Terrain layer 2
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return 0.0
	return hit.position.y

static func _safe_relative_transform(parent: Node3D, child: Node3D) -> Transform3D:
	if not parent or not child or parent == child:
		return Transform3D.IDENTITY
	var xform := Transform3D.IDENTITY
	var curr: Node = child
	while curr and curr != parent and curr is Node3D:
		xform = (curr as Node3D).transform * xform
		curr = curr.get_parent()
	return xform

func _create_exact_building_collision(building: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = []
	_find_all_meshes_recursively(building, meshes)
	
	if meshes.size() == 0:
		return

	var static_body := StaticBody3D.new()
	static_body.name = "ExactBuildingCollision"
	building.add_child(static_body)

	for mesh_inst in meshes:
		if mesh_inst.mesh:
			var trimesh_shape = mesh_inst.mesh.create_trimesh_shape()
			if trimesh_shape:
				var col_shape := CollisionShape3D.new()
				col_shape.shape = trimesh_shape
				# Transform the collision shape to match the exact position, rotation, and scale of this sub-mesh relative to the building root
				col_shape.transform = _safe_relative_transform(building, mesh_inst)
				static_body.add_child(col_shape)

func _find_all_meshes_recursively(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_find_all_meshes_recursively(child, meshes)

func generate() -> void:
	if not is_inside_tree():
		await ready
	await get_tree().physics_frame
	
	seed(123)
	
	var building_files: Array[String] = []
	var all_glbs := _get_glb_files("res://assets/city_kit")
	for f in all_glbs:
		var fn = f.get_file().to_lower()
		if "building" in fn and not "detail-" in fn:
			building_files.append(f)

	if building_files.size() > 0:
		_generate_buildings_assets(building_files)
	else:
		_generate_buildings_fallback()

func _generate_buildings_assets(building_files: Array[String]) -> void:
	var loaded_scenes: Array[PackedScene] = []
	for file_path in building_files:
		if _cached_building_scenes.has(file_path):
			loaded_scenes.append(_cached_building_scenes[file_path])
		else:
			var sc = load(file_path) as PackedScene
			if sc:
				_cached_building_scenes[file_path] = sc
				loaded_scenes.append(sc)

	if loaded_scenes.size() == 0:
		_generate_buildings_fallback()
		return

	# 1. Spawn buildings in grid
	var center_offset = Vector3(grid_size * spacing * 0.5, 0.0, grid_size * spacing * 0.5)

	for x in range(grid_size):
		for z in range(grid_size):
			if x == grid_size / 2 and z == grid_size / 2:
				continue

			var test_pos = Vector3(x * spacing, 0.0, z * spacing)
			var final_pos = test_pos - center_offset + Vector3(50, 0, 50)
			
			var ground_height = _get_ground_height(final_pos.x, final_pos.z)
			if ground_height > 15.0 or ground_height < -2.0:
				continue

			var idx = randi() % loaded_scenes.size()
			var building_scene = loaded_scenes[idx]
			var building_path = building_files[idx]
			
			var building = building_scene.instantiate()
			if building is Node3D:
				building.position = final_pos
				building.position.y = ground_height
				building.rotation.y = (randi() % 4) * (PI / 2.0)
				
				var fn = building_path.get_file().to_lower()
				var b_scale := Vector3.ZERO
				if "skyscraper" in fn:
					b_scale = Vector3(25.0, randf_range(60.0, 110.0), 25.0)
				else:
					b_scale = Vector3(18.0, randf_range(15.0, 30.0), 18.0)
				building.scale = b_scale
					
				add_child(building)
				_create_exact_building_collision(building)

	# 2. Spawn asphalt roads
	var road_parent = Node3D.new()
	road_parent.name = "Roads"
	add_child(road_parent)
	
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_color = Color(0.12, 0.12, 0.13)
	road_mat.roughness = 1.0
	
	for z_idx in range(grid_size - 1):
		var z_pos = (z_idx + 0.5) * spacing - center_offset.z + 50.0
		var road_mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(grid_size * spacing, 0.1, 9.0)
		road_mesh.mesh = box
		road_mesh.position = Vector3(50.0, _get_ground_height(50.0, z_pos) + 0.05, z_pos)
		road_mesh.material_override = road_mat
		road_parent.add_child(road_mesh)
		
	for x_idx in range(grid_size - 1):
		var x_pos = (x_idx + 0.5) * spacing - center_offset.x + 50.0
		var road_mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(9.0, 0.1, grid_size * spacing)
		road_mesh.mesh = box
		road_mesh.position = Vector3(x_pos, _get_ground_height(x_pos, 50.0) + 0.05, 50.0)
		road_mesh.material_override = road_mat
		road_parent.add_child(road_mesh)

	# 3. Spawn streetlights at road intersections
	for x_idx in range(grid_size - 1):
		for z_idx in range(grid_size - 1):
			var x_pos = (x_idx + 0.5) * spacing - center_offset.x + 50.0
			var z_pos = (z_idx + 0.5) * spacing - center_offset.z + 50.0
			
			var sw_pos = Vector3(x_pos - 5.5, _get_ground_height(x_pos - 5.5, z_pos - 5.5), z_pos - 5.5)
			_create_streetlight(sw_pos, PI / 4.0)
			
			var ne_pos = Vector3(x_pos + 5.5, _get_ground_height(x_pos + 5.5, z_pos + 5.5), z_pos + 5.5)
			_create_streetlight(ne_pos, -3.0 * PI / 4.0)

	# 4. Spawn parked cars along the road curbs
	for x in range(grid_size):
		for z in range(grid_size):
			if x == grid_size / 2 and z == grid_size / 2:
				continue
				
			var b_pos = Vector3(x * spacing, 0.0, z * spacing) - center_offset + Vector3(50, 0, 50)
			var b_height = _get_ground_height(b_pos.x, b_pos.z)
			if b_height > 15.0 or b_height < -2.0:
				continue
				
			if z < grid_size - 1 and randf() < 0.7:
				var z_road = (z + 0.5) * spacing - center_offset.z + 50.0
				var rx = b_pos.x + randf_range(-12.0, 12.0)
				var car_pos = Vector3(rx, _get_ground_height(rx, z_road - 4.3) + 0.05, z_road - 4.3)
				_create_procedural_car(car_pos, 0.0)
				
			if z > 0 and randf() < 0.7:
				var z_road = (z - 0.5) * spacing - center_offset.z + 50.0
				var rx = b_pos.x + randf_range(-12.0, 12.0)
				var car_pos = Vector3(rx, _get_ground_height(rx, z_road + 4.3) + 0.05, z_road + 4.3)
				_create_procedural_car(car_pos, PI)

			if x < grid_size - 1 and randf() < 0.6:
				var x_road = (x + 0.5) * spacing - center_offset.x + 50.0
				var rz = b_pos.z + randf_range(-12.0, 12.0)
				var car_pos = Vector3(x_road - 4.3, _get_ground_height(x_road - 4.3, rz) + 0.05, rz)
				_create_procedural_car(car_pos, PI / 2.0)

			if x > 0 and randf() < 0.6:
				var x_road = (x - 0.5) * spacing - center_offset.x + 50.0
				var rz = b_pos.z + randf_range(-12.0, 12.0)
				var car_pos = Vector3(x_road + 4.3, _get_ground_height(x_road + 4.3, rz) + 0.05, rz)
				_create_procedural_car(car_pos, -PI / 2.0)

func _create_streetlight(pos: Vector3, rot_y: float) -> void:
	var light_node := Node3D.new()
	light_node.name = "StreetLight"
	light_node.position = pos
	light_node.rotation.y = rot_y
	add_child(light_node)

	var static_body := StaticBody3D.new()
	static_body.name = "StreetLightCollision"
	light_node.add_child(static_body)

	# Pole collision
	var pole_col := CollisionShape3D.new()
	var pole_shape := CylinderShape3D.new()
	pole_shape.radius = 0.18
	pole_shape.height = 7.0
	pole_col.shape = pole_shape
	pole_col.position = Vector3(0, 3.5, 0)
	static_body.add_child(pole_col)

	# Arm collision
	var arm_col := CollisionShape3D.new()
	var arm_shape := CylinderShape3D.new()
	arm_shape.radius = 0.08
	arm_shape.height = 1.8
	arm_col.shape = arm_shape
	arm_col.position = Vector3(0.7, 6.9, 0)
	arm_col.rotation_degrees.z = 90.0
	static_body.add_child(arm_col)

	# Bulb head collision
	var bulb_col := CollisionShape3D.new()
	var bulb_shape := SphereShape3D.new()
	bulb_shape.radius = 0.35
	bulb_col.shape = bulb_shape
	bulb_col.position = Vector3(1.5, 6.7, 0)
	static_body.add_child(bulb_col)
	
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.25, 0.25, 0.28)
	pole_mat.roughness = 0.6
	pole_mat.metallic = 0.8
	
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.1
	pole_mesh.bottom_radius = 0.18
	pole_mesh.height = 7.0
	pole.mesh = pole_mesh
	pole.position = Vector3(0, 3.5, 0)
	pole.material_override = pole_mat
	light_node.add_child(pole)
	
	var arm := MeshInstance3D.new()
	var arm_mesh := CylinderMesh.new()
	arm_mesh.top_radius = 0.06
	arm_mesh.bottom_radius = 0.06
	arm_mesh.height = 1.8
	arm.mesh = arm_mesh
	arm.position = Vector3(0.7, 6.9, 0)
	arm.rotation_degrees.z = 90.0
	arm.material_override = pole_mat
	light_node.add_child(arm)
	
	var bulb := MeshInstance3D.new()
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.25
	bulb_mesh.height = 0.4
	bulb.mesh = bulb_mesh
	bulb.position = Vector3(1.5, 6.7, 0)
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(1.0, 0.95, 0.7)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.95, 0.7)
	bulb_mat.emission_energy_multiplier = 4.0
	bulb.material_override = bulb_mat
	light_node.add_child(bulb)
	
	var light := OmniLight3D.new()
	light.position = Vector3(1.5, 6.4, 0)
	light.light_color = Color(1.0, 0.92, 0.75)
	light.light_energy = 3.5
	light.omni_range = 15.0
	light.shadow_enabled = false
	light_node.add_child(light)

func _create_procedural_car(pos: Vector3, rot_y: float) -> void:
	var car := Node3D.new()
	car.name = "ParkedCar"
	car.position = pos
	car.rotation.y = rot_y
	add_child(car)

	var static_body := StaticBody3D.new()
	var col_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(4.2, 1.5, 1.8)
	col_shape.shape = box_shape
	col_shape.position = Vector3(0.0, 0.75, 0.0)
	static_body.add_child(col_shape)
	car.add_child(static_body)
	
	var body_colors = [
		Color(0.8, 0.1, 0.1),
		Color(0.1, 0.3, 0.8),
		Color(0.1, 0.7, 0.2),
		Color(0.9, 0.8, 0.1),
		Color(0.85, 0.85, 0.85),
		Color(0.1, 0.1, 0.12),
		Color(0.95, 0.95, 0.95)
	]
	var color = body_colors[randi() % body_colors.size()]
	
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = color
	body_mat.roughness = 0.2
	body_mat.metallic = 0.7
	
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.08, 0.08, 0.1)
	glass_mat.roughness = 0.1
	glass_mat.metallic = 0.9
	
	var lower_box := MeshInstance3D.new()
	var lower_mesh := BoxMesh.new()
	lower_mesh.size = Vector3(4.2, 0.8, 1.8)
	lower_box.mesh = lower_mesh
	lower_box.position = Vector3(0.0, 0.45, 0.0)
	lower_box.material_override = body_mat
	car.add_child(lower_box)
	
	var upper_box := MeshInstance3D.new()
	var upper_mesh := BoxMesh.new()
	upper_mesh.size = Vector3(2.3, 0.7, 1.6)
	upper_box.mesh = upper_mesh
	upper_box.position = Vector3(-0.2, 1.1, 0.0)
	upper_box.material_override = glass_mat
	car.add_child(upper_box)

func _generate_buildings_fallback() -> void:
	if house_scene == null and house_scene_path != "":
		house_scene = load(house_scene_path)
	if house_scene == null:
		push_error("TownGenerator: house scene path could not be loaded: %s" % house_scene_path)
		return

	for x in range(grid_size):
		for z in range(grid_size):
			if x % 2 == 0 and z % 2 == 0:
				continue

			var test_pos = Vector3(x * spacing, 0.0, z * spacing)
			var center_offset = Vector3(grid_size * spacing * 0.5, 0.0, grid_size * spacing * 0.5)
			var final_pos = test_pos - center_offset + Vector3(50, 0, 50)
			
			var ground_height = _get_ground_height(final_pos.x, final_pos.z)
			if ground_height > 15.0 or ground_height < -2.0:
				continue

			var house := house_scene.instantiate()
			if house is Node3D:
				house.position = final_pos
				house.position.y = ground_height
				house.rotation.y = randf() * PI * 2.0
				var h_scale = Vector3(15.0, randf_range(12.0, 24.0), 15.0)
				house.scale = h_scale
				add_child(house)
				_create_exact_building_collision(house)
