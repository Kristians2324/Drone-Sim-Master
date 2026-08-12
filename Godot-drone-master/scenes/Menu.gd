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
var current_tab_index: int = 1 # 0: Flight Controls, 1: Light Shows & Custom Shapes, 2: Graphics & Options, 3: Dev Menu
var tab_btn_controls: Button = null
var tab_btn_show: Button = null
var tab_btn_options: Button = null
var tab_btn_dev: Button = null
var tab_bar_container: HBoxContainer = null

# Dev Menu References
var dev_menu_panel: PanelContainer = null
var dev_status_label: Label = null
var current_drain_mult: float = 1.0
var god_mode_active: bool = false
var big_red_quit_button: Button = null
var quit_confirm_modal: PanelContainer = null

# Cached autoload references (safe in headless tests — avoids absolute-path get_node errors)
var _trans_mgr = null
var _theme_mgr = null

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
	PS1MusicManager.get_instance()
	video_recorder = VideoRecorderManager.new()
	add_child(video_recorder)

	update_controls_display()
	connect_formation_buttons()
	_setup_stop_show_button()
	_setup_recording_hud()
	_setup_tabbed_interface()
	_setup_big_red_quit_button()

	if resume_button and not resume_button.pressed.is_connected(_on_resume_pressed):
		resume_button.pressed.connect(_on_resume_pressed)
	var tutorial_btn = get_node_or_null("Center/MainLayout/Panel/Margin/Layout/Tutorial")
	if tutorial_btn and not tutorial_btn.pressed.is_connected(_on_tutorial_pressed):
		tutorial_btn.pressed.connect(_on_tutorial_pressed)
	var main_menu_btn = get_node_or_null("Center/MainLayout/Panel/Margin/Layout/MainMenu")
	if main_menu_btn and not main_menu_btn.pressed.is_connected(_on_main_menu_pressed):
		main_menu_btn.pressed.connect(_on_main_menu_pressed)
	var restart_btn = get_node_or_null("Center/MainLayout/Panel/Margin/Layout/Restart")
	if restart_btn and not restart_btn.pressed.is_connected(_on_restart_pressed):
		restart_btn.pressed.connect(_on_restart_pressed)
	var quit_btn = get_node_or_null("Center/MainLayout/Panel/Margin/Layout/Quit")
	if quit_btn and not quit_btn.pressed.is_connected(_on_quit_pressed):
		quit_btn.pressed.connect(_on_quit_pressed)

	_setup_theme_switcher_bar()
	if is_inside_tree() and get_tree().root.has_node("ThemeManager"):
		_theme_mgr = get_tree().root.get_node("ThemeManager")
		_theme_mgr.theme_changed.connect(_on_theme_changed)
		_on_theme_changed(_theme_mgr.current_ui_theme)

	if is_inside_tree() and get_tree().root.has_node("TranslationManager"):
		var trans_mgr = get_tree().root.get_node("TranslationManager")
		_trans_mgr = trans_mgr
		trans_mgr.locale_changed.connect(_on_locale_changed)
		_on_locale_changed(trans_mgr.current_locale, trans_mgr.is_rtl())

func _setup_theme_switcher_bar() -> void:
	var layout = get_node_or_null("Center/MainLayout/Panel/Margin/Layout")
	if not layout:
		return
		
	var theme_box = VBoxContainer.new()
	theme_box.name = "PauseThemeBar"
	theme_box.add_theme_constant_override("separation", 4)
	
	var label = Label.new()
	label.name = "PauseThemeLabel"
	label.text = "UI THEME MODE"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	theme_box.add_child(label)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 4)
	theme_box.add_child(hbox)
	
	var btn_auto = Button.new()
	btn_auto.text = "Location"
	btn_auto.pressed.connect(func():
		var tm = get_node_or_null("/root/ThemeManager")
		if tm: tm.set_theme_mode("auto")
	)
	hbox.add_child(btn_auto)
	
	var btn_light = Button.new()
	btn_light.text = "Light Mode"
	btn_light.pressed.connect(func():
		var tm = get_node_or_null("/root/ThemeManager")
		if tm: tm.set_theme_mode("light")
	)
	hbox.add_child(btn_light)
	
	var btn_dark = Button.new()
	btn_dark.text = "Dark Mode"
	btn_dark.pressed.connect(func():
		var tm = get_node_or_null("/root/ThemeManager")
		if tm: tm.set_theme_mode("dark")
	)
	hbox.add_child(btn_dark)

	var lang_option = OptionButton.new()
	lang_option.name = "PauseLanguageDropdown"
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
	
	layout.add_child(theme_box)

func _on_locale_changed(new_locale: String, is_rtl: bool) -> void:
	_adapt_ui_to_locale(new_locale, is_rtl)

