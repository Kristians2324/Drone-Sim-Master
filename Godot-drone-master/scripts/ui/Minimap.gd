extends CanvasLayer
## HUD Minimap providing a clear top-down view of the 3D map, terrain, and objects,
## featuring a prominent player direction arrow and landmark markers.

const ARROW_LEN: float = 24.0

@onready var sub_viewport: SubViewport = $Margin/Panel/ViewportContainer/SubViewport
@onready var map_camera: Camera3D = $Margin/Panel/ViewportContainer/SubViewport/MapCamera
@onready var panel: Control = $Margin/Panel

var _canvas: Control
var target_drone: Node3D = null
var tower_position: Vector3 = Vector3(350.0, 0.0, 350.0)
var _smooth_heading: float = 0.0

func _ready() -> void:
	layer = 120
	var margin = get_node_or_null("Margin")
	if margin:
		margin.layout_direction = Control.LAYOUT_DIRECTION_LTR

	var trans_mgr = get_node_or_null("/root/TranslationManager")
	if trans_mgr:
		trans_mgr.locale_changed.connect(func(_l, _rtl):
			var m = get_node_or_null("Margin")
			if m: m.layout_direction = Control.LAYOUT_DIRECTION_LTR
		)

	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _canvas.draw.is_connected(_on_draw):
		_canvas.draw.connect(_on_draw)
	add_child(_canvas)
	
	if sub_viewport:
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		sub_viewport.msaa_3d = Viewport.MSAA_DISABLED
		sub_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		var container = sub_viewport.get_parent() as SubViewportContainer
		if container and not container.stretch:
			sub_viewport.size = Vector2i(256, 256)

	if map_camera:
		map_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		map_camera.size = 180.0
		var clean_env := Environment.new()
		clean_env.background_mode = Environment.BG_CLEAR_COLOR
		clean_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		clean_env.ambient_light_color = Color(1.0, 1.0, 1.0)
		clean_env.fog_enabled = false
		clean_env.volumetric_fog_enabled = false
		clean_env.glow_enabled = false
		clean_env.ssr_enabled = false
		clean_env.ssao_enabled = false
		clean_env.ssil_enabled = false
		map_camera.environment = clean_env

func _process(delta: float) -> void:
	_find_target_drone()
	_update_camera(delta)
	_canvas.queue_redraw()

func _find_target_drone() -> void:
	if target_drone and is_instance_valid(target_drone):
		return
	var world = get_tree().current_scene
	if world:
		var manager = world.get_node_or_null("DroneControllerManager")
		if manager and "drone" in manager and manager.drone and is_instance_valid(manager.drone):
			target_drone = manager.drone
			return
		target_drone = world.find_child("Drone", true, false)

func _update_camera(delta: float) -> void:
	if not target_drone or not is_instance_valid(target_drone):
		return
	var drone_pos = target_drone.global_position
	if map_camera:
		map_camera.global_position = Vector3(drone_pos.x, drone_pos.y + 180.0, drone_pos.z)
	
	# Smoothly interpolate 2D yaw heading for minimap direction arrow
	var target_heading: float = -target_drone.global_rotation.y
	var diff := fmod(target_heading - _smooth_heading + PI * 3.0, TAU) - PI
	_smooth_heading += diff * delta * 12.0

func _on_draw() -> void:
	if not panel:
		return
		
	var center: Vector2 = panel.global_position + panel.size / 2.0
	var radius: float = panel.size.x * 0.5 - 3.5
	
	_draw_thick_border_ring(center, radius)
	_draw_tower_marker(center, panel.size)
	_draw_player_direction_arrow(center)

func _draw_thick_border_ring(center: Vector2, radius: float) -> void:
	var theme_mgr = get_node_or_null("/root/ThemeManager")
	var is_light = (theme_mgr and theme_mgr.current_ui_theme == "light")
	var border_color := Color(0.12, 0.45, 0.85, 0.95) if is_light else Color(0.2, 0.75, 1.0, 0.95)
	var steps: int = 64
	var prev := center + Vector2(radius, 0)
	for i in range(1, steps + 1):
		var a := (TAU * float(i)) / float(steps)
		var pt := center + Vector2(cos(a), sin(a)) * radius
		_canvas.draw_line(prev, pt, border_color, 7.0, true)
		prev = pt

# ── Prominent Player Direction Arrow ─────────────────────────────────────────
func _draw_player_direction_arrow(center: Vector2) -> void:
	var angle := _smooth_heading - PI * 0.5 # Up = Forward flight heading
	var dir := Vector2(cos(angle), sin(angle))
	var perp := Vector2(-dir.y, dir.x)

	var tip := center + dir * ARROW_LEN
	var base := center - dir * (ARROW_LEN * 0.4)

	# Forward direction beam
	var sight_tip := center + dir * 45.0
	_canvas.draw_line(center, sight_tip, Color(0.2, 0.85, 1.0, 0.45), 1.5, true)

	# Arrow shaft outline & fill
	_canvas.draw_line(base, tip, Color(1.0, 1.0, 1.0, 0.9), 3.0, true)

	# Arrowhead
	var head_back := tip - dir * 14.0
	var h_left := head_back + perp * 9.0
	var h_right := head_back - perp * 9.0

	var arrow_col := Color(0.2, 0.85, 1.0, 1.0) # Bright neon cyan
	var pts := PackedVector2Array([tip, h_left, h_right])
	_canvas.draw_colored_polygon(pts, arrow_col)
	_canvas.draw_polyline(PackedVector2Array([h_left, tip, h_right]), Color(1.0, 1.0, 1.0, 0.9), 1.8, true)

	# Central position dot
	_canvas.draw_circle(center, 4.5, Color(1.0, 0.85, 0.2, 1.0)) # Golden center hub
	_canvas.draw_arc(center, 4.5, 0.0, TAU, 16, Color(1.0, 1.0, 1.0, 0.9), 1.2)

# ── Recharge Tower Indicator ────────────────────────────────────────────────
func _draw_tower_marker(center: Vector2, panel_size: Vector2) -> void:
	if not target_drone or not is_instance_valid(target_drone) or not map_camera:
		return
		
	var drone_pos = target_drone.global_position
	var diff_x: float = tower_position.x - drone_pos.x
	var diff_z: float = tower_position.z - drone_pos.z
	
	var map_span: float = map_camera.size
	var rel_x: float = (diff_x / map_span) * panel_size.x
	var rel_y: float = (diff_z / map_span) * panel_size.y
	
	var offset_2d := Vector2(rel_x, rel_y)
	var max_radius: float = panel_size.x * 0.5 - 16.0
	if offset_2d.length() > max_radius:
		offset_2d = offset_2d.normalized() * max_radius
		
	var marker_pos := center + offset_2d
	
	# Draw glowing orange diamond icon for Recharge Tower
	var d_size := 7.0
	var d_pts := PackedVector2Array([
		marker_pos + Vector2(0, -d_size),
		marker_pos + Vector2(d_size, 0),
		marker_pos + Vector2(0, d_size),
		marker_pos + Vector2(-d_size, 0)
	])
	_canvas.draw_colored_polygon(d_pts, Color(1.0, 0.5, 0.0, 0.95))
	_canvas.draw_polyline(PackedVector2Array([
		marker_pos + Vector2(0, -d_size),
		marker_pos + Vector2(d_size, 0),
		marker_pos + Vector2(0, d_size),
		marker_pos + Vector2(-d_size, 0),
		marker_pos + Vector2(0, -d_size)
	]), Color(1.0, 0.9, 0.5, 0.9), 1.4)
