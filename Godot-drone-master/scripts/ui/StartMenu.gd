extends CanvasLayer

signal simulation_started

@onready var dimmer: ColorRect = $Dimmer
@onready var panel: PanelContainer = $Center/Panel
@onready var logo_rect: TextureRect = $Center/Panel/Margin/Layout/Header/LogoRect
@onready var start_prompt_label: Label = $Center/Panel/Margin/Layout/PromptBox/PressSpacePrompt
@onready var start_button: Button = $Center/Panel/Margin/Layout/StartButton
@onready var subtitle_label: Label = $Center/Panel/Margin/Layout/Header/Subtitle

var is_active: bool = true
var pulse_tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_logo()
	_start_pulse_animation()
	if start_button and not start_button.pressed.is_connected(_on_start_button_pressed):
		start_button.pressed.connect(_on_start_button_pressed)

func _setup_logo() -> void:
	if not logo_rect:
		return
	var logo_path = "res://assets/textures/drone_logo.png" if FileAccess.file_exists("res://assets/textures/drone_logo.png") else "res://icon.png"
	if ResourceLoader.has_cached(logo_path):
		var cached_tex = ResourceLoader.load(logo_path)
		if cached_tex is Texture2D:
			logo_rect.texture = cached_tex
			return
	if FileAccess.file_exists(logo_path):
		var img = Image.load_from_file(logo_path)
		if img and not img.is_empty():
			logo_rect.texture = ImageTexture.create_from_image(img)

func _start_pulse_animation() -> void:
	if pulse_tween and pulse_tween.is_running():
		pulse_tween.kill()
	
	if not start_prompt_label:
		return
		
	pulse_tween = create_tween().set_loops()
	pulse_tween.tween_property(start_prompt_label, "modulate:a", 0.35, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse_tween.tween_property(start_prompt_label, "modulate:a", 1.0, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _input(event: InputEvent) -> void:
	if not is_active or not visible:
		return
		
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			start_simulation()
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_START or event.button_index == JOY_BUTTON_A:
			start_simulation()
			get_viewport().set_input_as_handled()

func _on_start_button_pressed() -> void:
	if is_active:
		start_simulation()

func start_simulation() -> void:
	if not is_active:
		return
	is_active = false
	
	if pulse_tween and pulse_tween.is_running():
		pulse_tween.kill()
		
	var fade_tween = create_tween().set_parallel(true)
	if panel:
		fade_tween.tween_property(panel, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		fade_tween.tween_property(panel, "position:y", panel.position.y - 20.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if dimmer:
		fade_tween.tween_property(dimmer, "color:a", 0.0, 0.35)
		
	await fade_tween.finished
	hide()
	simulation_started.emit()

func open_menu() -> void:
	show()
	is_active = true
	if panel:
		panel.modulate.a = 1.0
	if dimmer:
		dimmer.color.a = 0.65
	_start_pulse_animation()
	if start_button:
		start_button.grab_focus()