func _adapt_ui_to_locale(locale: String, is_rtl: bool) -> void:
	# Use cached reference from _ready(); fall back to safe root.has_node() check.
	# Never uses absolute-path get_node("/root/...") directly — that throws SCRIPT ERRORs
	# in headless test environments where the autoload tree isn't fully initialised.
	var tm = _trans_mgr
	if tm == null and is_inside_tree() and get_tree().root.has_node("TranslationManager"):
		tm = get_tree().root.get_node("TranslationManager")
	var target_dir = Control.LAYOUT_DIRECTION_RTL if is_rtl else Control.LAYOUT_DIRECTION_LTR

	var center_node = get_node_or_null("Center")
	if center_node:
		center_node.layout_direction = target_dir

	# Per-locale panel width: wider for languages with long compound words or RTL scripts.
	# Spanish/French have long translated tab labels (e.g. ESPECTÁCULO, HERRAMIENTAS)
	var panel_width = 620
	var tab_font_size = 11
	if locale in ["de", "ru"]:
		panel_width = 700
		tab_font_size = 10
	elif locale in ["es", "fr"]:
		panel_width = 680
		tab_font_size = 10
	elif locale in ["zh", "ja", "ko"]:
		panel_width = 560
		tab_font_size = 12
	elif locale == "ar":
		panel_width = 660
		tab_font_size = 10

	if tab_btn_controls:
		tab_btn_controls.text = tm.get_auto_translation("TAB_CONTROLS") if tm else "CONTROLS"
		tab_btn_controls.add_theme_font_size_override("font_size", tab_font_size)
	if tab_btn_show:
		tab_btn_show.text = tm.get_auto_translation("TAB_SHOW") if tm else "LIGHT SHOW"
		tab_btn_show.add_theme_font_size_override("font_size", tab_font_size)
	if tab_btn_options:
		tab_btn_options.text = tm.get_auto_translation("TAB_OPTIONS") if tm else "OPTIONS"
		tab_btn_options.add_theme_font_size_override("font_size", tab_font_size)
	if tab_btn_dev:
		tab_btn_dev.text = tm.get_auto_translation("TAB_DEV") if tm else "DEV TOOLS"
		tab_btn_dev.add_theme_font_size_override("font_size", tab_font_size)

	if tab_bar_container:
		# Keep tab bar exactly as wide as the panel so buttons are always evenly spread
		tab_bar_container.custom_minimum_size = Vector2(panel_width, 38)
		tab_bar_container.layout_direction = target_dir

	if resume_button:
		resume_button.text = tm.get_auto_translation("BTN_RESUME") if tm else "RESUME SIMULATION"
	var tutorial_btn = get_node_or_null("Center/MainLayout/Panel/Margin/Layout/Tutorial")
	if tutorial_btn:
		tutorial_btn.text = tm.get_auto_translation("BTN_TUTORIAL") if tm else "PLAY TUTORIAL"
	var main_menu_btn = get_node_or_null("Center/MainLayout/Panel/Margin/Layout/MainMenu")
	if main_menu_btn:
		main_menu_btn.text = tm.get_auto_translation("BTN_MAIN_MENU") if tm else "MAIN MENU"
	var restart_btn = get_node_or_null("Center/MainLayout/Panel/Margin/Layout/Restart")
	if restart_btn:
		restart_btn.text = tm.get_auto_translation("BTN_RESTART") if tm else "RESTART LEVEL"
	var quit_btn = get_node_or_null("Center/MainLayout/Panel/Margin/Layout/Quit")
	if quit_btn:
		quit_btn.text = tm.get_auto_translation("BTN_QUIT") if tm else "QUIT GAME"

	var fn_title = get_node_or_null("Center/MainLayout/FunctionsPanel/Margin/FunctionsLayout/Title")
	if fn_title:
		fn_title.text = tm.get_auto_translation("TITLE_LIGHT_SHOWS") if tm else "LIGHT SHOWS & FUNCTIONS"
	var fm_title = get_node_or_null("Center/MainLayout/FunctionsPanel/Margin/FunctionsLayout/Formations/FormationsTitle")
	if fm_title:
		fm_title.text = tm.get_auto_translation("LABEL_SWARM_FORMATIONS") if tm else "SWARM AIRSHOW FORMATIONS"

	if formation_buttons != null and formation_buttons.has("star") and formation_buttons["star"]:
		formation_buttons["star"].text = tm.get_auto_translation("BTN_STAR") if tm else "Star"
	if formation_buttons != null and formation_buttons.has("circle") and formation_buttons["circle"]:
		formation_buttons["circle"].text = tm.get_auto_translation("BTN_CIRCLE") if tm else "Circle"
	if formation_buttons != null and formation_buttons.has("heart") and formation_buttons["heart"]:
		formation_buttons["heart"].text = tm.get_auto_translation("BTN_HEART") if tm else "Heart"
	if formation_buttons != null and formation_buttons.has("diamond") and formation_buttons["diamond"]:
		formation_buttons["diamond"].text = tm.get_auto_translation("BTN_DIAMOND") if tm else "Diamond"
	if formation_buttons != null and formation_buttons.has("wave") and formation_buttons["wave"]:
		formation_buttons["wave"].text = tm.get_auto_translation("BTN_WAVE") if tm else "Wave"

	if stop_show_button:
		stop_show_button.text = tm.get_auto_translation("BTN_STOP_SHOW") if tm else "STOP AIRSHOW FORMATION"
	if record_show_button:
		record_show_button.text = tm.get_auto_translation("BTN_STOP_RECORDING") if video_recorder and video_recorder.is_recording else (tm.get_auto_translation("BTN_RECORD_SHOW") if tm else "RECORD SHOW")
	if screenshot_button:
		screenshot_button.text = tm.get_auto_translation("BTN_TAKE_SCREENSHOT") if tm else "TAKE SCREENSHOT"

	select_tab(current_tab_index)
	update_controls_display()

