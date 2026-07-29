class_name ImageEdgeDetector
extends RefCounted

static func process_image_to_formation_data(image_path: String, target_drone_count: int = 0, scale_size: float = 28.0) -> Dictionary:
	var res: Dictionary = {
		"success": false,
		"shape_type": "Unknown",
		"drone_count": 0,
		"points": []
	}

	# 1. Try Python edge detection script
	var python_success = _try_python_edge_detection(image_path, target_drone_count, scale_size)
	if python_success:
		var py_data = _load_generated_json_data()
		if py_data.get("points", []).size() > 0:
			print("ImageEdgeDetector: Successfully processed via Python. Shape: ", py_data.get("shape_type", "Custom Shape"), ", Drones: ", py_data.get("drone_count", 0))
			return py_data

	# 2. Native GDScript fallback if Python fails
	print("ImageEdgeDetector: Running fallback GDScript native image edge detection...")
	var native_points = _process_image_native_gdscript(image_path, target_drone_count if target_drone_count > 0 else 39, scale_size)
	if native_points.size() > 0:
		res["success"] = true
		res["shape_type"] = "Custom Shape"
		res["drone_count"] = native_points.size()
		res["points"] = native_points
	return res

static func process_image_to_formation(image_path: String, drone_count: int = 0, scale_size: float = 28.0) -> Array[Vector3]:
	var data = process_image_to_formation_data(image_path, drone_count, scale_size)
	var pts: Array[Vector3] = []
	if data.has("points"):
		for p in data["points"]:
			pts.append(p)
	return pts

static func _try_python_edge_detection(image_path: String, drone_count: int, scale_size: float) -> bool:
	var json_global_path = ProjectSettings.globalize_path("user://custom_image_formation.json")
	if FileAccess.file_exists("user://custom_image_formation.json"):
		DirAccess.remove_absolute(json_global_path)

	var script_path = ProjectSettings.globalize_path("res://scripts/python/image_edge_to_formation.py")
	var global_img_path = ProjectSettings.globalize_path(image_path)

	if not FileAccess.file_exists(script_path):
		return false

	var output = []
	var args = [script_path, global_img_path, str(drone_count), json_global_path, str(scale_size)]

	var exit_code = OS.execute("python", args, output, true)
	if exit_code == 0 and FileAccess.file_exists("user://custom_image_formation.json"):
		return true

	exit_code = OS.execute("py", args, output, true)
	return (exit_code == 0 and FileAccess.file_exists("user://custom_image_formation.json"))

static func _load_generated_json_data() -> Dictionary:
	var res: Dictionary = {
		"success": false,
		"shape_type": "Custom Shape",
		"drone_count": 0,
		"points": []
	}
	var json_file_path = "user://custom_image_formation.json"
	if not FileAccess.file_exists(json_file_path):
		return res

	var file = FileAccess.open(json_file_path, FileAccess.READ)
	if not file:
		return res

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var err = json.parse(json_text)
	if err != OK:
		return res

	var data = json.data
	if data is Dictionary and data.has("points"):
		var pts_arr = data["points"]
		var points_vec3: Array[Vector3] = []
		for pt in pts_arr:
			if pt is Dictionary:
				var x = float(pt.get("x", 0.0))
				var y = float(pt.get("y", 0.0))
				var z = float(pt.get("z", 0.0))
				points_vec3.append(Vector3(x, y, z))
		res["success"] = true
		res["shape_type"] = String(data.get("shape_type", "Custom Shape"))
		res["drone_count"] = points_vec3.size()
		res["points"] = points_vec3
	return res

static func _process_image_native_gdscript(image_path: String, target_count: int, scale_size: float) -> Array[Vector3]:
	var res: Array[Vector3] = []
	var img = Image.new()
	var err = img.load(image_path)
	if err != OK:
		return res

	var width = img.get_width()
	var height = img.get_height()
	var edge_coords: Array[Vector2] = []

	# Check background color by sampling top-left, top-right, bot-left, bot-right corners
	var corner_a = (img.get_pixel(0, 0).a + img.get_pixel(width - 1, 0).a + img.get_pixel(0, height - 1).a + img.get_pixel(width - 1, height - 1).a) / 4.0
	var has_alpha = corner_a < 0.5
	var bg_lum = (img.get_pixel(0, 0).get_luminance() + img.get_pixel(width - 1, 0).get_luminance() + img.get_pixel(0, height - 1).get_luminance() + img.get_pixel(width - 1, height - 1).get_luminance()) / 4.0

	# Scan for outer boundary transition pixels
	for y in range(1, height - 1):
		for x in range(1, width - 1):
			var c = img.get_pixel(x, y)
			
			var is_fg = false
			if has_alpha:
				is_fg = c.a > 0.3
			else:
				is_fg = abs(c.get_luminance() - bg_lum) > 0.12

			if not is_fg:
				continue

			# Check if adjacent to background
			var left_fg = (img.get_pixel(x - 1, y).a > 0.3) if has_alpha else (abs(img.get_pixel(x - 1, y).get_luminance() - bg_lum) > 0.12)
			var right_fg = (img.get_pixel(x + 1, y).a > 0.3) if has_alpha else (abs(img.get_pixel(x + 1, y).get_luminance() - bg_lum) > 0.12)
			var top_fg = (img.get_pixel(x, y - 1).a > 0.3) if has_alpha else (abs(img.get_pixel(x, y - 1).get_luminance() - bg_lum) > 0.12)
			var bot_fg = (img.get_pixel(x, y + 1).a > 0.3) if has_alpha else (abs(img.get_pixel(x, y + 1).get_luminance() - bg_lum) > 0.12)

			var is_boundary = (not left_fg or not right_fg or not top_fg or not bot_fg)
			if is_boundary:
				edge_coords.append(Vector2(x, y))

	if edge_coords.size() == 0:
		return res

	var total_pts = edge_coords.size()
	var count = target_count if target_count > 0 else 39
	var step = float(total_pts) / float(count)
	var max_dim = float(max(width, height))

	for i in range(count):
		var idx = int(i * step) % total_pts
		var p = edge_coords[idx]
		var norm_x = (p.x - (width / 2.0)) / max_dim
		var norm_y = ((height / 2.0) - p.y) / max_dim
		res.append(Vector3(norm_x * scale_size, norm_y * scale_size, 0.0))

	return res
