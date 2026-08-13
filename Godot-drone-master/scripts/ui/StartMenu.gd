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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_setup_logo()
	_start_pulse_animation()
	_setup_theme_bar()
	
	if start_button and not start_button.pressed.is_connected(_on_start_button_pressed):
		start_button.pressed.connect(_on_start_button_pressed)
	if tutorial_button and not tutorial_button.pressed.is_connected(_on_tutorial_button_pressed):
		tutorial_button.pressed.connect(_on_tutorial_button_pressed)
		
	var theme_mgr = get_node_or_null("/root/ThemeManager")
	if theme_mgr:
		theme_mgr.theme_changed.connect(_on_theme_changed)
		_on_theme_changed(theme_mgr.current_ui_theme)

	var trans_mgr = get_node_or_null("/root/TranslationManager")
	if trans_mgr:
		trans_mgr.locale_changed.connect(_on_locale_changed)
		_on_locale_changed(trans_mgr.current_locale, trans_mgr.is_rtl())

func _setup_theme_bar() -> void:
	var layout = get_node_or_null("Center/Panel/Margin/Layout")
	if not layout:
		return
		
	var theme_container = VBoxContainer.new()
	theme_container.name = "ThemeControlBar"
	theme_container.add_theme_constant_override("separation", 6)
	
	var label = Label.new()
	label.name = "ThemeStatusLabel"
	label.text = "UI THEME & LOCATION SYNC"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	theme_container.add_child(label)
	
	var hbox = HBoxContainer.new()
	hbox.name = "HBox"
	hbox.layout_direction = Control.LAYOUT_DIRECTION_LTR
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	theme_container.add_child(hbox)
	
	var btn_auto = Button.new()
	btn_auto.name = "BtnAuto"
	btn_auto.text = "Location"
	btn_auto.pressed.connect(func():
		var tm = get_node_or_null("/root/ThemeManager")
		if tm: tm.set_theme_mode("auto")
	)
	hbox.add_child(btn_auto)
	
	var btn_light = Button.new()
	btn_light.name = "BtnLight"
	btn_light.text = "Light Mode"
	btn_light.pressed.connect(func():
		var tm = get_node_or_null("/root/ThemeManager")
		if tm: tm.set_theme_mode("light")
	)
	hbox.add_child(btn_light)
	
	var btn_dark = Button.new()
	btn_dark.name = "BtnDark"
	btn_dark.text = "Dark Mode"
	btn_dark.pressed.connect(func():
		var tm = get_node_or_null("/root/ThemeManager")
		if tm: tm.set_theme_mode("dark")
	)
	hbox.add_child(btn_dark)

	var lang_option = OptionButton.new()
	lang_option.name = "StartLanguageDropdown"
	var trans_mgr = get_node_or_null("/root/TranslationManager")
	if trans_mgr:
		var locales = trans_mgr.get_supported_locales()
		var selected_idx = 0
		for i in range(locales.size()):
			var loc = locales[i]
			lang_option.add_item(loc["name"])
			if loc["code"] == trans_mgr.current_locale:
				selected_idx = i
		lang_option.selected = selected_idx
		lang_option.item_selected.connect(func(idx):
			if idx >= 0 and idx < locales.size():
				trans_mgr.set_locale(locales[idx]["code"])
		)
	hbox.add_child(lang_option)
	
	layout.add_child(theme_container)

func _on_locale_changed(new_locale: String, is_rtl: bool) -> void:
	_adapt_ui_to_locale(new_locale, is_rtl)

