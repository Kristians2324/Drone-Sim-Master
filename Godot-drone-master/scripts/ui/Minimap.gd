extends CanvasLayer
## Circular WindCompass-style radar minimap with forward direction arrow,
## cardinal direction ticks, dark glass paneling, and landmark markers.

const RADAR_RADIUS: float = 92.0
const ARROW_LEN: float = 26.0
const PANEL_MARGIN: float = 18.0

@onready var sub_viewport: SubViewport = $Margin/ViewportContainer/SubViewport
@onready var map_camera: Camera3D = $Margin/ViewportContainer/SubViewport/MapCamera
@onready var viewport_container: SubViewportContainer = $Margin/ViewportContainer

var _canvas: Control
var target_drone: Node3D = null
var tower_position: Vector3 = Vector3(350.0, 0.0, 350.0)
var _smooth_heading: float = 0.0

func _ready() -> void:
	layer = 120
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)
	
	if sub_viewport:
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

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
		map_camera.global_position = Vector3(drone_pos.x, drone_pos.y + 200.0, drone_pos.z)
	
	# Smoothly interpolate 2D yaw heading for minimap arrow
	var target_heading: float = -target_drone.global_rotation.y
	var diff := fmod(target_heading - _smooth_heading + PI * 3.0, TAU) - PI
	_smooth_heading += diff * delta * 12.0

func _on_draw() -> void:
	var center := Vector2(PANEL_MARGIN + RADAR_RADIUS + 8.0, PANEL_MARGIN + RADAR_RADIUS + 8.0)
	
	_draw_backing(center)
	_draw_compass_ring(center)
	_draw_cardinal_labels(center)
	_draw_tower_marker(center)
	_draw_forward_direction_arrow(center)
	_draw_badge_label(center)

# ── WindCompass dark glass backing ──────────────────────────────────────────
func _draw_backing(center: Vector2) -> void:
	# Soft outer shadow
	_canvas.draw_circle(center, RADAR_RADIUS + 6.0, Color(0.0, 0.0, 0.0, 0.35))
	# Dark glass outer ring border
	_canvas.draw_circle(center, RADAR_RADIUS + 2.0, Color(0.2, 0.65, 0.95, 0.7))
	# Dark glass inner background
	_canvas.draw_circle(center, RADAR_RADIUS, Color(0.03, 0.06, 0.10, 0.78))

# ── WindCompass outer glowing ring and tick marks ───────────────────────────
func _draw_compass_ring(center: Vector2) -> void:
	# Glowing cyan outer ring
	_draw_thick_circle_arc(center, RADAR_RADIUS - 1.0, Color(0.2, 0.85, 1.0, 0.9), 2.0)
	
	# Tick marks every 45°
	for i in range(8):
		var angle := (PI / 4.0) * float(i)
		var inner := RADAR_RADIUS - (10.0 if i % 2 == 0 else 5.0)
		var p0 := center + Vector2(cos(angle), sin(angle)) * inner
		var p1 := center + Vector2(cos(angle), sin(angle)) * (RADAR_RADIUS - 1.0)
		var col := Color(0.7, 0.9, 1.0, 0.8) if i % 2 == 0 else Color(0.5, 0.7, 0.9, 0.45)
		_canvas.draw_line(p0, p1, col, 1.5)

# ── Cardinal direction labels (N, E, S, W) ──────────────────────────────────
func _draw_cardinal_labels(center: Vector2) -> void:
	var cardinals := {
		"N": -PI * 0.5,
		"E": 0.0,
		"S": PI * 0.5,
		"W": PI,
	}
	var label_r := RADAR_RADIUS - 18.0
	for label in cardinals:
		var a: float = cardinals[label]
		var pt := center + Vector2(cos(a), sin(a)) * label_r - Vector2(5.0, 6.0)
		var col := Color(0.95, 0.97, 1.0, 0.9) if label != "N" else Color(1.0, 0.35, 0.35, 1.0)
		_canvas.draw_string(ThemeDB.fallback_font, pt, label, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, col)

