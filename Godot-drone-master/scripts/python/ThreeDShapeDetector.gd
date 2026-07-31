class_name ThreeDShapeDetector
extends RefCounted

static func is_3d_file(path: String) -> bool:
	var ext = path.get_extension().to_lower()
	return ext in ["obj", "gltf", "glb", "stl", "ply"] or (ext == "json" and _is_3d_json(path))

static func _is_3d_json(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return false
	var json_text = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(json_text) == OK and json.data is Dictionary:
		if json.data.get("is_3d", false) == true:
			return true
		var pts = json.data.get("points", [])
		if pts.size() > 0 and pts[0] is Dictionary:
			var pt = pts[0]
			return pt.has("z") and abs(float(pt.get("z", 0.0))) > 0.001
	return false

static func process_3d_file_to_formation_data(file_path: String, target_count: int = 0, scale_size: float = 28.0) -> Dictionary:
	var res: Dictionary = {
		"success": false,
		"shape_type": "3D Model",
		"is_3d": true,
		"drone_count": 0,
		"points": []
	}

	# 1. Try Python 3D mesh processing script first
	var py_success = _try_python_3d_detection(file_path, target_count, scale_size)
	if py_success:
		var py_data = _load_generated_json_data()
		if py_data.get("points", []).size() > 0:
			print("ThreeDShapeDetector: Successfully processed via Python. Shape: ", py_data.get("shape_type", "3D Shape"), ", Drones: ", py_data.get("drone_count", 0))
			return py_data

	# 2. Native GDScript 3D Model parser fallback
	print("ThreeDShapeDetector: Running native GDScript 3D model scanner fallback...")
	var raw_points: Array[Vector3] = []
	var ext = file_path.get_extension().to_lower()

	match ext:
		"obj":
			raw_points = _parse_obj_file(file_path)
			res["shape_type"] = "3D OBJ Model"
		"gltf", "glb":
			raw_points = _parse_gltf_file(file_path)
			res["shape_type"] = "3D GLTF Model"
		"stl":
			raw_points = _parse_stl_file(file_path)
			res["shape_type"] = "3D STL Model"
		"ply":
			raw_points = _parse_ply_file(file_path)
			res["shape_type"] = "3D PLY Model"
		"json":
			raw_points = _parse_json_3d_file(file_path)
			res["shape_type"] = "3D Point Cloud JSON"
		_:
			raw_points = _parse_obj_file(file_path)
			res["shape_type"] = "3D Model"

	if raw_points.size() == 0:
		print("ThreeDShapeDetector: Failed to extract 3D points from ", file_path)
		return res

	# 3. Center and normalize 3D bounding box
	var sampled_points = _normalize_and_sample_3d_points(raw_points, target_count, scale_size)
	if sampled_points.size() > 0:
		res["success"] = true
		res["drone_count"] = sampled_points.size()
		res["points"] = sampled_points

	return res

static func _parse_obj_file(file_path: String) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	if not FileAccess.file_exists(file_path):
		return pts
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return pts

	var line_count = 0
	var stride = 1
	var file_len = file.get_length()
	if file_len > 30 * 1024 * 1024:
		stride = 10
	elif file_len > 10 * 1024 * 1024:
		stride = 5

	while not file.eof_reached():
		line_count += 1
		var line = file.get_line().strip_edges()
		if stride > 1 and line_count % stride != 0:
			continue

		if line.begins_with("v ") or line.begins_with("v\t"):
			var parts = line.split(" ", false)
			var clean_parts: Array[String] = []
			for p in parts:
				var sub_p = p.strip_edges()
				if sub_p != "":
					clean_parts.append(sub_p)

			if clean_parts.size() >= 4 and clean_parts[0] == "v":
				var x = float(clean_parts[1])
				var y = float(clean_parts[2])
				var z = float(clean_parts[3])
				pts.append(Vector3(x, y, z))

	file.close()
	return pts

static func _parse_gltf_file(file_path: String) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	if not FileAccess.file_exists(file_path):
		return pts

	# Try loading as packed scene / GLTF state
	var scene = ResourceLoader.load(file_path)
	if scene is PackedScene:
		var inst = scene.instantiate()
		if inst:
			_extract_mesh_vertices_recursive(inst, Transform3D.IDENTITY, pts)
			inst.queue_free()
	return pts

static func _extract_mesh_vertices_recursive(node: Node, current_xf: Transform3D, out_pts: Array[Vector3]) -> void:
	var next_xf = current_xf
	if node is Node3D:
		next_xf = current_xf * node.transform

	if node is MeshInstance3D and node.mesh:
		var mesh = node.mesh
		for surf in range(mesh.get_surface_count()):
			var arrays = mesh.surface_get_arrays(surf)
			if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
				var verts = arrays[Mesh.ARRAY_VERTEX]
				for v in verts:
					out_pts.append(next_xf * v)

	for child in node.get_children():
		_extract_mesh_vertices_recursive(child, next_xf, out_pts)

static func _parse_stl_file(file_path: String) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	if not FileAccess.file_exists(file_path):
		return pts
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return pts

	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line.begins_with("vertex "):
			var parts = line.split(" ", false)
			if parts.size() >= 4:
				pts.append(Vector3(float(parts[1]), float(parts[2]), float(parts[3])))
	file.close()
	return pts

static func _parse_ply_file(file_path: String) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	if not FileAccess.file_exists(file_path):
		return pts
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return pts

	var header_ended = false
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if not header_ended:
			if line == "end_header":
				header_ended = true
			continue

		var parts = line.split(" ", false)
		if parts.size() >= 3:
			pts.append(Vector3(float(parts[0]), float(parts[1]), float(parts[2])))
	file.close()
	return pts

static func _parse_json_3d_file(file_path: String) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	if not FileAccess.file_exists(file_path):
		return pts
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return pts
	var json_text = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(json_text) == OK and json.data is Dictionary:
		var pts_arr = json.data.get("points", [])
		for pt in pts_arr:
			if pt is Dictionary:
				pts.append(Vector3(float(pt.get("x", 0.0)), float(pt.get("y", 0.0)), float(pt.get("z", 0.0))))
	return pts

static func _normalize_and_sample_3d_points(raw_points: Array[Vector3], target_count: int, scale_size: float) -> Array[Vector3]:
	var res: Array[Vector3] = []
	if raw_points.size() == 0:
		return res

	# 1. Filter out exact origin dummy vertices (0,0,0) from raw 3D models
	var non_zero_pts: Array[Vector3] = []
	for p in raw_points:
		if p.length_squared() > 0.0001:
			non_zero_pts.append(p)

	if non_zero_pts.size() == 0:
		non_zero_pts = raw_points

	# 2. Sort X, Y, Z to find full 360-degree 3D bounding box
	var min_p = non_zero_pts[0]
	var max_p = non_zero_pts[0]
	for p in non_zero_pts:
		min_p.x = min(min_p.x, p.x)
		min_p.y = min(min_p.y, p.y)
		min_p.z = min(min_p.z, p.z)
		max_p.x = max(max_p.x, p.x)
		max_p.y = max(max_p.y, p.y)
		max_p.z = max(max_p.z, p.z)

	var center = (min_p + max_p) * 0.5
	var bbox_size = max_p - min_p
	var max_dim = max(bbox_size.x, max(bbox_size.y, bbox_size.z))
	if max_dim <= 0.0001:
		max_dim = 1.0

	var scale_factor = scale_size / max_dim

	# 3. Center and scale all 360-degree surface points
	var scaled_candidates: Array[Vector3] = []
	for p in non_zero_pts:
		var centered = (p - center) * scale_factor
		scaled_candidates.append(centered)

	if scaled_candidates.size() == 0:
		for p in raw_points:
			scaled_candidates.append((p - center) * scale_factor)

	# Target count: Default to 150 for Auto mode (target_count == 0), or user override!
	var desired_count = target_count if target_count > 0 else 150
	desired_count = min(desired_count, scaled_candidates.size())

	# Shuffle candidates spatially to eliminate OBJ sequential group/line bias
	var shuffled: Array[Vector3] = scaled_candidates.duplicate()
	var n_cand = shuffled.size()
	for i in range(n_cand - 1, 0, -1):
		var j = randi() % (i + 1)
		var tmp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp

	# STAGE 1: FORM THE OVERALL SHAPE FIRST (First 65% of drones with wide spatial spacing)
	var stage1_target = max(10, int(round(desired_count * 0.65)))
	var stage1_min_dist = maxf(0.6, 2.0 * sqrt(25.0 / float(desired_count)))
	var stage1_min_dist_sq = stage1_min_dist * stage1_min_dist

	for cand in shuffled:
		if res.size() >= stage1_target:
			break
		var too_close = false
		for existing in res:
			if cand.distance_squared_to(existing) < stage1_min_dist_sq:
				too_close = true
				break
		if not too_close:
			res.append(cand)

	# STAGE 2: FILL LARGEST GAPS WITH REMAINING DRONES (Farthest Point Sampling)
	var remaining_needed = desired_count - res.size()
	if remaining_needed > 0 and shuffled.size() > res.size():
		var sample_limit = min(shuffled.size(), desired_count * 8)
		for _step in range(remaining_needed):
			var best_cand = Vector3.ZERO
			var best_max_dist_sq = -1.0
			var found = false

			for idx in range(sample_limit):
				var cand = shuffled[idx]
				var min_d_sq = 999999.0
				for existing in res:
					var d_sq = cand.distance_squared_to(existing)
					if d_sq < min_d_sq:
						min_d_sq = d_sq

				if min_d_sq > best_max_dist_sq and min_d_sq > 0.04:
					best_max_dist_sq = min_d_sq
					best_cand = cand
					found = true

			if found:
				res.append(best_cand)
			else:
				break

	# Fallback pass to reach exact desired count
	if res.size() < desired_count:
		for cand in shuffled:
			if res.size() >= desired_count:
				break
			var too_close = false
			for existing in res:
				if cand.distance_squared_to(existing) < 0.04:
					too_close = true
					break
			if not too_close:
				res.append(cand)

	return res

static func _try_python_3d_detection(file_path: String, drone_count: int, scale_size: float) -> bool:
	var json_global_path = ProjectSettings.globalize_path("user://custom_3d_shape_formation.json")
	if FileAccess.file_exists("user://custom_3d_shape_formation.json"):
		DirAccess.remove_absolute(json_global_path)

	var script_path = ProjectSettings.globalize_path("res://scripts/python/shape3d_to_formation.py")
	var global_file_path = ProjectSettings.globalize_path(file_path)

	if not FileAccess.file_exists(script_path):
		return false

	var output = []
	var args = [script_path, global_file_path, str(drone_count), json_global_path, str(scale_size)]

	var exit_code = OS.execute("python", args, output, true)
	if exit_code == 0 and FileAccess.file_exists("user://custom_3d_shape_formation.json"):
		return true

	output.clear()
	exit_code = OS.execute("py", args, output, true)
	if exit_code == 0 and FileAccess.file_exists("user://custom_3d_shape_formation.json"):
		return true

	output.clear()
	exit_code = OS.execute("python3", args, output, true)
	return (exit_code == 0 and FileAccess.file_exists("user://custom_3d_shape_formation.json"))

static func _load_generated_json_data() -> Dictionary:
	var res: Dictionary = {
		"success": false,
		"shape_type": "3D Shape",
		"is_3d": true,
		"drone_count": 0,
		"points": []
	}
	var json_file_path = "user://custom_3d_shape_formation.json"
	if not FileAccess.file_exists(json_file_path):
		return res

	var file = FileAccess.open(json_file_path, FileAccess.READ)
	if not file:
		return res

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_text) == OK and json.data is Dictionary:
		var pts_arr = json.data.get("points", [])
		var points_vec3: Array[Vector3] = []
		for pt in pts_arr:
			if pt is Dictionary:
				points_vec3.append(Vector3(float(pt.get("x", 0.0)), float(pt.get("y", 0.0)), float(pt.get("z", 0.0))))
		res["success"] = true
		res["shape_type"] = String(json.data.get("shape_type", "3D Shape"))
		res["is_3d"] = true
		res["drone_count"] = points_vec3.size()
		res["points"] = points_vec3
	return res
