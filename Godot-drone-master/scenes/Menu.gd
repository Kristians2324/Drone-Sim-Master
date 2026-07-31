extends CanvasLayer

@onready var controls_label = get_node_or_null("Center/MainLayout/Panel/Margin/Layout/Controls")
@onready var resume_button = get_node_or_null("Center/MainLayout/Panel/Margin/Layout/Resume")
@onready var formation_buttons = {
	"star": get_node_or_null("Center/MainLayout/FunctionsPanel/Margin/FunctionsLayout/Formations/Row1/Star"),
	"circle": get_node_or_null("Center/MainLayout/FunctionsPanel/Margin/FunctionsLayout/Formations/Row1/Circle"),
	"heart": get_node_or_null("Center/MainLayout/FunctionsPanel/Margin/FunctionsLayout/Formations/Row1/Heart"),
	"diamond": get_node_or_null("Center/MainLayout/FunctionsPanel/Margin/FunctionsLayout/Formations/Row2/Diamond"),
	"wave": get_node_or_null("Center/MainLayout/FunctionsPanel/Margin/FunctionsLayout/Formations/Row2/Wave"),
}

var last_input_was_controller: bool = false
var cinematic_camera_button: Button = null
var stop_show_button: Button = null

const KEYBOARD_TEXT = "--- KEYBOARD CONTROLS ---
SPACE / SHIFT : Thrust Up/Down
W / S : Pitch Forward/Back
A / D : Roll Left/Right
Q / E : Yaw Rotate
C : Switch Camera View
ARROWS : Still Camera Angle (Light Show)
H : Toggle Hover Mode
B : Exit Light Show (Back to Flight)
V : Toggle Debug Mode
R : Reset Level
1-4 : Switch Environments
5 : Toggle Autopilot
6 / 7 : Aerial Tricks
TAB : Toggle Swarm (Boids Mode)"

const CONTROLLER_TEXT = "--- XBOX CONTROLLER ---
LS Vertical : Thrust Up/Down
LS Horizontal : Yaw (Turn)
RS Vertical : Pitch Forward/Back
RS Horizontal : Roll Left/Right
START : Toggle Menu (ESC)
A : Select Menu Option
BACK : Restart Level"

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	update_controls_display()
	connect_formation_buttons()
	_setup_stop_show_button()

var file_dialog: FileDialog = null
var select_file_button: Button = null
var go_button: Button = null
var status_label: Label = null
var drone_count_spinbox: SpinBox = null

var selected_image_path: String = ""
var processed_formation_points: Array[Vector3] = []
var detected_shape_name: String = ""
var required_drone_count: int = 0

func _setup_stop_show_button() -> void:
	var layout = get_node_or_null("Center/MainLayout/FunctionsPanel/Margin/FunctionsLayout")
	if layout:
		if file_dialog == null:
			_setup_custom_image_ui(layout)

		if cinematic_camera_button == null:
			cinematic_camera_button = Button.new()
			cinematic_camera_button.name = "CinematicCameraButton"
			cinematic_camera_button.text = "ENABLE CINEMATIC CAMERA"
			cinematic_camera_button.custom_minimum_size = Vector2(0, 34)
			cinematic_camera_button.pressed.connect(_on_cinematic_camera_pressed)
			layout.add_child(cinematic_camera_button)
			cinematic_camera_button.visible = false

		if stop_show_button == null:
			stop_show_button = Button.new()
			stop_show_button.name = "StopShowButton"
			stop_show_button.text = "STOP AIRSHOW FORMATION"
			stop_show_button.custom_minimum_size = Vector2(0, 34)
			stop_show_button.pressed.connect(_on_stop_show_pressed)
			layout.add_child(stop_show_button)
			stop_show_button.visible = false