func _adapt_ui_to_locale(_locale: String, is_rtl: bool) -> void:
	var tm = get_node_or_null("/root/TranslationManager")
	var target_dir = Control.LAYOUT_DIRECTION_RTL if is_rtl else Control.LAYOUT_DIRECTION_LTR

	var center_node = get_node_or_null("Center")
	if center_node:
		center_node.layout_direction = target_dir

	if start_button:
		start_button.text = tm.get_auto_translation("BTN_START_SIM") if tm else "START SIMULATION"
	if tutorial_button:
		tutorial_button.text = tm.get_auto_translation("BTN_QUICK_TUTORIAL") if tm else "QUICK TUTORIAL"
	if subtitle_label:
		subtitle_label.text = tm.get_auto_translation("SUBTITLE_SIMULATOR") if tm else "Advanced Quadcopter & Swarm Physics Simulation"
		subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var title_lbl = get_node_or_null("Center/Panel/Margin/Layout/Header/Title")
	if title_lbl:
		title_lbl.text = tm.get_auto_translation("TITLE_SIMULATOR") if tm else "DRONE FLIGHT SIMULATOR"
		title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var theme_lbl = get_node_or_null("Center/Panel/Margin/Layout/ThemeControlBar/ThemeStatusLabel")
	if theme_lbl:
		theme_lbl.text = tm.get_auto_translation("OPT_UI_TITLE") if tm else "UI THEME & LOCATION SYNC"

	var btn_auto = get_node_or_null("Center/Panel/Margin/Layout/ThemeControlBar/HBox/BtnAuto")
	var btn_light = get_node_or_null("Center/Panel/Margin/Layout/ThemeControlBar/HBox/BtnLight")
	var btn_dark = get_node_or_null("Center/Panel/Margin/Layout/ThemeControlBar/HBox/BtnDark")

	if btn_auto and btn_auto is Button:
		btn_auto.text = tm.get_auto_translation("OPT_AUTO_LOCATION_SYNC") if tm else "Location"
	if btn_light and btn_light is Button:
		btn_light.text = tm.get_auto_translation("OPT_LIGHT_MODE") if tm else "Light Mode"
	if btn_dark and btn_dark is Button:
		btn_dark.text = tm.get_auto_translation("OPT_DARK_MODE") if tm else "Dark Mode"

	var welcome_lbl = get_node_or_null("Center/Panel/Margin/Layout/WelcomeText")
	if welcome_lbl and welcome_lbl is Label:
		welcome_lbl.text = tm.get_auto_translation("START_WELCOME_TEXT") if tm else "Press Space to start flying, or view the flight controls below."

	var feat_grid = get_node_or_null("Center/Panel/Margin/Layout/FeatureGrid")
	if feat_grid:
		feat_grid.layout_direction = Control.LAYOUT_DIRECTION_LTR

	var feat1 = get_node_or_null("Center/Panel/Margin/Layout/FeatureGrid/Feature1")
	if feat1 and feat1 is Label:
		feat1.layout_direction = Control.LAYOUT_DIRECTION_LTR
		feat1.text_direction = Control.TEXT_DIRECTION_LTR
		feat1.text = tm.get_auto_translation("START_HINT_FLIGHT") if tm else "Flight: WASD + Space / Shift"
	var feat2 = get_node_or_null("Center/Panel/Margin/Layout/FeatureGrid/Feature2")
	if feat2 and feat2 is Label:
		feat2.layout_direction = Control.LAYOUT_DIRECTION_LTR
		feat2.text_direction = Control.TEXT_DIRECTION_LTR
		feat2.text = tm.get_auto_translation("START_HINT_TRICKS") if tm else "Tricks: 6 (Loop), 7 (Roll)"
	var feat3 = get_node_or_null("Center/Panel/Margin/Layout/FeatureGrid/Feature3")
	if feat3 and feat3 is Label:
		feat3.layout_direction = Control.LAYOUT_DIRECTION_LTR
		feat3.text_direction = Control.TEXT_DIRECTION_LTR
		feat3.text = tm.get_auto_translation("START_HINT_MAPS") if tm else "Maps: 1 to 4 Keys"
	var feat4 = get_node_or_null("Center/Panel/Margin/Layout/FeatureGrid/Feature4")
	if feat4 and feat4 is Label:
		feat4.layout_direction = Control.LAYOUT_DIRECTION_LTR
		feat4.text_direction = Control.TEXT_DIRECTION_LTR
		feat4.text = tm.get_auto_translation("START_HINT_SWARM") if tm else "Swarm Mode: Tab Key"

	if start_prompt_label:
		start_prompt_label.text = tm.get_auto_translation("START_PRESS_SPACE") if tm else "PRESS SPACE TO START"
	var sub_prompt = get_node_or_null("Center/Panel/Margin/Layout/PromptBox/SubPrompt")
	if sub_prompt and sub_prompt is Label:
		sub_prompt.text = tm.get_auto_translation("START_SUB_PROMPT") if tm else "(or press Enter / Controller A button)"

