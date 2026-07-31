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

	# AUTOMATIC UPRIGHT ORIENTATION ENFORCEMENT
	# If 3D CAD model height was saved along Z-axis (Z-Up CAD standard), swap Y and Z
	# so chair backrests and vehicle roofs stand 100% upright by default!
	if bbox_size.z > bbox_size.y * 1.15:
		for i in range(non_zero_pts.size()):
			var old = non_zero_pts[i]
			non_zero_pts[i] = Vector3(old.x, old.z, old.y)
		min_p = non_zero_pts[0]
		max_p = non_zero_pts[0]
		for p in non_zero_pts:
			min_p.x = min(min_p.x, p.x)
			min_p.y = min(min_p.y, p.y)
			min_p.z = min(min_p.z, p.z)
			max_p.x = max(max_p.x, p.x)
			max_p.y = max(max_p.y, p.y)
			max_p.z = max(max_p.z, p.z)
		center = (min_p + max_p) * 0.5
		bbox_size = max_p - min_p

	var max_dim = max(bbox_size.x, max(bbox_size.y, bbox_size.z))
	if max_dim <= 0.0001:
		max_dim = 1.0

	var scale_factor = scale_size / max_dim

	# 3. Center and scale all points
	var scaled_candidates: Array[Vector3] = []
	for p in non_zero_pts:
		var centered = (p - center) * scale_factor
		scaled_candidates.append(centered)

	if scaled_candidates.size() == 0:
		for p in raw_points:
			scaled_candidates.append((p - center) * scale_factor)

	# 4. FILTER ONLY OUTER SURFACE SHELL (DISCARD INTERIOR/INNER BITS!)
	var outer_shell_pts = _filter_outer_surface_shell_only(scaled_candidates)

	# SMART AUTO-DETECT DRONE COUNT (Calculated from 3D surface area & curvature complexity!)
	var desired_count = target_count
	if desired_count <= 0:
		desired_count = _calculate_smart_optimal_3d_drone_count(outer_shell_pts, scale_size)

	desired_count = min(desired_count, outer_shell_pts.size())

	# FAST MINIMUM SEPARATION SAMPLING (1.35m minimum separation to eliminate drone clumping!)
	var min_dist = maxf(1.35, 1.8 * sqrt(20.0 / float(desired_count)))
	var min_dist_sq = min_dist * min_dist

	var total_outer = outer_shell_pts.size()
	var indices: Array[int] = []
	for i in range(total_outer):
		indices.append(i)
	indices.shuffle()

	for idx in indices:
		if res.size() >= desired_count:
			break
		var pt = outer_shell_pts[idx]
		var too_close = false
		for existing in res:
			if pt.distance_squared_to(existing) < min_dist_sq:
				too_close = true
				break
		if not too_close:
			res.append(pt)

	if res.size() < desired_count:
		var fb_dist_sq = 1.0 # Strict 1.0 meter floor distance
		for idx in indices:
			if res.size() >= desired_count:
				break
			var pt = outer_shell_pts[idx]
			var too_close = false
			for existing in res:
				if pt.distance_squared_to(existing) < fb_dist_sq:
					too_close = true
					break
			if not too_close:
				res.append(pt)

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

static func _filter_outer_surface_shell_only(candidates: Array[Vector3]) -> Array[Vector3]:
	var outer_pts: Array[Vector3] = []
	if candidates.size() < 20:
		return candidates

	var dir_max_r: Dictionary = {}
	var dir_items: Dictionary = {}

	for p in candidates:
		var r = p.length()
		if r < 0.001:
			continue
		var u = p / r
		var key = Vector3i(int(round(u.x * 6.0)), int(round(u.y * 6.0)), int(round(u.z * 6.0)))
		
		if not dir_max_r.has(key) or r > float(dir_max_r[key]):
			dir_max_r[key] = r

		if not dir_items.has(key):
			dir_items[key] = []
		dir_items[key].append(p)

	for key in dir_items.keys():
		var max_r: float = float(dir_max_r[key])
		var shell_min_r = max_r * 0.85
		var pts_list: Array = dir_items[key]
		for p in pts_list:
			if (p as Vector3).length() >= shell_min_r:
				outer_pts.append(p)

	if outer_pts.size() < 15:
		return candidates

	return outer_pts

static func _calculate_smart_optimal_3d_drone_count(pts: Array[Vector3], scale_size: float = 28.0) -> int:
	if pts.size() < 10:
		return 80

	var min_p = pts[0]
	var max_p = pts[0]
	for p in pts:
		min_p.x = min(min_p.x, p.x)
		min_p.y = min(min_p.y, p.y)
		min_p.z = min(min_p.z, p.z)
		max_p.x = max(max_p.x, p.x)
		max_p.y = max(max_p.y, p.y)
		max_p.z = max(max_p.z, p.z)

	var dims = max_p - min_p
	var max_dim = max(dims.x, max(dims.y, dims.z))
	if max_dim <= 0.001:
		max_dim = 1.0

	var sx = (dims.x / max_dim) * scale_size
	var sy = (dims.y / max_dim) * scale_size
	var sz = (dims.z / max_dim) * scale_size

	var estimated_surface_area = 2.0 * (sx * sy + sy * sz + sz * sx)
	var target_area_per_drone = 1.25
	var raw_optimal = estimated_surface_area / target_area_per_drone

	return int(round(clampf(raw_optimal, 60.0, 380.0)))
