extends Node3D

@export var forest_radius = 1500.0

var _cached_scenes: Dictionary = {}
var _cached_primitive_shapes: Dictionary = {}

func _ready():
	# Seed for consistent world across runs
	seed(42)
	# Wait for physics to initialize so we can raycast the terrain height
	await get_tree().physics_frame
	generate_world()

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

func _create_fast_collision_for_node(node: Node3D, is_tree: bool = true) -> void:
	var static_body := StaticBody3D.new()
	static_body.position = node.position
	static_body.rotation = node.rotation
	add_child(static_body)

	var col_shape := CollisionShape3D.new()
	if is_tree:
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.8 * maxf(node.scale.x, node.scale.z)
		cyl.height = 12.0 * node.scale.y
		col_shape.shape = cyl
		col_shape.position = Vector3(0.0, cyl.height * 0.5, 0.0)
	else:
		var box := BoxShape3D.new()
		box.size = Vector3(1.5, 1.2, 1.5) * node.scale
		col_shape.shape = box
		col_shape.position = Vector3(0.0, box.size.y * 0.5, 0.0)

	static_body.add_child(col_shape)

func generate_world():
	var all_glbs := _get_glb_files("res://assets/nature_kit")
	var tree_files: Array[String] = []
	var rock_files: Array[String] = []
	
	for f in all_glbs:
		var fn = f.get_file().to_lower()
		if "tree" in fn:
			if not ("dark" in fn or "fall" in fn):
				tree_files.append(f)
		elif "rock_" in fn or "stone_" in fn:
			if "rock_large" in fn or "rock_small" in fn:
				rock_files.append(f)

	# Pre-cache PackedScene instances
	var tree_scenes: Array[PackedScene] = []
	for p in tree_files:
		var sc = load(p) as PackedScene
		if sc: tree_scenes.append(sc)

	var rock_scenes: Array[PackedScene] = []
	for p in rock_files:
		var sc = load(p) as PackedScene
		if sc: rock_scenes.append(sc)

	# 1. Generate Trees in clusters
	if tree_scenes.size() > 0:
		_generate_trees_assets(tree_scenes)
	else:
		_generate_trees_fallback()

	# 2. Generate Rocks in clusters
	if rock_scenes.size() > 0:
		_generate_rocks_assets(rock_scenes)
	else:
		_generate_rocks_fallback()

func _generate_trees_assets(tree_scenes: Array[PackedScene]) -> void:
	var cluster_count = 28
	var trees_per_cluster = 16
	
	for c in range(cluster_count):
		var cluster_x = randf_range(-forest_radius, forest_radius)
		var cluster_z = randf_range(-forest_radius, forest_radius)
		var center = Vector3(cluster_x, 0.0, cluster_z)
		
		var dist_to_town = (center - Vector3(50, 0.0, 50)).length()
		if dist_to_town < 320:
			continue
			
		for t in range(trees_per_cluster):
			var angle = randf() * PI * 2.0
			var dist = randf_range(5.0, 45.0)
			var pos = center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
			
			if (pos - Vector3(50, 0.0, 50)).length() < 280:
				continue
				
			var ground_y = _get_ground_height(pos.x, pos.z)
			if ground_y > 15.0 or ground_y < -2.0:
				continue
			pos.y = ground_y
			
			var tree_scene = tree_scenes[randi() % tree_scenes.size()]
			var tree = tree_scene.instantiate()
			if tree is Node3D:
				tree.position = pos
				tree.scale = Vector3(randf_range(16.0, 24.0), randf_range(20.0, 38.0), randf_range(16.0, 24.0))
				tree.rotation.y = randf() * PI * 2.0
				add_child(tree)
				
				_create_fast_collision_for_node(tree, true)

