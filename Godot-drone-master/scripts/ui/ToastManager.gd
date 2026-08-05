extends CanvasLayer

## Global Toast Notification Manager
## Provides clean, professional top-right HUD notifications for user actions.

static var instance: Node = null

var container: VBoxContainer
var toast_queue: Array = []

func _init() -> void:
	instance = self

func _ready() -> void:
	layer = 150
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_container()

func _setup_container() -> void:
	if container: return
	
	var margin = MarginContainer.new()
	margin.name = "ToastMargin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	container = VBoxContainer.new()
	container.name = "ToastContainer"
	container.size_flags_horizontal = Control.SIZE_SHRINK_END
	container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	container.add_theme_constant_override("separation", 8)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(container)

static func notify(message: String, duration: float = 2.5) -> void:
	if instance and instance.has_method("show_toast"):
		instance.show_toast(message, duration)

func show_toast(message: String, duration: float = 2.5) -> void:
	if not is_inside_tree() or message.strip_edges() == "": return
	_setup_container()

	var panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.11, 0.16, 0.88)
	style.border_width_left = 3
	style.border_color = Color(0.25, 0.55, 0.95, 0.9)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 14
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	var label = Label.new()
	label.text = message.to_upper()
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.92, 0.95, 0.98))
	panel.add_child(label)

	container.add_child(panel)

	# Entrance & Exit Animation
	panel.modulate.a = 0.0
	panel.position.x += 40.0

	var tween = create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "position:x", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(duration).timeout
	if is_instance_valid(panel) and panel.is_inside_tree():
		var fade_tween = create_tween().set_parallel(true)
		fade_tween.tween_property(panel, "modulate:a", 0.0, 0.25)
		fade_tween.tween_property(panel, "position:x", 30.0, 0.25)
		await fade_tween.finished
		if is_instance_valid(panel):
			panel.queue_free()
