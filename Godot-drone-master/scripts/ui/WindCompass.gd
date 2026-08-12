extends CanvasLayer
## Redesigned Wind Compass HUD showing wind origin, push direction, real-time velocity,
## drone nose orientation pointer, and instant relative flight effect badges.
class_name WindCompass

const COMPASS_RADIUS := 80.0
const ARROW_LEN      := 58.0
const RIBBON_COUNT   := 14
const RIBBON_LEN     := 68.0
const RIBBON_SPACING := 6.0
const ARC_WIDTH      := 10.0
const PANEL_MARGIN   := 18.0

var _wind_direction: Vector3 = Vector3(1.0, 0.0, 0.0) # direction wind is pushing
var _wind_strength: float    = 0.0
var _gust_factor: float      = 0.0
var _state_name: String      = "Normal"
var _smooth_strength: float  = 0.0
var _smooth_angle: float     = 0.0   # 2D screen radians
var _smooth_drone_angle: float = 0.0
var _gust_flash: float       = 0.0
var _prev_gust_factor: float = 0.0
var _time: float             = 0.0

var _canvas: Control
var _wind_manager: WindManager = null
var target_drone: Node3D = null

func _ready() -> void:
	layer = 125
	process_mode = Node.PROCESS_MODE_ALWAYS
	var margin = get_node_or_null("Margin")
	if margin: margin.layout_direction = Control.LAYOUT_DIRECTION_LTR
	_canvas = Control.new()
	_canvas.layout_direction = Control.LAYOUT_DIRECTION_LTR
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)
	_connect_wind_manager()

	var theme_mgr = get_node_or_null("/root/ThemeManager")
	if theme_mgr:
		theme_mgr.theme_changed.connect(func(_new_theme: String):
			if _canvas and is_instance_valid(_canvas):
				_canvas.queue_redraw()
		)

var _connect_retries: int = 0

func _connect_wind_manager() -> void:
	if not is_inside_tree():
		return
	_wind_manager = _find_wind_manager()
	if _wind_manager:
		if not _wind_manager.wind_changed.is_connected(_on_wind_changed):
			_wind_manager.wind_changed.connect(_on_wind_changed)
	elif is_inside_tree() and _connect_retries < 30:
		_connect_retries += 1
		call_deferred("_connect_wind_manager")

func _find_wind_manager() -> WindManager:
	var scene := get_tree().current_scene if get_tree() else null
	if scene == null:
		return null
	var direct := scene.get_node_or_null("WindManager")
	if direct is WindManager:
		return direct as WindManager
	for child in scene.get_children():
		if child is WindManager:
			return child as WindManager
		var nested := child.find_child("WindManager", true, false)
		if nested is WindManager:
			return nested as WindManager
	return null

func _find_target_drone() -> void:
	if target_drone and is_instance_valid(target_drone):
		return
	var scene := get_tree().current_scene if get_tree() else null
	if scene:
		var manager = scene.get_node_or_null("DroneControllerManager")
		if manager and "drone" in manager and manager.drone and is_instance_valid(manager.drone):
			target_drone = manager.drone
			return
		target_drone = scene.find_child("Drone", true, false)

func _on_wind_changed(direction: Vector3, strength: float, gust_factor: float, state_name: String) -> void:
	_wind_direction = direction
	_wind_strength  = strength
	_gust_factor    = gust_factor
	_state_name     = state_name
	if gust_factor - _prev_gust_factor > 0.18:
		_gust_flash = 1.0
	_prev_gust_factor = gust_factor

func _process(delta: float) -> void:
	if get_tree() and get_tree().paused:
		return

	_time += delta
	_smooth_strength = lerpf(_smooth_strength, _wind_strength, delta * 3.5)

	# 2D Screen Angle for wind push (x = East/Right, z = South/Down)
	var target_angle := atan2(_wind_direction.z, _wind_direction.x)
	var angle_diff := fmod(target_angle - _smooth_angle + PI * 3.0, TAU) - PI
	_smooth_angle += angle_diff * delta * 5.0

	_find_target_drone()
	if target_drone and is_instance_valid(target_drone):
		# Drone facing direction in 2D screen coordinates (-z = North/Up, x = East/Right)
		var fwd := -target_drone.global_transform.basis.z
		var target_d_angle := atan2(fwd.z, fwd.x)
		var d_diff := fmod(target_d_angle - _smooth_drone_angle + PI * 3.0, TAU) - PI
		_smooth_drone_angle += d_diff * delta * 12.0

	_gust_flash = maxf(0.0, _gust_flash - delta * 2.2)

	if _wind_manager == null:
		_wind_manager = _find_wind_manager()
		if _wind_manager and not _wind_manager.wind_changed.is_connected(_on_wind_changed):
			_wind_manager.wind_changed.connect(_on_wind_changed)

	_canvas.queue_redraw()