func _on_theme_changed(_new_theme: String) -> void:
	var theme_mgr = get_node_or_null("/root/ThemeManager")
	var main_layout = get_node_or_null("Center/MainLayout")
	if theme_mgr and main_layout:
		theme_mgr.apply_theme_to_control(main_layout)
		var label = get_node_or_null("Center/MainLayout/Panel/Margin/Layout/PauseThemeBar/PauseThemeLabel")
		if label:
			label.text = "UI THEME: %s (%s) | %s" % [theme_mgr.theme_mode.capitalize(), theme_mgr.current_ui_theme.capitalize(), theme_mgr.city_name]

		if resume_button and is_instance_valid(resume_button):
			var is_light = (theme_mgr.current_ui_theme == "light")
			var primary_sb = StyleBoxFlat.new()
			primary_sb.corner_radius_top_left = 8
			primary_sb.corner_radius_top_right = 8
			primary_sb.corner_radius_bottom_left = 8
			primary_sb.corner_radius_bottom_right = 8
			primary_sb.set_border_width_all(1)

			if is_light:
				primary_sb.bg_color = Color(0.12, 0.48, 0.88, 0.95)
				primary_sb.border_color = Color(0.20, 0.65, 1.0, 1.0)
				resume_button.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
				resume_button.add_theme_color_override("font_focus_color", Color(1.0, 1.0, 1.0, 1.0))
				resume_button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
			else:
				primary_sb.bg_color = Color(0.15, 0.45, 0.75, 1.0)
				primary_sb.border_color = Color(0.20, 0.85, 1.0, 0.8)
				resume_button.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
				resume_button.add_theme_color_override("font_focus_color", Color(1.0, 1.0, 1.0, 1.0))
				resume_button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))

			resume_button.add_theme_stylebox_override("normal", primary_sb)
			resume_button.add_theme_stylebox_override("hover", primary_sb)
			resume_button.add_theme_stylebox_override("focus", primary_sb)
			resume_button.add_theme_stylebox_override("pressed", primary_sb)

	_update_tab_button_styles()

func _update_tab_button_styles() -> void:
	# Use cached _theme_mgr to avoid absolute-path get_node() in headless tests
	var theme_mgr = _theme_mgr
	if theme_mgr == null and is_inside_tree() and get_tree().root.has_node("ThemeManager"):
		theme_mgr = get_tree().root.get_node("ThemeManager")
	var is_light = (theme_mgr and theme_mgr.current_ui_theme == "light")

	var btns = [tab_btn_controls, tab_btn_show, tab_btn_options, tab_btn_dev]
	for i in range(btns.size()):
		var btn = btns[i]
		if btn and is_instance_valid(btn):
			var sb = StyleBoxFlat.new()
			sb.corner_radius_top_left = 6
			sb.corner_radius_top_right = 6
			sb.corner_radius_bottom_left = 6
			sb.corner_radius_bottom_right = 6

			if is_light:
				if i == current_tab_index:
					sb.bg_color = Color(0.12, 0.48, 0.88, 0.95)
					sb.border_width_bottom = 3
					sb.border_color = Color(0.20, 0.65, 1.0, 1.0)
					btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
				else:
					sb.bg_color = Color(0.80, 0.85, 0.92, 0.95)
					sb.border_width_bottom = 0
					btn.add_theme_color_override("font_color", Color(0.06, 0.10, 0.18, 0.85))
			else:
				if i == current_tab_index:
					sb.bg_color = Color(0.12, 0.22, 0.32, 0.95)
					sb.border_width_bottom = 3
					sb.border_color = Color(0.2, 0.85, 1.0, 1.0)
					btn.add_theme_color_override("font_color", Color(0.2, 0.95, 1.0, 1.0))
				else:
					sb.bg_color = Color(0.06, 0.1, 0.15, 0.8)
					sb.border_width_bottom = 0
					btn.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.85))

			btn.add_theme_stylebox_override("normal", sb)
			btn.add_theme_stylebox_override("hover", sb)
			btn.add_theme_stylebox_override("pressed", sb)