func _setup_custom_image_ui(parent_layout: Control) -> void:
	file_dialog = FileDialog.new()
	file_dialog.name = "ImageFileDialog"
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray([
		"*.obj, *.gltf, *.glb, *.stl, *.ply, *.json, *.png, *.jpg, *.jpeg, *.webp, *.bmp ; 3D Models & Images (*.obj, *.gltf, *.glb, *.stl, *.png, *.jpg)",
		"*.obj, *.gltf, *.glb, *.stl, *.ply ; 3D Model Files (*.obj, *.gltf, *.glb, *.stl, *.ply)",
		"*.png, *.jpg, *.jpeg, *.webp, *.bmp ; 2D Image Files (*.png, *.jpg, *.jpeg, *.webp, *.bmp)",
		"*.json ; 3D Point Cloud JSON (*.json)"
	])
	file_dialog.use_native_dialog = true
	file_dialog.file_selected.connect(_on_image_file_selected)
	add_child(file_dialog)

	var sep = HSeparator.new()
	parent_layout.add_child(sep)

	var title = Label.new()
	title.text = "CUSTOM 3D & 2D SHAPE LIGHT SHOW"
	title.add_theme_color_override("font_color", Color(0.2, 0.85, 1.0, 1.0))
	title.add_theme_font_size_override("font_size", 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent_layout.add_child(title)

	select_file_button = Button.new()
	select_file_button.name = "SelectFileButton"
	select_file_button.text = "CHOOSE IMAGE (.PNG, .JPG) OR 3D MODEL"
	select_file_button.custom_minimum_size = Vector2(0, 32)
	select_file_button.pressed.connect(_on_select_file_pressed)
	parent_layout.add_child(select_file_button)

	var count_hbox = HBoxContainer.new()
	count_hbox.name = "DroneCountHBox"

	var count_label = Label.new()
	count_label.text = "Drone Count (0 = Auto):"
	count_label.add_theme_font_size_override("font_size", 11)
	count_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 0.9))
	count_hbox.add_child(count_label)

	drone_count_spinbox = SpinBox.new()
	drone_count_spinbox.name = "DroneCountSpinBox"
	drone_count_spinbox.min_value = 0
	drone_count_spinbox.max_value = 500
	drone_count_spinbox.step = 1
	drone_count_spinbox.value = 0
	drone_count_spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drone_count_spinbox.value_changed.connect(_on_drone_count_changed)
	count_hbox.add_child(drone_count_spinbox)

	parent_layout.add_child(count_hbox)

	status_label = Label.new()
	status_label.name = "ImageStatusLabel"
	status_label.text = "Select any PNG/JPG image or 3D model (.obj, .gltf, .stl)"
	status_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.8))
	status_label.add_theme_font_size_override("font_size", 10)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	parent_layout.add_child(status_label)

	go_button = Button.new()
	go_button.name = "GoFormShapeButton"
	go_button.text = "FORM SHAPE & START SHOW"
	go_button.custom_minimum_size = Vector2(0, 34)
	go_button.disabled = true
	go_button.pressed.connect(_on_go_form_shape_pressed)
	parent_layout.add_child(go_button)

	var sep2 = HSeparator.new()
	parent_layout.add_child(sep2)

func _on_select_file_pressed() -> void:
	if file_dialog:
		file_dialog.popup_centered(Vector2i(800, 600))

func _on_drone_count_changed(_val: float) -> void:
	if selected_image_path != "":
		_on_image_file_selected(selected_image_path)

