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
		"description": "Mastering drone flight relies on smooth control inputs:\n\n• W / S : Pitch Forward / Backward\n• A / D : Roll Left / Right\n• SPACE / SHIFT : Increase / Decrease Thrust (Ascend / Descend)\n• Q / E : Yaw Rotation (Rotate Left / Right)\n• H : Toggle Hover Mode (holds current altitude without losing height)"
	},
	{
		"title": "2. Recharge & Maintenance Tower",
		"description": "Your drone operates on a battery system supported by the Recharge Tower:\n\n• Locate the tall hexagonal obelisk with glowing orange neon lights.\n• Land or hover directly on the glowing top landing pad.\n• Recharging begins automatically, restoring full power and system health."
	},
	{
		"title": "3. Wind Dynamics & Compass HUD",
		"description": "Atmospheric turbulence affects flight trajectory in real time:\n\n• Observe the bottom-left Wind Compass HUD for live wind heading and speed (m/s).\n• Use subtle counter-pitch and roll inputs to maintain a steady flight line during heavy gusts."
	},
	{
		"title": "4. ESC Menu & Swarm Light Shows",
		"description": "Press ESC at any time to open the Pause Menu:\n\n• Review full keyboard and Xbox controller button mappings.\n• Command a drone swarm in synchronized light show formations (Star, Circle, Heart, Diamond, Wave).\n• During a Light Show Formation, vibrant colorful LED lights illuminate below each drone and cinematic cameras track the flight.\n• Press B key at any time (or click STOP AIRSHOW FORMATION in the pause menu) to exit back to manual flight."
	},
	{
		"title": "5. Swarm Escort Mode (TAB Key)",
		"description": "Press TAB during flight to activate Swarm Escort Mode:\n\n• A formation of drones surrounds your position in a synchronized flock.\n• The main player drone becomes invisible while the swarm surrounds and follows your flight path.\n• Press TAB again to disengage Swarm Escort Mode."
	},
	{
		"title": "6. Environment Switcher (Keys 1 - 4)",
		"description": "Switch environments seamlessly during flight using numerical keys 1 through 4:\n\n• Key 1 : Earth & Mountainous Terrain\n• Key 2 : Urban Town & Architecture\n• Key 3 : Night Show Arena\n• Key 4 : Indoor Flight Track\n\nEach transition features an animated loading screen with progress feedback."
	}
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	_connect_signals()
	var theme_mgr = get_node_or_null("/root/ThemeManager")
	if theme_mgr:
		theme_mgr.theme_changed.connect(_on_theme_changed)
	var trans_mgr = get_node_or_null("/root/TranslationManager")
	if trans_mgr:
		trans_mgr.locale_changed.connect(func(_l, _rtl): _update_step_display())

func _on_theme_changed(_t: String) -> void:
	var theme_mgr = get_node_or_null("/root/ThemeManager")
	var panel = get_node_or_null("Center/Panel")
	if theme_mgr and panel:
		theme_mgr.apply_theme_to_control(panel)

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
	if is_inside_tree() and get_tree():
		get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show()
	_on_theme_changed("")
	_update_step_display()
	if next_button:
		next_button.grab_focus()
	tutorial_started.emit()

func _update_step_display() -> void:
	if current_step_index < 0:
		current_step_index = 0
	if current_step_index >= TUTORIAL_STEPS.size():
		current_step_index = TUTORIAL_STEPS.size() - 1

	var tm = get_node_or_null("/root/TranslationManager")
	var is_rtl = tm.is_rtl() if tm else false
	var target_dir = Control.LAYOUT_DIRECTION_RTL if is_rtl else Control.LAYOUT_DIRECTION_LTR

	var center_node = get_node_or_null("Center")
	if center_node:
		center_node.layout_direction = target_dir

	var guide_title = get_node_or_null("Center/Panel/Margin/Layout/Header/Title")
	if guide_title:
		guide_title.text = tm.get_auto_translation("TUTORIAL_GUIDE_TITLE") if tm else "FLIGHT & SIMULATOR GUIDE"

	var step_idx = current_step_index + 1
	var title_key = "TUTORIAL_STEP%d_TITLE" % step_idx
	var desc_key = "TUTORIAL_STEP%d_DESC" % step_idx

	if step_label:
		var counter_fmt = tm.get_auto_translation("TUTORIAL_STEP_COUNTER") if tm else "Step %d of %d"
		step_label.text = counter_fmt % [step_idx, TUTORIAL_STEPS.size()]
	if step_title_label:
		step_title_label.text = tm.get_auto_translation(title_key) if tm else TUTORIAL_STEPS[current_step_index]["title"]
	if description_label:
		description_label.text = tm.get_auto_translation(desc_key) if tm else TUTORIAL_STEPS[current_step_index]["description"]
		description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	if prev_button:
		prev_button.disabled = (current_step_index == 0)
		prev_button.text = tm.get_auto_translation("BTN_PREV") if tm else "PREV"
	if skip_button:
		skip_button.text = tm.get_auto_translation("BTN_SKIP") if tm else "SKIP"
	if next_button:
		if current_step_index == TUTORIAL_STEPS.size() - 1:
			next_button.text = tm.get_auto_translation("BTN_FINISH") if tm else "FINISH"
		else:
			next_button.text = tm.get_auto_translation("BTN_NEXT") if tm else "NEXT"

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
	if is_inside_tree() and get_tree():
		get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	tutorial_completed.emit()