func _on_draw() -> void:
	var vp_size := _canvas.get_rect().size
	var cx := COMPASS_RADIUS + PANEL_MARGIN + ARC_WIDTH + 8.0
	var cy := vp_size.y - COMPASS_RADIUS - PANEL_MARGIN - ARC_WIDTH - 42.0
	var center := Vector2(cx, cy)

	_draw_backing(center)
	_draw_speed_arc(center)
	_draw_cardinal_labels(center)
	_draw_flow_ribbons(center)
	_draw_compass_ring(center)
	_draw_drone_pointer(center)
	_draw_direction_arrow(center)
	_draw_state_badge(center)
	if _gust_flash > 0.01:
		_draw_gust_flash(center)

func _draw_backing(center: Vector2) -> void:
	var theme_mgr = get_node_or_null("/root/ThemeManager")
	var is_light = (theme_mgr and theme_mgr.current_ui_theme == "light")
	var r := COMPASS_RADIUS + ARC_WIDTH + 4.0
	var shadow_col := Color(0.0, 0.0, 0.0, 0.15) if is_light else Color(0.0, 0.0, 0.0, 0.30)
	var bg_col := Color(0.88, 0.91, 0.95, 0.94) if is_light else Color(0.03, 0.06, 0.10, 0.85)
	_canvas.draw_circle(center, r + 4.0, shadow_col)
	_canvas.draw_circle(center, r, bg_col)

func _draw_speed_arc(center: Vector2) -> void:
	var max_speed := 8.0
	var fill := clampf(_smooth_strength / max_speed, 0.0, 1.0)
	var r := COMPASS_RADIUS + ARC_WIDTH * 0.5

	_draw_arc_thick(center, r, 0.0, TAU, ARC_WIDTH, Color(0.1, 0.15, 0.22, 0.5))

	if fill > 0.001:
		var arc_col := _speed_colour(fill)
		_draw_arc_thick(center, r, -PI * 0.5, -PI * 0.5 + fill * TAU, ARC_WIDTH, arc_col)

func _speed_colour(t: float) -> Color:
	if t < 0.4:
		return Color(0.2, 0.85, 1.0, 0.95).lerp(Color(0.3, 0.65, 1.0, 0.95), t / 0.4)
	elif t < 0.75:
		return Color(0.3, 0.65, 1.0, 0.95).lerp(Color(1.0, 0.65, 0.15, 0.95), (t - 0.4) / 0.35)
	else:
		return Color(1.0, 0.65, 0.15, 0.95).lerp(Color(1.0, 0.2, 0.1, 0.98), (t - 0.75) / 0.25)

func _draw_arc_thick(center: Vector2, radius: float, from_angle: float, to_angle: float, width: float, color: Color) -> void:
	var steps: int = max(int(abs(to_angle - from_angle) / 0.08), 6)
	var prev := Vector2.ZERO
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var a := lerpf(from_angle, to_angle, t)
		var pt := center + Vector2(cos(a), sin(a)) * radius
		if i > 0:
			_canvas.draw_line(prev, pt, color, width, true)
		prev = pt

func _draw_compass_ring(center: Vector2) -> void:
	var theme_mgr = get_node_or_null("/root/ThemeManager")
	var is_light = (theme_mgr and theme_mgr.current_ui_theme == "light")
	var ring_col := Color(0.12, 0.45, 0.85, 0.8) if is_light else Color(0.2, 0.75, 1.0, 0.7)
	_draw_arc_thick(center, COMPASS_RADIUS, 0.0, TAU, 1.8, ring_col)

	for i in range(8):
		var angle := (PI / 4.0) * float(i)
		var inner := COMPASS_RADIUS - (8.0 if i % 2 == 0 else 4.0)
		var p0 := center + Vector2(cos(angle), sin(angle)) * inner
		var p1 := center + Vector2(cos(angle), sin(angle)) * COMPASS_RADIUS
		var col := Color(0.12, 0.45, 0.85, 0.9) if is_light else (Color(0.75, 0.92, 1.0, 0.85) if i % 2 == 0 else Color(0.5, 0.75, 0.95, 0.5))
		_canvas.draw_line(p0, p1, col, 1.5)