func _setup_tabbed_interface() -> void:
	var main_layout = get_node_or_null("Center/MainLayout")
	var center_node = get_node_or_null("Center")
	if not main_layout or not center_node:
		return

	if tab_bar_container == null:
		var parent_vbox = VBoxContainer.new()
		parent_vbox.name = "TabbedVBox"
		parent_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		parent_vbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		parent_vbox.add_theme_constant_override("separation", 10)

		tab_bar_container = HBoxContainer.new()
		tab_bar_container.name = "TopTabBar"
		tab_bar_container.alignment = BoxContainer.ALIGNMENT_CENTER
		# No fixed custom_minimum_size here — it will be set by _adapt_ui_to_locale
		# to match the panel width for the active locale.
		tab_bar_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tab_bar_container.add_theme_constant_override("separation", 8)

		tab_btn_controls = Button.new()
		tab_btn_controls.text = "CONTROLS"
		tab_btn_controls.custom_minimum_size = Vector2(0, 36)
		tab_btn_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_btn_controls.add_theme_font_size_override("font_size", 11)
		tab_btn_controls.pressed.connect(select_tab.bind(0))
		tab_bar_container.add_child(tab_btn_controls)

		tab_btn_show = Button.new()
		tab_btn_show.text = "LIGHT SHOW"
		tab_btn_show.custom_minimum_size = Vector2(0, 36)
		tab_btn_show.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_btn_show.add_theme_font_size_override("font_size", 11)
		tab_btn_show.pressed.connect(select_tab.bind(1))
		tab_bar_container.add_child(tab_btn_show)

		tab_btn_options = Button.new()
		tab_btn_options.text = "OPTIONS"
		tab_btn_options.custom_minimum_size = Vector2(0, 36)
		tab_btn_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_btn_options.add_theme_font_size_override("font_size", 11)
		tab_btn_options.pressed.connect(select_tab.bind(2))
		tab_bar_container.add_child(tab_btn_options)

		tab_btn_dev = Button.new()
		tab_btn_dev.text = "DEV TOOLS"
		tab_btn_dev.custom_minimum_size = Vector2(0, 36)
		tab_btn_dev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_btn_dev.add_theme_font_size_override("font_size", 11)
		tab_btn_dev.pressed.connect(select_tab.bind(3))
		tab_bar_container.add_child(tab_btn_dev)

		parent_vbox.add_child(tab_bar_container)

		if main_layout.get_parent() != parent_vbox:
			main_layout.get_parent().remove_child(main_layout)
			parent_vbox.add_child(main_layout)

		_build_dev_menu_panel(main_layout)

		center_node.add_child(parent_vbox)

	select_tab(0)

func select_tab(tab_idx: int) -> void:
	current_tab_index = tab_idx

	var functions_panel = get_node_or_null("Center/TabbedVBox/MainLayout/FunctionsPanel")
	var main_panel = get_node_or_null("Center/TabbedVBox/MainLayout/Panel")
	var graph_panel = get_node_or_null("Center/TabbedVBox/MainLayout/GraphMenuPanel")
	var dev_panel = get_node_or_null("Center/TabbedVBox/MainLayout/DevMenuPanel")

	if not functions_panel or not main_panel or not graph_panel:
		functions_panel = get_node_or_null("Center/MainLayout/FunctionsPanel")
		main_panel = get_node_or_null("Center/MainLayout/Panel")
		graph_panel = get_node_or_null("Center/MainLayout/GraphMenuPanel")
		dev_panel = get_node_or_null("Center/MainLayout/DevMenuPanel")

	if functions_panel and main_panel and graph_panel:
		main_panel.visible = (tab_idx == 0)
		functions_panel.visible = (tab_idx == 1)
		graph_panel.visible = (tab_idx == 2)
		if dev_panel:
			dev_panel.visible = (tab_idx == 3)

		# Use locale-aware width so panels always match the tab bar above them
		var pw = _get_locale_panel_width()
		var panels = [main_panel, functions_panel, graph_panel, dev_panel]
		if tab_idx < panels.size() and panels[tab_idx]:
			panels[tab_idx].custom_minimum_size = Vector2(pw, 520)

	_update_tab_button_styles()

## Returns the panel width appropriate for the active locale.
func _get_locale_panel_width() -> int:
	var locale = ""
	if _trans_mgr:
		locale = _trans_mgr.current_locale
	elif is_inside_tree() and get_tree().root.has_node("TranslationManager"):
		locale = get_tree().root.get_node("TranslationManager").current_locale
	if locale in ["de", "ru"]:
		return 700
	elif locale in ["es", "fr"]:
		return 680
	elif locale in ["zh", "ja", "ko"]:
		return 560
	elif locale == "ar":
		return 660
	return 620


func _process(delta: float) -> void:
	if visible and get_viewport():
		var vp_size = get_viewport().get_visible_rect().size
		if big_red_quit_button:
			big_red_quit_button.position = Vector2(vp_size.x - 213, vp_size.y - 74)
		if quit_confirm_modal and quit_confirm_modal.visible:
			quit_confirm_modal.position = (vp_size - Vector2(420, 180)) / 2.0

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

