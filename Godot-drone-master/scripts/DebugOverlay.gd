extends CanvasLayer

const TOGGLE_KEY := KEY_V
const FONT_SIZE_FPS := 18
const FONT_SIZE_STATS := 14
const FONT_SIZE_BATTERY := 22
const BATTERY_PANEL_WIDTH := 210
const BATTERY_PANEL_HEIGHT := 76
const PANEL_WIDTH := 310
const PADDING := 10
const LINE_HEIGHT := 18
const UPDATE_INTERVAL := 0.15

var _visible := false
var _timer := 0.0

var _fps_label: Label
var _battery_panel: PanelContainer
var _battery_margin: MarginContainer
var _battery_vbox: VBoxContainer
var _battery_icon_box: Control
var _battery_percent_label: Label
var _battery_status_label: Label
var _stats_panel: PanelContainer
var _stats_label: Label

var _stat_lines: Array[String] = []

func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_fps_label()
	_build_battery_hud()
	_build_stats_panel()
	_apply_visibility()
	
	var theme_mgr = get_node_or_null("/root/ThemeManager")
	if theme_mgr:
		theme_mgr.theme_changed.connect(func(_t): _update_battery_theme())

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == TOGGLE_KEY:
			_visible = !_visible
			_apply_visibility()

func _process(delta: float) -> void:
	var fps := Engine.get_frames_per_second()
	var fps_color := _fps_color(fps)
	if _fps_label:
		_fps_label.text = "FPS: %d" % fps
		_fps_label.add_theme_color_override("font_color", fps_color)

	_update_battery_display()

	if not _visible:
		return

	_timer += delta
	if _timer >= UPDATE_INTERVAL:
		_timer = 0.0
		_refresh_stats()
		_stats_label.text = "\n".join(_stat_lines)

func _refresh_stats() -> void:
	_stat_lines.clear()

	var vp := get_viewport()
	var rs := RenderingServer

	var fps := Engine.get_frames_per_second()
	var ms  := 0.0
	if fps > 0:
		ms = 1000.0 / fps
	_stat_lines.append("─── Performance ───────────────")
	_stat_lines.append("FPS:        %d  (%.2f ms)" % [fps, ms])
	_stat_lines.append("Preset:     %s" % _get_preset_name())
	_stat_lines.append("Engine ver: %s" % Engine.get_version_info().string)

	var static_mem  := float(OS.get_static_memory_usage())
	var static_peak := float(OS.get_static_memory_peak_usage())
	_stat_lines.append("")
	_stat_lines.append("─── System RAM ─────────────────")
	_stat_lines.append("RAM Used:   %s" % _fmt_bytes(static_mem))
	_stat_lines.append("RAM Peak:   %s" % _fmt_bytes(static_peak))

	var tex_mem    := float(rs.get_rendering_info(rs.RENDERING_INFO_TEXTURE_MEM_USED))
	var buf_mem    := float(rs.get_rendering_info(rs.RENDERING_INFO_BUFFER_MEM_USED))
	var total_vram := tex_mem + buf_mem
	_stat_lines.append("")
	_stat_lines.append("─── GPU / Hardware Specs ───────")
	_stat_lines.append("CPU:        %s" % OS.get_processor_name())
	_stat_lines.append("CPU Cores:  %d threads" % OS.get_processor_count())
	_stat_lines.append("GPU:        %s" % rs.get_video_adapter_name())
	_stat_lines.append("VRAM Total: %s" % _fmt_bytes(total_vram))
	_stat_lines.append("  Textures: %s" % _fmt_bytes(tex_mem))
	_stat_lines.append("  Buffers:  %s" % _fmt_bytes(buf_mem))

	var draw_calls := rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims      := rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var objects    := rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	_stat_lines.append("")
	_stat_lines.append("─── Render Stats ───────────────")
	_stat_lines.append("Draw Calls: %d" % draw_calls)
	_stat_lines.append("Objects:    %d" % objects)
	_stat_lines.append("Primitives: %s" % _fmt_large(prims))

	if vp:
		var vp_size := vp.get_visible_rect().size
		_stat_lines.append("")
		_stat_lines.append("─── Display & Viewport ─────────")
		_stat_lines.append("Resolution: %dx%d" % [int(vp_size.x), int(vp_size.y)])
		_stat_lines.append("OS Platform: %s" % OS.get_name())
		_stat_lines.append("MSAA:       %s" % _msaa_name(vp.msaa_3d))
		_stat_lines.append("V-Sync:     %s" % _vsync_name(DisplayServer.window_get_vsync_mode()))

	var node_count := _count_nodes(get_tree().root)
	_stat_lines.append("")
	_stat_lines.append("─── Scene Info ─────────────────")
	_stat_lines.append("Node count: %d" % node_count)
	_stat_lines.append("Scene:      %s" % (get_tree().current_scene.name if get_tree().current_scene else "—"))

	_stat_lines.append("")
	_stat_lines.append("[V] toggle debug hardware stats")