func _on_theme_changed(_new_theme: String) -> void:
	var theme_mgr = get_node_or_null("/root/ThemeManager")
	if not theme_mgr or not panel:
		return

	theme_mgr.apply_theme_to_control(panel)
	
	var is_light = (theme_mgr.current_ui_theme == "light")
	
	var title_lbl = get_node_or_null("Center/Panel/Margin/Layout/Header/Title")
	if title_lbl:
		if is_light:
			title_lbl.add_theme_color_override("font_color", Color(0.06, 0.22, 0.55, 1.0))
			title_lbl.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.9))
			title_lbl.add_theme_constant_override("outline_size", 4)
		else:
			title_lbl.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
			title_lbl.add_theme_color_override("font_outline_color", Color(0.1, 0.4, 0.8, 0.8))
			title_lbl.add_theme_constant_override("outline_size", 6)

	var sub_lbl = get_node_or_null("Center/Panel/Margin/Layout/Header/Subtitle")
	if sub_lbl:
		sub_lbl.add_theme_color_override("font_color", Color(0.08, 0.35, 0.75, 1.0) if is_light else Color(0.35, 0.8, 1.0, 1.0))

	var welcome_lbl = get_node_or_null("Center/Panel/Margin/Layout/WelcomeText")
	if welcome_lbl:
		welcome_lbl.add_theme_color_override("font_color", Color(0.12, 0.18, 0.28, 0.9) if is_light else Color(0.8, 0.84, 0.9, 1.0))

	var prompt_lbl = get_node_or_null("Center/Panel/Margin/Layout/PromptBox/PressSpacePrompt")
	if prompt_lbl:
		if is_light:
			prompt_lbl.add_theme_color_override("font_color", Color(0.08, 0.42, 0.88, 1.0))
			prompt_lbl.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.9))
			prompt_lbl.add_theme_constant_override("outline_size", 4)
		else:
			prompt_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35, 1.0))
			prompt_lbl.add_theme_color_override("font_outline_color", Color(0.4, 0.3, 0.0, 0.8))
			prompt_lbl.add_theme_constant_override("outline_size", 4)

	var sub_prompt = get_node_or_null("Center/Panel/Margin/Layout/PromptBox/SubPrompt")
	if sub_prompt:
		sub_prompt.add_theme_color_override("font_color", Color(0.25, 0.35, 0.48, 0.9) if is_light else Color(0.6, 0.65, 0.72, 1.0))

	# Style the 4 control hint pill labels (Feature1..Feature4)
	for i in range(1, 5):
		var feat_lbl = get_node_or_null("Center/Panel/Margin/Layout/FeatureGrid/Feature%d" % i)
		if feat_lbl:
			var pill_style = StyleBoxFlat.new()
			pill_style.corner_radius_top_left = 8
			pill_style.corner_radius_top_right = 8
			pill_style.corner_radius_bottom_left = 8
			pill_style.corner_radius_bottom_right = 8
			pill_style.content_margin_left = 10
			pill_style.content_margin_right = 10
			pill_style.content_margin_top = 6
			pill_style.content_margin_bottom = 6
			pill_style.set_border_width_all(1)
			
			if is_light:
				pill_style.bg_color = Color(0.85, 0.90, 0.96, 0.95)
				pill_style.border_color = Color(0.65, 0.78, 0.90, 0.7)
				feat_lbl.add_theme_color_override("font_color", Color(0.08, 0.16, 0.30, 1.0))
			else:
				pill_style.bg_color = Color(0.13, 0.15, 0.20, 0.85)
				pill_style.border_color = Color(0.20, 0.65, 0.90, 0.4)
				feat_lbl.add_theme_color_override("font_color", Color(0.75, 0.80, 0.88, 1.0))
				
			feat_lbl.add_theme_stylebox_override("normal", pill_style)

	var status_label = get_node_or_null("Center/Panel/Margin/Layout/ThemeControlBar/ThemeStatusLabel")
	if status_label:
		var tm = get_node_or_null("/root/TranslationManager")
		status_label.text = tm.get_auto_translation("OPT_UI_TITLE") if tm else "UI THEME & LOCATION SYNC"
		status_label.add_theme_color_override("font_color", Color(0.12, 0.22, 0.35, 0.9) if is_light else Color(0.75, 0.85, 0.95, 0.9))

	var lang_option = get_node_or_null("Center/Panel/Margin/Layout/ThemeControlBar/HBox/StartLanguageDropdown")
	if lang_option and lang_option is OptionButton:
		var opt_style = StyleBoxFlat.new()
		opt_style.corner_radius_top_left = 6
		opt_style.corner_radius_top_right = 6
		opt_style.corner_radius_bottom_left = 6
		opt_style.corner_radius_bottom_right = 6
		opt_style.content_margin_left = 10
		opt_style.content_margin_right = 10
		opt_style.content_margin_top = 4
		opt_style.content_margin_bottom = 4
		opt_style.set_border_width_all(1)
		if is_light:
			opt_style.bg_color = Color(0.80, 0.85, 0.92, 0.95)
			opt_style.border_color = Color(0.20, 0.50, 0.85, 0.6)
			lang_option.add_theme_color_override("font_color", Color(0.06, 0.10, 0.18, 1.0))
		else:
			opt_style.bg_color = Color(0.12, 0.16, 0.25, 0.95)
			opt_style.border_color = Color(0.20, 0.85, 1.0, 0.4)
			lang_option.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
		lang_option.add_theme_stylebox_override("normal", opt_style)
		lang_option.add_theme_stylebox_override("hover", opt_style)
		lang_option.add_theme_stylebox_override("pressed", opt_style)
		lang_option.add_theme_stylebox_override("focus", opt_style)

func _exit_tree() -> void:
	if pulse_tween and pulse_tween.is_valid():
		pulse_tween.kill()
		pulse_tween = null

func open_menu() -> void:
	is_active = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
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
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	simulation_started.emit()