func _setup_big_red_quit_button() -> void:
	if big_red_quit_button != null: return

	big_red_quit_button = Button.new()
	big_red_quit_button.name = "BigRedQuitButton"
	big_red_quit_button.text = "⏻ POWER OFF (QUIT)"
	big_red_quit_button.custom_minimum_size = Vector2(185, 48)
	big_red_quit_button.add_theme_font_size_override("font_size", 13)

	var sb_normal = StyleBoxFlat.new()
	sb_normal.bg_color = Color(0.55, 0.08, 0.08, 0.92)
	sb_normal.border_width_left = 2
	sb_normal.border_width_top = 2
	sb_normal.border_width_right = 2
	sb_normal.border_width_bottom = 2
	sb_normal.border_color = Color(1.0, 0.25, 0.25, 1.0)
	sb_normal.corner_radius_top_left = 8
	sb_normal.corner_radius_top_right = 8
	sb_normal.corner_radius_bottom_left = 8
	sb_normal.corner_radius_bottom_right = 8
	sb_normal.content_margin_left = 14
	sb_normal.content_margin_right = 14
	sb_normal.content_margin_top = 8
	sb_normal.content_margin_bottom = 8

	var sb_hover = sb_normal.duplicate() as StyleBoxFlat
	sb_hover.bg_color = Color(0.8, 0.12, 0.12, 0.98)
	sb_hover.border_color = Color(1.0, 0.5, 0.5, 1.0)

	var sb_pressed = sb_normal.duplicate() as StyleBoxFlat
	sb_pressed.bg_color = Color(0.95, 0.15, 0.15, 1.0)
	sb_pressed.border_color = Color(1.0, 0.75, 0.75, 1.0)

	big_red_quit_button.add_theme_stylebox_override("normal", sb_normal)
	big_red_quit_button.add_theme_stylebox_override("hover", sb_hover)
	big_red_quit_button.add_theme_stylebox_override("pressed", sb_pressed)
	big_red_quit_button.add_theme_stylebox_override("focus", sb_hover)
	big_red_quit_button.add_theme_color_override("font_color", Color(1.0, 0.95, 0.95))
	big_red_quit_button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))

	big_red_quit_button.pressed.connect(_on_quit_pressed)

	add_child(big_red_quit_button)

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
	if not controls_label:
		return
	var tm = get_node_or_null("/root/TranslationManager")
	if not tm:
		controls_label.text = CONTROLLER_TEXT if last_input_was_controller else KEYBOARD_TEXT
		return

	controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if last_input_was_controller:
		controls_label.text = tm.get_auto_translation("TITLE_XBOX_CONTROLS") + "\n" + \
			tm.get_auto_translation("XBOX_THRUST") + "\n" + \
			tm.get_auto_translation("XBOX_YAW") + "\n" + \
			tm.get_auto_translation("XBOX_PITCH") + "\n" + \
			tm.get_auto_translation("XBOX_ROLL") + "\n" + \
			tm.get_auto_translation("XBOX_MENU") + "\n" + \
			tm.get_auto_translation("XBOX_SELECT") + "\n" + \
			tm.get_auto_translation("XBOX_RESTART")
	else:
		controls_label.text = tm.get_auto_translation("TITLE_KEYBOARD_CONTROLS") + "\n" + \
			tm.get_auto_translation("KEY_THRUST") + "\n" + \
			tm.get_auto_translation("KEY_PITCH") + "\n" + \
			tm.get_auto_translation("KEY_ROLL") + "\n" + \
			tm.get_auto_translation("KEY_YAW") + "\n" + \
			tm.get_auto_translation("KEY_CAM") + "\n" + \
			tm.get_auto_translation("KEY_ARROWS") + "\n" + \
			tm.get_auto_translation("KEY_HOVER") + "\n" + \
			tm.get_auto_translation("KEY_EXIT_SHOW") + "\n" + \
			tm.get_auto_translation("KEY_SCREENSHOT") + "\n" + \
			tm.get_auto_translation("KEY_DEBUG") + "\n" + \
			tm.get_auto_translation("KEY_RESTART") + "\n" + \
			tm.get_auto_translation("KEY_ENV") + "\n" + \
			tm.get_auto_translation("KEY_AUTOPILOT") + "\n" + \
			tm.get_auto_translation("KEY_TRICKS") + "\n" + \
			tm.get_auto_translation("KEY_BOIDS")

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

	select_tab(0)

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

func _on_resume_pressed() -> void:
	resume()

func _on_tutorial_pressed() -> void:
	stop_recording()
	resume()
	var main_scene = get_tree().current_scene if get_tree() else null
	if main_scene and main_scene.has_method("start_tutorial"):
		main_scene.start_tutorial()

func _on_main_menu_pressed() -> void:
	stop_recording()
	resume()
	var main_scene = get_tree().current_scene if get_tree() else null
	if main_scene and main_scene.has_method("open_start_menu"):
		main_scene.open_start_menu()

func _on_restart_pressed() -> void:
	stop_recording()
	resume()
	var main_scene = get_tree().current_scene if get_tree() else null
	if main_scene and main_scene.has_method("_restart_fresh"):
		main_scene.call_deferred("_restart_fresh")
	else:
		get_tree().reload_current_scene()

func _on_quit_pressed() -> void:
	_show_quit_confirmation_modal()

func _confirm_quit_action() -> void:
	stop_recording()
	get_tree().quit()

func _cancel_quit_action() -> void:
	if quit_confirm_modal and is_instance_valid(quit_confirm_modal):
		quit_confirm_modal.visible = false

func _show_quit_confirmation_modal() -> void:
	if quit_confirm_modal != null and is_instance_valid(quit_confirm_modal):
		quit_confirm_modal.visible = true
		return

	quit_confirm_modal = PanelContainer.new()
	quit_confirm_modal.name = "QuitConfirmModal"
	quit_confirm_modal.custom_minimum_size = Vector2(420, 180)

	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.12, 0.98)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(1.0, 0.25, 0.25, 0.95)
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	quit_confirm_modal.add_theme_stylebox_override("panel", sb)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	quit_confirm_modal.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title = Label.new()
	title.text = "ARE YOU SURE YOU WANT TO QUIT?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	vbox.add_child(title)

	var sub = Label.new()
	sub.text = "All unsaved simulation progress will be closed."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.85))
	vbox.add_child(sub)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var btn_yes = Button.new()
	btn_yes.text = "YES, QUIT GAME"
	btn_yes.custom_minimum_size = Vector2(170, 42)
	btn_yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_modal_red_button(btn_yes)
	btn_yes.pressed.connect(_confirm_quit_action)
	hbox.add_child(btn_yes)

	var btn_no = Button.new()
	btn_no.text = "CANCEL"
	btn_no.custom_minimum_size = Vector2(140, 42)
	btn_no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_dev_button(btn_no)
	btn_no.pressed.connect(_cancel_quit_action)
	hbox.add_child(btn_no)

	vbox.add_child(hbox)

	add_child(quit_confirm_modal)
	quit_confirm_modal.visible = true