func _on_image_file_selected(path: String) -> void:
	selected_image_path = path
	var ThreeDShapeDetectorClass = load("res://scripts/python/ThreeDShapeDetector.gd")
	var is_3d = ThreeDShapeDetectorClass.is_3d_file(path)

	if status_label:
		if is_3d:
			status_label.text = "Scanning 3D shape geometry and sampling points..."
		else:
			status_label.text = "Processing image with Python edge detection..."
		status_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2, 1.0))
	
	await get_tree().process_frame

	var target_count = int(drone_count_spinbox.value) if drone_count_spinbox else 0
	var data: Dictionary = {}

	if is_3d:
		data = ThreeDShapeDetectorClass.process_3d_file_to_formation_data(path, target_count, 28.0)
	else:
		var ImageEdgeDetectorClass = load("res://scripts/python/ImageEdgeDetector.gd")
		data = ImageEdgeDetectorClass.process_image_to_formation_data(path, target_count, 28.0)

	if data.get("success", false) and data.get("points", []).size() > 0:
		processed_formation_points = data["points"]
		detected_shape_name = String(data.get("shape_type", "Custom Shape"))
		required_drone_count = processed_formation_points.size()

		if status_label:
			var mode_str = "Auto-detected" if target_count == 0 else "Manual override"
			var dimension_str = "3D Formation" if data.get("is_3d", false) else "2D Outline"
			status_label.text = "READY! %s [%s] (%s: %d Drones)." % [detected_shape_name, dimension_str, mode_str, required_drone_count]
			status_label.add_theme_color_override("font_color", Color(0.2, 0.95, 0.4, 1.0))
		if go_button:
			go_button.disabled = false
	else:
		if status_label:
			status_label.text = "Error: Could not extract valid shape from selected file."
			status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
		if go_button:
			go_button.disabled = true

func _on_go_form_shape_pressed() -> void:
	if processed_formation_points.size() == 0:
		return
	var manager = get_tree().current_scene.get_node_or_null("DroneControllerManager")
	if manager and manager.has_method("start_custom_image_shape"):
		manager.start_custom_image_shape(selected_image_path, processed_formation_points)
		resume()

func _input(event):
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if not last_input_was_controller:
			last_input_was_controller = true
			update_controls_display()
	elif event is InputEventKey or event is InputEventMouse:
		if last_input_was_controller:
			last_input_was_controller = false
			update_controls_display()

func update_controls_display():
	if controls_label:
		controls_label.text = CONTROLLER_TEXT if last_input_was_controller else KEYBOARD_TEXT

func connect_formation_buttons():
	for key in formation_buttons.keys():
		var button = formation_buttons[key]
		if button and not button.pressed.is_connected(_on_formation_pressed.bind(key)):
			button.pressed.connect(_on_formation_pressed.bind(key))

func _on_formation_pressed(shape_name: String) -> void:
	var manager = get_tree().current_scene.get_node_or_null("DroneControllerManager")
	if manager and manager.has_method("select_show_shape"):
		manager.select_show_shape(shape_name)
		resume()

func _on_cinematic_camera_pressed() -> void:
	var manager = get_tree().current_scene.get_node_or_null("DroneControllerManager")
	if manager and manager.has_method("set_cinematic_camera_enabled"):
		manager.set_cinematic_camera_enabled(true)
	resume()

func _on_stop_show_pressed() -> void:
	var manager = get_tree().current_scene.get_node_or_null("DroneControllerManager")
	if manager and manager.has_method("stop_show_mode"):
		manager.stop_show_mode()
	resume()

func toggle():
	if visible:
		resume()
	else:
		pause()

func pause():
	show()
	update_controls_display()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var manager = get_tree().current_scene.get_node_or_null("DroneControllerManager")
	if manager:
		var has_show = manager.get("show_mode") != 0
		if stop_show_button:
			stop_show_button.visible = has_show
		if cinematic_camera_button:
			cinematic_camera_button.visible = has_show
			var is_cin = manager.get("is_cinematic_mode") == true
			cinematic_camera_button.text = "CINEMATIC CAMERA [ACTIVE]" if is_cin else "ENABLE CINEMATIC CAMERA"
			cinematic_camera_button.disabled = is_cin

	if resume_button:
		resume_button.grab_focus()

func resume():
	hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_resume_pressed():
	resume()

func _on_tutorial_pressed():
	resume()
	var world = get_tree().current_scene
	if world and world.has_method("start_tutorial"):
		world.start_tutorial()

func _on_main_menu_pressed():
	resume()
	var world = get_tree().current_scene
	if world and world.has_method("open_start_menu"):
		world.open_start_menu()

func _on_restart_pressed():
	resume()
	get_tree().reload_current_scene()

func _on_quit_pressed():
	get_tree().quit()
