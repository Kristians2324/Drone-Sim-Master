extends CanvasLayer

@onready var dimmer: ColorRect = $Dimmer
@onready var spinner_rect: TextureRect = $Center/Layout/SpinnerRect
@onready var status_label: Label = $Center/Layout/StatusLabel

var is_loading: bool = false
var rotation_speed: float = 4.5

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_logo()
	_update_pivot()

func _setup_logo() -> void:
	if not spinner_rect:
		return
	if ResourceLoader.exists("res://assets/textures/drone_logo.png.import"):
		var custom_tex = load("res://assets/textures/drone_logo.png")
		if custom_tex is Texture2D:
			spinner_rect.texture = custom_tex
			return
	if ResourceLoader.exists("res://icon.png.import"):
		var fallback_tex = load("res://icon.png")
		if fallback_tex is Texture2D:
			spinner_rect.texture = fallback_tex

func _update_pivot() -> void:
	if spinner_rect:
		spinner_rect.pivot_offset = spinner_rect.size / 2.0

func _process(delta: float) -> void:
	if visible and spinner_rect:
		spinner_rect.rotation += delta * rotation_speed

func show_loading(message: String = "Loading Simulation...") -> void:
	show()
	is_loading = true
	if status_label:
		status_label.text = message
	if dimmer:
		dimmer.color.a = 0.92
	if spinner_rect:
		spinner_rect.modulate.a = 1.0
		spinner_rect.rotation = 0.0
		_update_pivot()

func hide_loading() -> void:
	if not is_loading:
		return
	is_loading = false
	
	if not is_inside_tree():
		hide()
		return
		
	var fade_tween = create_tween()
	fade_tween.set_parallel(true)
	if dimmer:
		fade_tween.tween_property(dimmer, "color:a", 0.0, 0.35)
	if spinner_rect:
		fade_tween.tween_property(spinner_rect, "modulate:a", 0.0, 0.35)
	if status_label:
		fade_tween.tween_property(status_label, "modulate:a", 0.0, 0.35)
		
	await fade_tween.finished
	hide()
