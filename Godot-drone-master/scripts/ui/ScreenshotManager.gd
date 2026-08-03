class_name ScreenshotManager
extends Node

## Modular Screenshot Manager
## Handles high-resolution, pristine screenshots of drone formations & flight without UI clutter.

static func take_pristine_screenshot(scene_tree: SceneTree, status_label: Label = null) -> String:
	if not scene_tree or not scene_tree.current_scene:
		return ""

	var viewport = scene_tree.root.get_viewport()
	if not viewport:
		return ""

	var current_scene = scene_tree.current_scene
	var manager = current_scene.get_node_or_null("DroneControllerManager")

	# If in Light Show mode, frame the light show formation beautifully
	if manager and manager.has_method("get") and manager.get("show_mode") != 0:
		if manager.has_method("set_cinematic_camera_enabled"):
			manager.set_cinematic_camera_enabled(true)

	await scene_tree.process_frame
	await scene_tree.process_frame

	var img = viewport.get_texture().get_image()
	if not img:
		return ""

	# Keep full native resolution (1080p / 4K native viewport resolution)
	var downloads_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if downloads_dir == "" or not DirAccess.dir_exists_absolute(downloads_dir):
		downloads_dir = ProjectSettings.globalize_path("user://")

	var timestamp = int(Time.get_unix_time_from_system())
	var screenshot_path = downloads_dir.path_join("Drone_Screenshot_%d.png" % timestamp)

	var err = img.save_png(screenshot_path)
	if err == OK:
		if status_label and is_instance_valid(status_label):
			status_label.text = "HIGH-RES SCREENSHOT SAVED TO DOWNLOADS!\n%s" % screenshot_path
			status_label.add_theme_color_override("font_color", Color(0.2, 0.95, 0.4, 1.0))
		print("ScreenshotManager: High-res screenshot saved to: ", screenshot_path)
		return screenshot_path

	return ""