# ── Prominent Forward Direction Arrow ───────────────────────────────────────
func _draw_forward_direction_arrow(center: Vector2) -> void:
	var angle := _smooth_heading - PI * 0.5 # Top = 0° forward heading
	var dir := Vector2(cos(angle), sin(angle))
	var perp := Vector2(-dir.y, dir.x)

	var tip := center + dir * ARROW_LEN
	var base := center - dir * (ARROW_LEN * 0.4)

	# Forward sight ray line extending in front of player
	var sight_tip := center + dir * (RADAR_RADIUS - 12.0)
	_canvas.draw_line(center, sight_tip, Color(0.2, 0.85, 1.0, 0.35), 1.2, true)

	# Main arrow shaft
	_canvas.draw_line(base, tip, Color(1.0, 1.0, 1.0, 0.8), 2.5, true)

	# Large distinct arrowhead
	var head_back := tip - dir * 14.0
	var h_left := head_back + perp * 8.0
	var h_right := head_back - perp * 8.0

	var arrow_col := Color(0.2, 0.85, 1.0, 1.0) # Bright neon cyan
	var pts := PackedVector2Array([tip, h_left, h_right])
	_canvas.draw_colored_polygon(pts, arrow_col)
	_canvas.draw_polyline(PackedVector2Array([h_left, tip, h_right]), Color(1.0, 1.0, 1.0, 0.9), 1.5, true)

	# Center player dot
	_canvas.draw_circle(center, 4.0, Color(1.0, 0.85, 0.2, 1.0)) # Golden center hub
	_canvas.draw_arc(center, 4.0, 0.0, TAU, 16, Color(1.0, 1.0, 1.0, 0.9), 1.2)

# ── Recharge Tower Indicator ────────────────────────────────────────────────
func _draw_tower_marker(center: Vector2) -> void:
	if not target_drone or not is_instance_valid(target_drone) or not map_camera:
		return
		
	var drone_pos = target_drone.global_position
	var diff_x: float = tower_position.x - drone_pos.x
	var diff_z: float = tower_position.z - drone_pos.z
	
	var map_span: float = map_camera.size
	var rel_x: float = (diff_x / map_span) * (RADAR_RADIUS * 2.0)
	var rel_y: float = (diff_z / map_span) * (RADAR_RADIUS * 2.0)
	
	var offset_2d := Vector2(rel_x, rel_y)
	var dist := offset_2d.length()
	
	# Clamp to radar outer perimeter if tower is outside view
	var max_dist := RADAR_RADIUS - 16.0
	if dist > max_dist:
		offset_2d = offset_2d.normalized() * max_dist
		
	var marker_pos := center + offset_2d
	
	# Draw glowing orange diamond icon for Recharge Tower
	var d_size := 6.0
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
	]), Color(1.0, 0.9, 0.5, 0.9), 1.2)

# ── Radar Badge Label ────────────────────────────────────────────────────────
func _draw_badge_label(center: Vector2) -> void:
	var label_pos := center + Vector2(-22.0, RADAR_RADIUS + 12.0)
	_canvas.draw_string(ThemeDB.fallback_font, label_pos + Vector2(1, 1), "RADAR HUD",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.0, 0.0, 0.0, 0.7))
	_canvas.draw_string(ThemeDB.fallback_font, label_pos, "RADAR HUD",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.2, 0.85, 1.0, 0.9))

func _draw_thick_circle_arc(center: Vector2, radius: float, color: Color, width: float) -> void:
	var steps: int = 48
	var prev := center + Vector2(radius, 0)
	for i in range(1, steps + 1):
		var a := (TAU * float(i)) / float(steps)
		var pt := center + Vector2(cos(a), sin(a)) * radius
		_canvas.draw_line(prev, pt, color, width, true)
		prev = pt