func _style_modal_red_button(btn: Button) -> void:
	if not btn: return
	var sb_normal = StyleBoxFlat.new()
	sb_normal.bg_color = Color(0.55, 0.08, 0.08, 0.92)
	sb_normal.border_width_left = 1
	sb_normal.border_width_top = 1
	sb_normal.border_width_right = 1
	sb_normal.border_width_bottom = 1
	sb_normal.border_color = Color(1.0, 0.25, 0.25, 1.0)
	sb_normal.corner_radius_top_left = 8
	sb_normal.corner_radius_top_right = 8
	sb_normal.corner_radius_bottom_left = 8
	sb_normal.corner_radius_bottom_right = 8

	var sb_hover = sb_normal.duplicate() as StyleBoxFlat
	sb_hover.bg_color = Color(0.8, 0.12, 0.12, 0.98)
	sb_hover.border_color = Color(1.0, 0.5, 0.5, 1.0)

	btn.add_theme_stylebox_override("normal", sb_normal)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_hover)
	btn.add_theme_stylebox_override("focus", sb_hover)
	btn.add_theme_color_override("font_color", Color(1.0, 0.95, 0.95))

func _style_dev_button(btn: Button) -> void:
	if not btn: return
	var sb_normal = StyleBoxFlat.new()
	sb_normal.bg_color = Color(0.08, 0.14, 0.22, 0.9)
	sb_normal.border_width_left = 1
	sb_normal.border_width_top = 1
	sb_normal.border_width_right = 1
	sb_normal.border_width_bottom = 1
	sb_normal.border_color = Color(0.2, 0.55, 0.85, 0.85)
	sb_normal.corner_radius_top_left = 8
	sb_normal.corner_radius_top_right = 8
	sb_normal.corner_radius_bottom_left = 8
	sb_normal.corner_radius_bottom_right = 8

	var sb_hover = sb_normal.duplicate() as StyleBoxFlat
	sb_hover.bg_color = Color(0.12, 0.22, 0.35, 0.95)
	sb_hover.border_color = Color(0.3, 0.85, 1.0, 1.0)

	btn.add_theme_stylebox_override("normal", sb_normal)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_hover)
	btn.add_theme_stylebox_override("focus", sb_hover)
	btn.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))

func _get_active_drone() -> Node:
	var scene = get_tree().current_scene if get_tree() else null
	if not scene: return null
	var single = scene.get_node_or_null("SingleDroneController")
	if single and "drone" in single and single.drone and is_instance_valid(single.drone):
		return single.drone
	var manager = scene.get_node_or_null("DroneControllerManager")
	if manager and "drone" in manager and manager.drone and is_instance_valid(manager.drone):
		return manager.drone
	return scene.find_child("Drone", true, false)

func _show_dev_status(msg: String) -> void:
	if dev_status_label:
		dev_status_label.text = "Status: " + msg
		dev_status_label.add_theme_color_override("font_color", Color(0.2, 0.95, 1.0))

func _on_dev_drain_battery(amount: float) -> void:
	var drone = _get_active_drone()
	if drone:
		if drone.has_method("drain_battery"):
			drone.drain_battery(amount)
		elif drone.get("battery_manager") and is_instance_valid(drone.battery_manager):
			if drone.battery_manager.has_method("drain"):
				drone.battery_manager.drain(amount)
			else:
				drone.battery_manager.battery_percent = maxf(0.0, drone.battery_manager.battery_percent - amount)
	_show_dev_status("Drained Battery by " + str(int(amount)) + "%")

func _on_dev_set_battery(val: float) -> void:
	var drone = _get_active_drone()
	if drone:
		if drone.has_method("set_battery_percent"):
			drone.set_battery_percent(val)
		elif drone.get("battery_manager") and is_instance_valid(drone.battery_manager):
			if drone.battery_manager.has_method("set_percent"):
				drone.battery_manager.set_percent(val)
			else:
				drone.battery_manager.battery_percent = val
	_show_dev_status("Set Battery to " + str(int(val)) + "%")

func _on_dev_toggle_infinite_battery() -> void:
	var drone = _get_active_drone()
	if drone:
		var bm = drone.get("battery_manager")
		if bm and is_instance_valid(bm):
			var curr = bm.infinite_battery if "infinite_battery" in bm else false
			if drone.has_method("set_infinite_battery_enabled"):
				drone.set_infinite_battery_enabled(not curr)
			elif bm.has_method("set_infinite_battery"):
				bm.set_infinite_battery(not curr)
			_show_dev_status("Infinite Battery: " + ("ENABLED" if not curr else "DISABLED"))

