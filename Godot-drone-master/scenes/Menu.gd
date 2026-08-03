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
var record_show_button: Button = null
var screenshot_button: Button = null

const VideoRecorderManager = preload("res://scripts/ui/VideoRecorderManager.gd")
const ScreenshotManager = preload("res://scripts/ui/ScreenshotManager.gd")

# Decoupled Modules
var video_recorder = null

var rec_hud_layer: CanvasLayer = null
var rec_hud_container: Control = null
var rec_dot_label: Label = null
var rec_timer_label: Label = null

# Responsive Tab Navigation State
var current_tab_index: int = 1 # 0: Flight Controls, 1: Light Shows & Custom Shapes, 2: Graphics & Options
var tab_btn_controls: Button = null
var tab_btn_show: Button = null
var tab_btn_options: Button = null
var tab_bar_container: HBoxContainer = null

const KEYBOARD_TEXT = "--- KEYBOARD CONTROLS ---
SPACE / SHIFT : Thrust Up/Down
W / S : Pitch Forward/Back
A / D : Roll Left/Right
Q / E : Yaw Rotate
C : Switch Camera View
ARROWS : Still Camera Angle (Light Show)
H : Toggle Hover Mode
B : Exit Light Show (Back to Flight)
F12 / P : Take Screenshot to Downloads
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
	video_recorder = VideoRecorderManager.new()
	add_child(video_recorder)

	update_controls_display()
	connect_formation_buttons()
	_setup_stop_show_button()
	_setup_recording_hud()
	_setup_tabbed_interface()

	if resume_button and not resume_button.pressed.is_connected(resume):
		resume_button.pressed.connect(resume)
	var quit_btn = get_node_or_null("Center/MainLayout/Panel/Margin/Layout/Quit")
	if quit_btn and not quit_btn.pressed.is_connected(_on_quit_pressed):
		quit_btn.pressed.connect(_on_quit_pressed)

func _setup_tabbed_interface() -> void:
	var main_layout = get_node_or_null("Center/MainLayout")
	var center_node = get_node_or_null("Center")
	if not main_layout or not center_node:
		return

	if tab_bar_container == null:
		var parent_vbox = VBoxContainer.new()
		parent_vbox.name = "TabbedVBox"
		parent_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		parent_vbox.add_theme_constant_override("separation", 10)

		tab_bar_container = HBoxContainer.new()
		tab_bar_container.name = "TopTabBar"
		tab_bar_container.alignment = BoxContainer.ALIGNMENT_CENTER
		tab_bar_container.add_theme_constant_override("separation", 8)

		tab_btn_controls = Button.new()
		tab_btn_controls.text = "FLIGHT CONTROLS"
		tab_btn_controls.custom_minimum_size = Vector2(160, 36)
		tab_btn_controls.add_theme_font_size_override("font_size", 11)
		tab_btn_controls.pressed.connect(select_tab.bind(0))
		tab_bar_container.add_child(tab_btn_controls)

		tab_btn_show = Button.new()
		tab_btn_show.text = "LIGHT SHOW & FORMATIONS"
		tab_btn_show.custom_minimum_size = Vector2(210, 36)
		tab_btn_show.add_theme_font_size_override("font_size", 11)
		tab_btn_show.pressed.connect(select_tab.bind(1))
		tab_bar_container.add_child(tab_btn_show)

		tab_btn_options = Button.new()
		tab_btn_options.text = "GRAPHICS & OPTIONS"
		tab_btn_options.custom_minimum_size = Vector2(170, 36)
		tab_btn_options.add_theme_font_size_override("font_size", 11)
		tab_btn_options.pressed.connect(select_tab.bind(2))
		tab_bar_container.add_child(tab_btn_options)

		parent_vbox.add_child(tab_bar_container)

		if main_layout.get_parent() != parent_vbox:
			main_layout.get_parent().remove_child(main_layout)
			parent_vbox.add_child(main_layout)

		center_node.add_child(parent_vbox)

	select_tab(1)

func select_tab(tab_idx: int) -> void:
	current_tab_index = tab_idx

	var functions_panel = get_node_or_null("Center/TabbedVBox/MainLayout/FunctionsPanel")
	var main_panel = get_node_or_null("Center/TabbedVBox/MainLayout/Panel")
	var graph_panel = get_node_or_null("Center/TabbedVBox/MainLayout/GraphMenuPanel")

	if not functions_panel or not main_panel or not graph_panel:
		functions_panel = get_node_or_null("Center/MainLayout/FunctionsPanel")
		main_panel = get_node_or_null("Center/MainLayout/Panel")
		graph_panel = get_node_or_null("Center/MainLayout/GraphMenuPanel")

	if functions_panel and main_panel and graph_panel:
		main_panel.visible = (tab_idx == 0)
		functions_panel.visible = (tab_idx == 1)
		graph_panel.visible = (tab_idx == 2)

		var active_panel = [main_panel, functions_panel, graph_panel][tab_idx]
		if active_panel:
			active_panel.custom_minimum_size = Vector2(560, 520)

	_update_tab_button_styles()

func _update_tab_button_styles() -> void:
	var btns = [tab_btn_controls, tab_btn_show, tab_btn_options]
	for i in range(btns.size()):
		var btn = btns[i]
		if btn and is_instance_valid(btn):
			if i == current_tab_index:
				btn.add_theme_color_override("font_color", Color(0.2, 0.95, 1.0, 1.0))
			else:
				btn.remove_theme_color_override("font_color")

