extends CanvasLayer

@onready var controls_label = get_node_or_null("Center/MainLayout/Panel/Margin/Layout/Controls")
@onready var resume_button = get_node_or_null("Center/MainLayout/Panel/Margin/Layout/Resume")
@onready var formation_buttons = {
	"star": get_node_or_null("Center/MainLayout/Panel/Margin/Layout/Formations/Row/Star"),
	"circle": get_node_or_null("Center/MainLayout/Panel/Margin/Layout/Formations/Row/Circle"),
	"heart": get_node_or_null("Center/MainLayout/Panel/Margin/Layout/Formations/Row/Heart"),
	"diamond": get_node_or_null("Center/MainLayout/Panel/Margin/Layout/Formations/Row/Diamond"),
	"wave": get_node_or_null("Center/MainLayout/Panel/Margin/Layout/Formations/Row/Wave"),
}

var last_input_was_controller: bool = false
var stop_show_button: Button = null

const KEYBOARD_TEXT = "--- KEYBOARD CONTROLS ---
SPACE / SHIFT : Thrust Up/Down
W / S : Pitch Forward/Back
A / D : Roll Left/Right
Q / E : Yaw Rotate
C : Switch Camera View
H : Toggle Hover Mode
B : Exit Light Show (Back to Flight)
V : Toggle Debug Mode
R : Reset Level
1-4 : Switch Environments
5 : Toggle Autopilot (Track Flight)
6 : Trigger Loop-de-Loop Trick
7 : Trigger Barrel Roll Trick
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

func _setup_stop_show_button() -> void:
	var layout = get_node_or_null("Center/MainLayout/Panel/Margin/Layout/Formations")
	if layout and stop_show_button == null:
		stop_show_button = Button.new()
		stop_show_button.name = "StopShowButton"
		stop_show_button.text = "STOP AIRSHOW FORMATION"
		stop_show_button.custom_minimum_size = Vector2(0, 36)
		stop_show_button.pressed.connect(_on_stop_show_pressed)
		layout.add_child(stop_show_button)
		stop_show_button.visible = false

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
	if stop_show_button:
		var has_show = manager and manager.get("show_mode") != 0
		stop_show_button.visible = has_show

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