func _on_dev_set_drain_mult(mult: float) -> void:
	current_drain_mult = mult
	var drone = _get_active_drone()
	if drone and drone.get("battery_manager") and is_instance_valid(drone.battery_manager):
		drone.battery_manager.drain_mult = mult
	_show_dev_status("Battery Drain Speed: " + str(mult) + "x")

func _on_dev_set_gravity(scale: float) -> void:
	var drone = _get_active_drone()
	if drone and "gravity_scale" in drone:
		drone.gravity_scale = scale
	_show_dev_status("Gravity Scale: " + str(scale) + "x " + ("(Zero-G Floating!)" if scale == 0.0 else ""))

func _on_dev_set_timescale(scale: float) -> void:
	Engine.time_scale = scale
	_show_dev_status("Time Scale: " + str(scale) + "x " + ("(Matrix Slow-Mo!)" if scale < 1.0 else ""))

func _on_dev_toggle_god_mode() -> void:
	god_mode_active = not god_mode_active
	var drone = _get_active_drone()
	if drone:
		drone.set("god_mode", god_mode_active)
	_show_dev_status("God Mode / Invincibility: " + ("ENABLED" if god_mode_active else "DISABLED"))

func _on_dev_set_thrust_mult(mult: float) -> void:
	var drone = _get_active_drone()
	if drone and "thrust_force" in drone:
		drone.thrust_force = 45.0 * mult
	_show_dev_status("Motor Thrust: " + str(mult) + "x " + ("(Rocket Thrust!)" if mult > 1.0 else ""))

func _style_dev_option_button(opt: OptionButton) -> void:
	if not opt: return
	var sb_normal = StyleBoxFlat.new()
	sb_normal.bg_color = Color(0.08, 0.14, 0.22, 0.9)
	sb_normal.border_width_left = 1
	sb_normal.border_width_top = 1
	sb_normal.border_width_right = 1
	sb_normal.border_width_bottom = 1
	sb_normal.border_color = Color(0.2, 0.55, 0.85, 0.85)
	sb_normal.corner_radius_top_left = 8
	sb_normal.corner_radius_top_right = 8
	sb_normal.corner_radius_bottom_left = 8
	sb_normal.corner_radius_bottom_right = 8
	sb_normal.content_margin_left = 12
	sb_normal.content_margin_right = 12
	sb_normal.content_margin_top = 6
	sb_normal.content_margin_bottom = 6

	var sb_hover = sb_normal.duplicate() as StyleBoxFlat
	sb_hover.bg_color = Color(0.12, 0.22, 0.35, 0.95)
	sb_hover.border_color = Color(0.3, 0.85, 1.0, 1.0)

	opt.add_theme_stylebox_override("normal", sb_normal)
	opt.add_theme_stylebox_override("hover", sb_hover)
	opt.add_theme_stylebox_override("pressed", sb_hover)
	opt.add_theme_stylebox_override("focus", sb_hover)
	opt.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	opt.add_theme_color_override("font_hover_color", Color(0.3, 0.95, 1.0))

func _add_dev_option_row(vbox: VBoxContainer, label_text: String, opt_button: OptionButton) -> void:
	var row = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 34)

	var lbl = Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.92, 0.98))
	row.add_child(lbl)

	opt_button.custom_minimum_size = Vector2(230, 32)
	_style_dev_option_button(opt_button)
	row.add_child(opt_button)

	vbox.add_child(row)

func _on_dev_battery_preset_selected(idx: int) -> void:
	match idx:
		0: _on_dev_set_battery(100.0)
		1: _on_dev_set_battery(75.0)
		2: _on_dev_set_battery(50.0)
		3: _on_dev_set_battery(10.0)
		4: _on_dev_set_battery(0.0)

func _on_dev_drain_speed_selected(idx: int) -> void:
	match idx:
		0: _on_dev_set_drain_mult(1.0)
		1: _on_dev_set_drain_mult(5.0)
		2: _on_dev_set_drain_mult(20.0)

func _on_dev_infinite_battery_selected(idx: int) -> void:
	var drone = _get_active_drone()
	if drone:
		var enabled = (idx == 1)
		if drone.has_method("set_infinite_battery_enabled"):
			drone.set_infinite_battery_enabled(enabled)
		elif drone.get("battery_manager") and is_instance_valid(drone.battery_manager):
			drone.battery_manager.infinite_battery = enabled
		_show_dev_status("Infinite Battery: " + ("ENABLED" if enabled else "DISABLED"))

func _on_dev_gravity_selected(idx: int) -> void:
	match idx:
		0: _on_dev_set_gravity(1.0)
		1: _on_dev_set_gravity(0.0)
		2: _on_dev_set_gravity(0.3)
		3: _on_dev_set_gravity(2.5)

func _on_dev_timescale_selected(idx: int) -> void:
	match idx:
		0: _on_dev_set_timescale(1.0)
		1: _on_dev_set_timescale(0.25)
		2: _on_dev_set_timescale(0.5)
		3: _on_dev_set_timescale(2.0)