func _process(delta: float) -> void:
	if video_recorder and video_recorder.is_recording:
		video_recorder.process_recording(delta, get_viewport())

		# Smooth position anchor in Bottom-Right corner
		if rec_hud_container and get_viewport():
			var vp_size = get_viewport().get_visible_rect().size
			rec_hud_container.position = Vector2(vp_size.x - 145, vp_size.y - 50)

		var mins = int(video_recorder.recording_time) / 60
		var secs = int(video_recorder.recording_time) % 60
		if rec_timer_label:
			rec_timer_label.text = "%02d:%02d" % [mins, secs]

		# Smooth heartbeat pulse opacity easing (ZERO layout shifting or text jitter!)
		if rec_dot_label:
			var alpha = 0.35 + 0.65 * (sin(video_recorder.rec_blink_timer * 3.5) * 0.5 + 0.5)
			rec_dot_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, alpha))

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
		if record_show_button == null:
			var rec_hbox = HBoxContainer.new()
			rec_hbox.add_theme_constant_override("separation", 4)

			record_show_button = Button.new()
			record_show_button.name = "RecordShowButton"
			record_show_button.text = "RECORD SHOW"
			record_show_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			record_show_button.custom_minimum_size = Vector2(0, 34)
			record_show_button.add_theme_font_size_override("font_size", 10)
			record_show_button.pressed.connect(_on_record_show_pressed)
			rec_hbox.add_child(record_show_button)

			screenshot_button = Button.new()
			screenshot_button.name = "ScreenshotButton"
			screenshot_button.text = "TAKE SCREENSHOT"
			screenshot_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			screenshot_button.custom_minimum_size = Vector2(0, 34)
			screenshot_button.add_theme_font_size_override("font_size", 10)
			screenshot_button.pressed.connect(take_screenshot)
			rec_hbox.add_child(screenshot_button)

			layout.add_child(rec_hbox)

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

func _setup_recording_hud() -> void:
	if rec_hud_container != null:
		return

	rec_hud_layer = CanvasLayer.new()
	rec_hud_layer.name = "RecordingHUDLayer"
	rec_hud_layer.layer = 120
	rec_hud_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(rec_hud_layer)

	rec_hud_container = PanelContainer.new()
	rec_hud_container.name = "RecordingHUD"
	rec_hud_container.position = Vector2(600, 600)
	rec_hud_container.visible = false

	var stylebox = StyleBoxFlat.new()
	stylebox.bg_color = Color(0.04, 0.04, 0.08, 0.92)
	stylebox.border_color = Color(0.95, 0.15, 0.15, 0.95)
	stylebox.border_width_left = 2
	stylebox.border_width_top = 2
	stylebox.border_width_right = 2
	stylebox.border_width_bottom = 2
	stylebox.corner_radius_top_left = 6
	stylebox.corner_radius_top_right = 6
	stylebox.corner_radius_bottom_right = 6
	stylebox.corner_radius_bottom_left = 6
	stylebox.content_margin_left = 10
	stylebox.content_margin_top = 5
	stylebox.content_margin_right = 12
	stylebox.content_margin_bottom = 5
	rec_hud_container.add_theme_stylebox_override("panel", stylebox)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)

	rec_dot_label = Label.new()
	rec_dot_label.text = "REC"
	rec_dot_label.custom_minimum_size = Vector2(40, 22)
	rec_dot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rec_dot_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25, 1.0))
	rec_dot_label.add_theme_font_size_override("font_size", 12)
	hbox.add_child(rec_dot_label)

	rec_timer_label = Label.new()
	rec_timer_label.text = "00:00"
	rec_timer_label.custom_minimum_size = Vector2(50, 22)
	rec_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rec_timer_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	rec_timer_label.add_theme_font_size_override("font_size", 12)
	hbox.add_child(rec_timer_label)

	rec_hud_container.add_child(hbox)
	rec_hud_layer.add_child(rec_hud_container)

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
	drone_count_spinbox.custom_minimum_size = Vector2(85, 28)
	drone_count_spinbox.value_changed.connect(_on_drone_count_changed)
	count_hbox.add_child(drone_count_spinbox)
	parent_layout.add_child(count_hbox)

	status_label = Label.new()
	status_label.name = "CustomShapeStatusLabel"
	status_label.text = "Select a 3D model or 2D image file to scan formation."
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
		data = ThreeDShapeDetectorClass.process_3d_file_to_formation_data(path, target_count, 20.0)
	else:
		var ImageEdgeDetectorClass = load("res://scripts/python/ImageEdgeDetector.gd")
		data = ImageEdgeDetectorClass.process_image_to_formation_data(path, target_count, 20.0)

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

func _on_record_show_pressed() -> void:
	if video_recorder and video_recorder.is_recording:
		stop_recording()
	else:
		start_recording()

func start_recording() -> void:
	if video_recorder:
		video_recorder.start_recording()

	if rec_hud_container:
		rec_hud_container.visible = true
	if record_show_button:
		record_show_button.text = "STOP RECORDING"
		record_show_button.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
	resume()

func stop_recording() -> void:
	if not video_recorder or not video_recorder.is_recording:
		return

	if rec_hud_container:
		rec_hud_container.visible = false
	if record_show_button:
		record_show_button.text = "RECORD SHOW"
		record_show_button.remove_theme_color_override("font_color")

	video_recorder.stop_recording(status_label)

func take_screenshot() -> void:
	ScreenshotManager.take_pristine_screenshot(get_tree(), status_label)
	if visible:
		resume()

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
	stop_recording()
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

	select_tab(current_tab_index)

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
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_quit_pressed() -> void:
	stop_recording()
	get_tree().quit()