func _draw_cardinal_labels(center: Vector2) -> void:
	var theme_mgr = get_node_or_null("/root/ThemeManager")
	var is_light = (theme_mgr and theme_mgr.current_ui_theme == "light")
	var cardinals := {
		"N": -PI * 0.5,
		"E": 0.0,
		"S": PI * 0.5,
		"W": PI,
	}
	var label_r := COMPASS_RADIUS - 18.0
	for label in cardinals:
		var a: float = cardinals[label]
		var pt := center + Vector2(cos(a), sin(a)) * label_r - Vector2(5.0, 7.0)
		var col: Color
		if label == "N":
			col = Color(0.85, 0.15, 0.15, 1.0) if is_light else Color(1.0, 0.35, 0.35, 1.0)
		else:
			col = Color(0.06, 0.10, 0.18, 0.95) if is_light else Color(0.9, 0.95, 1.0, 0.9)
		_canvas.draw_string(ThemeDB.fallback_font, pt, label, HORIZONTAL_ALIGNMENT_CENTER, -1, 13, col)

func _draw_flow_ribbons(center: Vector2) -> void:
	if _smooth_strength < 0.05:
		return

	var flow_angle := _smooth_angle
	var speed_t := clampf(_smooth_strength / 7.0, 0.0, 1.0)
	var ribbon_alpha := lerpf(0.12, 0.60, speed_t)
	var ribbon_speed := lerpf(24.0, 70.0, speed_t)
	var ribbon_len_t := lerpf(20.0, RIBBON_LEN, speed_t)

	var perp := Vector2(cos(flow_angle + PI * 0.5), sin(flow_angle + PI * 0.5))
	var flow := Vector2(cos(flow_angle), sin(flow_angle))

	for i in range(RIBBON_COUNT):
		var idx := i - RIBBON_COUNT / 2
		var offset := perp * idx * RIBBON_SPACING
		var t_offset := fmod(_time * ribbon_speed + float(i) * 8.5, RIBBON_LEN * 1.8)

		for seg in range(6):
			var t0 := t_offset + seg * ribbon_len_t / 6.0
			var t1 := t0 + ribbon_len_t / 6.0
			var edge_fade := 1.0 - clampf((t0 / RIBBON_LEN) * 0.9, 0.0, 0.9)
			var seg_alpha := ribbon_alpha * edge_fade * lerpf(0.2, 1.0, float(seg + 1) / 6.0)

			var p0 := center + offset + flow * fmod(t0, RIBBON_LEN)
			var p1 := center + offset + flow * fmod(t1, RIBBON_LEN)
			if center.distance_to(p0) < COMPASS_RADIUS - 4.0 and center.distance_to(p1) < COMPASS_RADIUS - 4.0:
				var col := Color(0.3, 0.85, 1.0, seg_alpha)
				_canvas.draw_line(p0, p1, col, lerpf(1.2, 2.2, speed_t), true)

func _draw_drone_pointer(center: Vector2) -> void:
	if not target_drone or not is_instance_valid(target_drone):
		return
	var angle := _smooth_drone_angle
	var dir := Vector2(cos(angle), sin(angle))
	var perp := Vector2(-dir.y, dir.x)
	var tip := center + dir * (COMPASS_RADIUS - 10.0)

	_canvas.draw_line(center, tip, Color(0.2, 0.85, 1.0, 0.6), 1.5, true)
	var head_back := tip - dir * 10.0
	var h_left := head_back + perp * 5.0
	var h_right := head_back - perp * 5.0
	_canvas.draw_colored_polygon(PackedVector2Array([tip, h_left, h_right]), Color(0.2, 0.85, 1.0, 0.9))

