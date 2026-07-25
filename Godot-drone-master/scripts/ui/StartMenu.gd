extends CanvasLayer

signal simulation_started

@onready var dimmer: ColorRect = $Dimmer
@onready var panel: PanelContainer = $Center/Panel
@onready var logo_rect: TextureRect = $Center/Panel/Margin/Layout/Header/LogoRect
@onready var start_prompt_label: Label = $Center/Panel/Margin/Layout/PromptBox/PressSpacePrompt
@onready var start_button: Button = $Center/Panel/Margin/Layout/ButtonGroup/StartButton
@onready var tutorial_button: Button = $Center/Panel/Margin/Layout/ButtonGroup/TutorialButton
@onready var subtitle_label: Label = $Center/Panel/Margin/Layout/Header/Subtitle

var is_active: bool = true
var pulse_tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_logo()
	_start_pulse_animation()
	if start_button and not start_button.pressed.is_connected(_on_start_button_pressed):
		start_button.pressed.connect(_on_start_button_pressed)
	if tutorial_button and not tutorial_button.pressed.is_connected(_on_tutorial_button_pressed):
		tutorial_button.pressed.connect(_on_tutorial_button_pressed)

func _exit_tree() -> void:
	if pulse_tween and pulse_tween.is_valid():
		pulse_tween.kill()
		pulse_tween = null

func open_menu() -> void:
	is_active = true
	show()
	_start_pulse_animation()

func _setup_logo() -> void:
	if not logo_rect:
		return
	if FileAccess.file_exists("res://icon.png"):
		var tex = load("res://icon.png")
		if tex is Texture2D:
			logo_rect.texture = tex

func _start_pulse_animation() -> void:
	if pulse_tween and pulse_tween.is_valid():
		pulse_tween.kill()
	
	if not start_prompt_label or not is_inside_tree():
		return
		
	pulse_tween = create_tween().set_loops()
	pulse_tween.tween_property(start_prompt_label, "modulate:a", 0.35, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse_tween.tween_property(start_prompt_label, "modulate:a", 1.0, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _input(event: InputEvent) -> void:
	if not is_active or not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		start_simulation()

func _on_start_button_pressed() -> void:
	start_simulation()

func _on_tutorial_button_pressed() -> void:
	if not is_active:
		return
	is_active = false
	if pulse_tween and pulse_tween.is_valid():
		pulse_tween.kill()
		pulse_tween = null
	hide()
	
	var main_scene = get_tree().current_scene if get_tree() else null
	if main_scene and main_scene.has_method("start_tutorial"):
		main_scene.start_tutorial()

func start_simulation() -> void:
	if not is_active:
		return
	is_active = false
	if pulse_tween and pulse_tween.is_valid():
		pulse_tween.kill()
		pulse_tween = null
	hide()
	simulation_started.emit()
