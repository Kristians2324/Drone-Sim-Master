extends CanvasLayer

signal tutorial_started
signal tutorial_completed

@onready var step_label: Label = $Center/Panel/Margin/Layout/Header/StepLabel
@onready var step_title_label: Label = $Center/Panel/Margin/Layout/StepTitle
@onready var description_label: Label = $Center/Panel/Margin/Layout/Description
@onready var prev_button: Button = $Center/Panel/Margin/Layout/Actions/PrevButton
@onready var next_button: Button = $Center/Panel/Margin/Layout/Actions/NextButton
@onready var skip_button: Button = $Center/Panel/Margin/Layout/Actions/SkipButton

var current_step_index: int = 0
var is_active: bool = false

const TUTORIAL_STEPS = [
	{
		"title": "1. Basic Flight & Attitude Controls",
		"description": "Mastering drone flight relies on smooth control inputs:\n\n• W / S : Pitch Forward / Backward\n• A / D : Roll Left / Right\n• SPACE / SHIFT : Increase / Decrease Thrust (Ascend / Descend)\n• Q / E : Yaw Rotation (Rotate Left / Right)\n• H : Toggle Hover Mode (locks current altitude automatically)"
	},
	{
		"title": "2. Recharge & Maintenance Tower",
		"description": "Your drone operates on a battery system supported by the Recharge Tower:\n\n• Locate the hexagonal tower obelisk at coordinates (X: 350, Z: 350).\n• Land or hover directly on the glowing top landing pad.\n• Recharging begins automatically, restoring full power and system health."
	},
	{
		"title": "3. Wind Dynamics & Compass HUD",
		"description": "Atmospheric turbulence affects flight trajectory in real time:\n\n• Observe the top-left Wind Compass HUD for live wind heading and speed (m/s).\n• Use subtle counter-pitch and roll inputs to maintain a steady flight line during heavy gusts."
	},
	{
		"title": "4. ESC Menu & Swarm Light Shows",
		"description": "Press ESC at any time to open the Pause Menu:\n\n• Review full keyboard and Xbox controller button mappings.\n• Command a 60+ drone swarm in synchronized light show formations (Star, Circle, Heart, Diamond, Wave).\n• Replay this Flight Guide or adjust simulation settings."
	},
	{
		"title": "5. Environment Switcher (Keys 1 - 4)",
		"description": "Switch environments seamlessly during flight using numerical keys 1 through 4:\n\n• Key 1 : Earth & Mountainous Terrain\n• Key 2 : Urban Town & Architecture\n• Key 3 : Night Show Arena\n• Key 4 : Indoor Flight Track\n\nEach transition features an animated loading screen with progress feedback."
	}
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	_connect_signals()

func _connect_signals() -> void:
	if prev_button and not prev_button.pressed.is_connected(_on_prev_pressed):
		prev_button.pressed.connect(_on_prev_pressed)
	if next_button and not next_button.pressed.is_connected(_on_next_pressed):
		next_button.pressed.connect(_on_next_pressed)
	if skip_button and not skip_button.pressed.is_connected(_on_skip_pressed):
		skip_button.pressed.connect(_on_skip_pressed)

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not is_active:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_skip_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_right"):
		_on_next_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_on_prev_pressed()
		get_viewport().set_input_as_handled()

func start_tutorial() -> void:
	current_step_index = 0
	is_active = true
	show()
	_update_step_display()
	if next_button:
		next_button.grab_focus()
	tutorial_started.emit()

func _update_step_display() -> void:
	if current_step_index < 0:
		current_step_index = 0
	if current_step_index >= TUTORIAL_STEPS.size():
		current_step_index = TUTORIAL_STEPS.size() - 1

	var step_data = TUTORIAL_STEPS[current_step_index]
	if step_label:
		step_label.text = "Step %d of %d" % [current_step_index + 1, TUTORIAL_STEPS.size()]
	if step_title_label:
		step_title_label.text = step_data["title"]
	if description_label:
		description_label.text = step_data["description"]

	if prev_button:
		prev_button.disabled = (current_step_index == 0)
	if next_button:
		if current_step_index == TUTORIAL_STEPS.size() - 1:
			next_button.text = "FINISH"
		else:
			next_button.text = "NEXT"

func _on_prev_pressed() -> void:
	if current_step_index > 0:
		current_step_index -= 1
		_update_step_display()

func _on_next_pressed() -> void:
	if current_step_index < TUTORIAL_STEPS.size() - 1:
		current_step_index += 1
		_update_step_display()
	else:
		close_tutorial()

func _on_skip_pressed() -> void:
	close_tutorial()

func close_tutorial() -> void:
	is_active = false
	hide()
	tutorial_completed.emit()