func _generate_rocks_assets(rock_scenes: Array[PackedScene]) -> void:
	var cluster_count = 10
	var rocks_per_cluster = 8
	
	for c in range(cluster_count):
		var cluster_x = randf_range(-forest_radius, forest_radius)
		var cluster_z = randf_range(-forest_radius, forest_radius)
		var center = Vector3(cluster_x, 0.0, cluster_z)
		
		var dist_to_town = (center - Vector3(50, 0.0, 50)).length()
		if dist_to_town < 320:
			continue
			
		for r in range(rocks_per_cluster):
			var angle = randf() * PI * 2.0
			var dist = randf_range(2.0, 30.0)
			var pos = center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
			
			if (pos - Vector3(50, 0.0, 50)).length() < 280:
				continue
				
			var ground_y = _get_ground_height(pos.x, pos.z)
			if ground_y > 15.0 or ground_y < -2.0:
				continue
			pos.y = ground_y
			
			var rock_scene = rock_scenes[randi() % rock_scenes.size()]
			var rock = rock_scene.instantiate()
			if rock is Node3D:
				rock.position = pos - Vector3(0, 1.0, 0)
				rock.scale = Vector3(randf_range(12.0, 25.0), randf_range(10.0, 18.0), randf_range(12.0, 25.0))
				rock.rotation = Vector3(randf(), randf(), randf()) * PI
				add_child(rock)
				_create_fast_collision_for_node(rock, false)

func _generate_trees_fallback() -> void:
	var tree_multimesh = MultiMeshInstance3D.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = 300
	
	var tree_mesh = CylinderMesh.new()
	tree_mesh.top_radius = 0.0
	tree_mesh.bottom_radius = 2.0
	tree_mesh.height = 6.0
	var tree_mat = StandardMaterial3D.new()
	tree_mat.albedo_color = Color(0.1, 0.3, 0.1)
	tree_mesh.material = tree_mat
	
	mm.mesh = tree_mesh
	tree_multimesh.multimesh = mm
	add_child(tree_multimesh)

	for i in range(300):
		var pos = Vector3(randf_range(-forest_radius, forest_radius), 0, randf_range(-forest_radius, forest_radius))
		if pos.length() < 20:
			pos *= 2.0
		
		var xform = Transform3D()
		xform = xform.scaled(Vector3(randf_range(0.8, 1.5), randf_range(1.0, 2.0), randf_range(0.8, 1.5)))
		xform.origin = pos + Vector3(0, tree_mesh.height * 0.5 * xform.basis.get_scale().y, 0)
		mm.set_instance_transform(i, xform)
		
		var tree_static = StaticBody3D.new()
		var tree_collision_node = CollisionShape3D.new()
		var tree_shape = CylinderShape3D.new()
		tree_shape.radius = 1.0
		tree_shape.height = 6.0 * xform.basis.get_scale().y
		
		tree_collision_node.shape = tree_shape
		tree_collision_node.position = pos + Vector3(0, tree_shape.height * 0.5, 0)
		tree_static.add_child(tree_collision_node)
		add_child(tree_static)

func _generate_rocks_fallback() -> void:
	for i in range(50):
		var rock = MeshInstance3D.new()
		var sphere_mesh := SphereMesh.new()
		sphere_mesh.radius = randf_range(2.0, 5.0)
		sphere_mesh.height = sphere_mesh.radius * 2.0
		rock.mesh = sphere_mesh
		var rock_mat = StandardMaterial3D.new()
		rock_mat.albedo_color = Color(0.4, 0.4, 0.43)
		rock_mat.roughness = 0.9
		rock.material_override = rock_mat
		
		var rock_pos = Vector3(randf_range(-forest_radius, forest_radius), -1, randf_range(-forest_radius, forest_radius))
		rock.position = rock_pos
		rock.scale = Vector3(randf_range(1.0, 2.0), randf_range(0.5, 1.0), randf_range(1.0, 2.0))
		rock.rotation = Vector3(randf(), randf(), randf()) * PI
		add_child(rock)