func _draw_direction_arrow(center: Vector2) -> void:
	var angle := _smooth_angle
	var dir := Vector2(cos(angle), sin(angle))
	var perp := Vector2(-dir.y, dir.x)

	var tip := center + dir * ARROW_LEN
	var base := center - dir * (ARROW_LEN * 0.35)

	_canvas.draw_line(base, tip, Color(1.0, 1.0, 1.0, 0.4), 2.5, true)

	var head_back := tip - dir * 16.0
	var h_left := head_back + perp * 8.0
	var h_right := head_back - perp * 8.0

	var speed_t := clampf(_smooth_strength / 7.0, 0.0, 1.0)
	var arrow_col := _speed_colour(speed_t).lightened(0.2)
	arrow_col.a = 1.0

	var pts := PackedVector2Array([tip, h_left, h_right])
	_canvas.draw_colored_polygon(pts, arrow_col)
	_canvas.draw_polyline(PackedVector2Array([h_left, tip, h_right]), Color(1.0, 1.0, 1.0, 0.8), 1.6, true)

	_canvas.draw_circle(center, 4.0, Color(1.0, 1.0, 1.0, 0.85))
	_canvas.draw_arc(center, 4.0, 0.0, TAU, 16, Color(0.2, 0.8, 1.0, 0.9), 1.2)

func _draw_state_badge(center: Vector2) -> void:
	var speed_t := clampf(_smooth_strength / 7.0, 0.0, 1.0)
	var badge_col := _speed_colour(speed_t)

	var tm = get_node_or_null("/root/TranslationManager")

	var raw_origin := _wind_manager.get_wind_origin_name() if _wind_manager else "EAST"
	var raw_push   := _wind_manager.get_wind_push_name() if _wind_manager else "WEST"

	var origin_name = tm.get_auto_translation("DIR_" + raw_origin) if tm else raw_origin
	var push_name   = tm.get_auto_translation("DIR_" + raw_push) if tm else raw_push

	var text_line1: String = (tm.get_auto_translation("HUD_WIND_FROM") if tm else "WIND: FROM %s") % origin_name
	var text_line2: String = (tm.get_auto_translation("HUD_WIND_PUSH") if tm else "PUSH: %s (%.1f m/s)") % [push_name, _smooth_strength]
	if tm and tm.is_rtl():
		text_line2 += "\u200E"

	var effect_text: String = tm.get_auto_translation("HUD_EFFECT_DRIFT") if tm else "EFFECT: BALANCED DRIFT"
	if target_drone and is_instance_valid(target_drone):
		var fwd := -target_drone.global_transform.basis.z
		var right := target_drone.global_transform.basis.x
		var tailwind := fwd.dot(_wind_direction)
		var crosswind := right.dot(_wind_direction)

		if tailwind > 0.4:
			effect_text = tm.get_auto_translation("HUD_EFFECT_TAILWIND") if tm else "EFFECT: TAILWIND (PUSHING NOSE)"
		elif tailwind < -0.4:
			effect_text = tm.get_auto_translation("HUD_EFFECT_HEADWIND") if tm else "EFFECT: HEADWIND (RESISTING NOSE)"
		elif crosswind > 0.3:
			effect_text = tm.get_auto_translation("HUD_EFFECT_CROSS_RIGHT") if tm else "EFFECT: CROSSWIND (PUSHING RIGHT)"
		elif crosswind < -0.3:
			effect_text = tm.get_auto_translation("HUD_EFFECT_CROSS_LEFT") if tm else "EFFECT: CROSSWIND (PUSHING LEFT)"
		else:
			effect_text = tm.get_auto_translation("HUD_EFFECT_DRIFT") if tm else "EFFECT: BALANCED DRIFT"

	var pos1 := center + Vector2(-48.0, COMPASS_RADIUS + ARC_WIDTH + 8.0)
	var pos2 := pos1 + Vector2(0, 13)
	var pos3 := pos2 + Vector2(0, 13)

	_canvas.draw_string(ThemeDB.fallback_font, pos1 + Vector2(1, 1), text_line1, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.0, 0.0, 0.0, 0.8))
	_canvas.draw_string(ThemeDB.fallback_font, pos2 + Vector2(1, 1), text_line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.0, 0.0, 0.0, 0.8))
	_canvas.draw_string(ThemeDB.fallback_font, pos3 + Vector2(1, 1), effect_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.0, 0.0, 0.0, 0.8))

	_canvas.draw_string(ThemeDB.fallback_font, pos1, text_line1, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.95, 1.0, 0.9))
	_canvas.draw_string(ThemeDB.fallback_font, pos2, text_line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, badge_col)
	_canvas.draw_string(ThemeDB.fallback_font, pos3, effect_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.85, 1.0, 0.9))

func _draw_gust_flash(center: Vector2) -> void:
	var alpha := _gust_flash * 0.35
	_canvas.draw_circle(center, COMPASS_RADIUS + ARC_WIDTH + 4.0, Color(0.6, 0.9, 1.0, alpha))