func _get_preset_name() -> String:
	var main_scene = get_tree().current_scene if get_tree() else null
	if main_scene:
		var hsm = main_scene.get_node_or_null("HardwareSettingsManager")
		if hsm and hsm.has_method("get_quality_tier_name"):
			return hsm.get_quality_tier_name()
	return "ULTRA (High-End GPU)"

func _build_fps_label() -> void:
	_fps_label = Label.new()
	_fps_label.add_theme_font_size_override("font_size", FONT_SIZE_FPS)
	_fps_label.add_theme_color_override("font_color", Color.WHITE)
	_fps_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_fps_label.add_theme_constant_override("shadow_offset_x", 2)
	_fps_label.add_theme_constant_override("shadow_offset_y", 2)
	_fps_label.add_theme_constant_override("shadow_outline_size", 1)
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.anchor_left   = 1.0
	_fps_label.anchor_right  = 1.0
	_fps_label.anchor_top    = 0.0
	_fps_label.anchor_bottom = 0.0
	_fps_label.offset_left   = -220
	_fps_label.offset_right  = -PADDING
	_fps_label.offset_top    = PADDING
	_fps_label.offset_bottom = PADDING + FONT_SIZE_FPS + 4
	add_child(_fps_label)

func _update_battery_theme() -> void:
	if not _battery_panel:
		return
	var theme_mgr = get_node_or_null("/root/ThemeManager")
	var is_light = (theme_mgr and theme_mgr.current_ui_theme == "light")

	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.set_border_width_all(2)

	if is_light:
		style.bg_color = Color(0.88, 0.91, 0.95, 0.94)
		style.border_color = Color(0.12, 0.45, 0.80, 0.75)
		style.shadow_color = Color(0.05, 0.10, 0.20, 0.12)
		style.shadow_size = 6
	else:
		style.bg_color = Color(0.03, 0.06, 0.10, 0.85)
		style.border_color = Color(0.2, 0.75, 0.95, 0.8)
		style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
		style.shadow_size = 6

	_battery_panel.add_theme_stylebox_override("panel", style)

func _build_battery_hud() -> void:
	_battery_panel = PanelContainer.new()
	_update_battery_theme()
	
	_battery_panel.anchor_left = 0.0
	_battery_panel.anchor_right = 0.0
	_battery_panel.anchor_top = 1.0
	_battery_panel.anchor_bottom = 1.0
	_battery_panel.offset_left = PADDING + 12
	_battery_panel.offset_right = PADDING + 12 + BATTERY_PANEL_WIDTH
	_battery_panel.offset_top = -(BATTERY_PANEL_HEIGHT + 235)
	_battery_panel.offset_bottom = -(235)

	_battery_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_battery_margin = MarginContainer.new()
	_battery_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_battery_panel.add_child(_battery_margin)

	_battery_vbox = VBoxContainer.new()
	_battery_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_battery_vbox.add_theme_constant_override("separation", 4)
	_battery_margin.add_child(_battery_vbox)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	_battery_vbox.add_child(hbox)

	_battery_percent_label = Label.new()
	_battery_percent_label.add_theme_font_size_override("font_size", FONT_SIZE_BATTERY)
	_battery_percent_label.text = "BATTERY 100%"
	hbox.add_child(_battery_percent_label)

	_battery_status_label = Label.new()
	_battery_status_label.add_theme_font_size_override("font_size", 12)
	_battery_status_label.text = "FLIGHT TIME: ~20 MIN"
	_battery_vbox.add_child(_battery_status_label)

	add_child(_battery_panel)
	_battery_panel.visible = true

func _build_stats_panel() -> void:
	_stats_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.04, 0.07, 0.88)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.2, 0.65, 0.9, 0.7)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_stats_panel.add_theme_stylebox_override("panel", style)

	_stats_panel.anchor_left   = 1.0
	_stats_panel.anchor_right  = 1.0
	_stats_panel.anchor_top    = 0.0
	_stats_panel.anchor_bottom = 1.0
	_stats_panel.offset_left   = -(PANEL_WIDTH + PADDING)
	_stats_panel.offset_right  = -PADDING
	_stats_panel.offset_top    = PADDING + FONT_SIZE_FPS + 14
	_stats_panel.offset_bottom = -PADDING

	_stats_label = Label.new()
	_stats_label.add_theme_font_size_override("font_size", FONT_SIZE_STATS)
	_stats_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_OFF

	var margin := MarginContainer.new()
	margin.add_child(_stats_label)
	_stats_panel.add_child(margin)
	add_child(_stats_panel)

func _apply_visibility() -> void:
	if _stats_panel: _stats_panel.visible = _visible
	if _fps_label: _fps_label.visible = true
	if _battery_panel: _battery_panel.visible = true