func _on_dev_god_mode_selected(idx: int) -> void:
	god_mode_active = (idx == 1)
	var drone = _get_active_drone()
	if drone:
		drone.set("god_mode", god_mode_active)
	_show_dev_status("God Mode / Invincibility: " + ("ENABLED" if god_mode_active else "DISABLED"))

func _on_dev_thrust_selected(idx: int) -> void:
	match idx:
		0: _on_dev_set_thrust_mult(1.0)
		1: _on_dev_set_thrust_mult(2.5)

func _build_dev_menu_panel(main_layout: Node) -> void:
	if dev_menu_panel != null: return

	dev_menu_panel = PanelContainer.new()
	dev_menu_panel.name = "DevMenuPanel"
	dev_menu_panel.custom_minimum_size = Vector2(560, 520)

	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.12, 0.95)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.2, 0.85, 1.0, 0.85)
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	dev_menu_panel.add_theme_stylebox_override("panel", sb)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	dev_menu_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title = Label.new()
	title.text = "DEV TOOLS & SIMULATION MODIFIERS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.2, 0.85, 1.0, 1.0))
	vbox.add_child(title)

	dev_status_label = Label.new()
	dev_status_label.text = "Status: Ready (Select a Dev Modifier below)"
	dev_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dev_status_label.add_theme_font_size_override("font_size", 11)
	dev_status_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.8))
	vbox.add_child(dev_status_label)

	var sep1 = HSeparator.new()
	vbox.add_child(sep1)

	# --- SECTION 1: BATTERY CONTROLS ---
	var cat1 = Label.new()
	cat1.text = "BATTERY DRAIN & REFILL OPTIONS"
	cat1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cat1.add_theme_font_size_override("font_size", 12)
	cat1.add_theme_color_override("font_color", Color(0.2, 0.85, 1.0, 0.9))
	vbox.add_child(cat1)

	# Row 1: Battery Level Preset
	var opt_bat = OptionButton.new()
	opt_bat.add_item("100% (Instant Recharge)")
	opt_bat.add_item("75% (Drain -25%)")
	opt_bat.add_item("50% (Drain -50%)")
	opt_bat.add_item("10% (Low Warning)")
	opt_bat.add_item("0% (Empty)")
	opt_bat.item_selected.connect(_on_dev_battery_preset_selected)
	_add_dev_option_row(vbox, "Battery Charge Preset", opt_bat)

	# Row 2: Battery Drain Speed
	var opt_drain = OptionButton.new()
	opt_drain.add_item("1x Normal Speed")
	opt_drain.add_item("5x Fast Drain")
	opt_drain.add_item("20x Turbo Drain")
	opt_drain.item_selected.connect(_on_dev_drain_speed_selected)
	_add_dev_option_row(vbox, "Battery Drain Speed", opt_drain)

	# Row 3: Infinite Battery Mode
	var opt_inf = OptionButton.new()
	opt_inf.add_item("Disabled")
	opt_inf.add_item("Enabled")
	opt_inf.item_selected.connect(_on_dev_infinite_battery_selected)
	_add_dev_option_row(vbox, "Infinite Battery Mode", opt_inf)

	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	# --- SECTION 2: DRASTIC PHYSICS & WORLD MODIFIERS ---
	var cat2 = Label.new()
	cat2.text = "DRASTIC PHYSICS & ENVIRONMENT MODIFIERS"
	cat2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cat2.add_theme_font_size_override("font_size", 12)
	cat2.add_theme_color_override("font_color", Color(0.2, 0.85, 1.0, 0.9))
	vbox.add_child(cat2)

	# Row 4: World Gravity
	var opt_grav = OptionButton.new()
	opt_grav.add_item("1.0x Normal Gravity")
	opt_grav.add_item("0.0x Zero-G Floating")
	opt_grav.add_item("0.3x Lunar Low-G")
	opt_grav.add_item("2.5x Heavy Gravity")
	opt_grav.item_selected.connect(_on_dev_gravity_selected)
	_add_dev_option_row(vbox, "World Gravity Scale", opt_grav)

	# Row 5: Time Scale (Slow-Mo)
	var opt_time = OptionButton.new()
	opt_time.add_item("1.0x Normal Speed")
	opt_time.add_item("0.25x Matrix Slow-Mo")
	opt_time.add_item("0.5x Half Speed")
	opt_time.add_item("2.0x Fast-Forward")
	opt_time.item_selected.connect(_on_dev_timescale_selected)
	_add_dev_option_row(vbox, "Time Scale (Slow-Mo)", opt_time)

	# Row 6: God Mode / Invincibility
	var opt_god = OptionButton.new()
	opt_god.add_item("Disabled (Normal Damage)")
	opt_god.add_item("Enabled (Invincible)")
	opt_god.item_selected.connect(_on_dev_god_mode_selected)
	_add_dev_option_row(vbox, "God Mode (Invincibility)", opt_god)

	# Row 7: Motor Thrust Power
	var opt_thrust = OptionButton.new()
	opt_thrust.add_item("1.0x Normal Thrust")
	opt_thrust.add_item("2.5x Rocket Thrust")
	opt_thrust.item_selected.connect(_on_dev_thrust_selected)
	_add_dev_option_row(vbox, "Motor Thrust Power", opt_thrust)

	main_layout.add_child(dev_menu_panel)
	dev_menu_panel.visible = false