func set_battery_hud_visible(visible_flag: bool) -> void:
	if _battery_panel and is_instance_valid(_battery_panel):
		_battery_panel.visible = visible_flag

func _update_battery_display() -> void:
	var drone: Node = null
	var main_scene = get_tree().current_scene if get_tree() else null
	if main_scene:
		var manager = main_scene.get_node_or_null("DroneControllerManager")
		if not manager or not manager.get("drone"):
			manager = main_scene.get_node_or_null("SingleDroneController")
		if manager and "drone" in manager and manager.drone and is_instance_valid(manager.drone):
			drone = manager.drone
		elif main_scene.find_child("Drone", true, false):
			drone = main_scene.find_child("Drone", true, false)

	if not drone or not is_instance_valid(drone):
		return

	var pct: float = 100.0
	if drone.has_method("get_battery_percent"):
		pct = drone.get_battery_percent()
	elif "battery_percent" in drone and drone.battery_percent != null:
		pct = float(drone.battery_percent)

	var is_recharging: bool = drone.is_battery_recharging() if drone.has_method("is_battery_recharging") else false

	var theme_mgr = get_node_or_null("/root/ThemeManager")
	var is_light = (theme_mgr and theme_mgr.current_ui_theme == "light")

	if _battery_percent_label:
		_battery_percent_label.text = "BATTERY %d%%" % int(pct)
		if is_light:
			if pct > 40.0:
				_battery_percent_label.add_theme_color_override("font_color", Color(0.04, 0.55, 0.22))
			elif pct > 15.0:
				_battery_percent_label.add_theme_color_override("font_color", Color(0.85, 0.45, 0.0))
			else:
				_battery_percent_label.add_theme_color_override("font_color", Color(0.85, 0.15, 0.15))
		else:
			if pct > 40.0:
				_battery_percent_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.4))
			elif pct > 15.0:
				_battery_percent_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))
			else:
				_battery_percent_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25))

	if _battery_status_label:
		if is_recharging:
			_battery_status_label.text = "RECHARGING AT TOWER..."
			_battery_status_label.add_theme_color_override("font_color", Color(0.85, 0.45, 0.0) if is_light else Color(1.0, 0.65, 0.0))
		elif pct <= 3.0:
			_battery_status_label.text = "CRITICAL AUTO-LANDING"
			_battery_status_label.add_theme_color_override("font_color", Color(0.85, 0.15, 0.15) if is_light else Color(1.0, 0.2, 0.2))
		elif pct <= 20.0:
			_battery_status_label.text = "LOW BATTERY WARNING"
			_battery_status_label.add_theme_color_override("font_color", Color(0.85, 0.45, 0.0) if is_light else Color(1.0, 0.7, 0.2))
		else:
			_battery_status_label.text = "FLIGHT TIME: ~%d MIN" % int(pct * 0.2)
			_battery_status_label.add_theme_color_override("font_color", Color(0.06, 0.10, 0.18, 0.9) if is_light else Color(0.8, 0.9, 1.0, 0.8))

func _fps_color(fps: int) -> Color:
	if fps >= 55:
		return Color(0.2, 0.9, 0.4)
	elif fps >= 30:
		return Color(1.0, 0.8, 0.2)
	else:
		return Color(1.0, 0.3, 0.3)

func _fmt_bytes(bytes: float) -> String:
	if bytes < 1024.0:
		return "%.0f B" % bytes
	elif bytes < 1024.0 * 1024.0:
		return "%.1f KB" % (bytes / 1024.0)
	elif bytes < 1024.0 * 1024.0 * 1024.0:
		return "%.1f MB" % (bytes / (1024.0 * 1024.0))
	else:
		return "%.2f GB" % (bytes / (1024.0 * 1024.0 * 1024.0))

func _fmt_large(num: int) -> String:
	if num < 1000:
		return str(num)
	elif num < 1000000:
		return "%.1fk" % (float(num) / 1000.0)
	else:
		return "%.2fM" % (float(num) / 1000000.0)

func _msaa_name(msaa: Viewport.MSAA) -> String:
	match msaa:
		Viewport.MSAA_DISABLED: return "Off"
		Viewport.MSAA_2X:       return "2x"
		Viewport.MSAA_4X:       return "4x"
		Viewport.MSAA_8X:       return "8x"
		_:                      return "Custom"

func _vsync_name(mode: DisplayServer.VSyncMode) -> String:
	match mode:
		DisplayServer.VSYNC_DISABLED: return "Disabled"
		DisplayServer.VSYNC_ENABLED:  return "Enabled"
		DisplayServer.VSYNC_ADAPTIVE: return "Adaptive"
		DisplayServer.VSYNC_MAILBOX:  return "Mailbox"
		_:                            return "Unknown"

func _count_nodes(node: Node) -> int:
	if node == null: return 0
	var count := 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count
