extends CanvasLayer

@onready var dimmer: ColorRect = $Dimmer
@onready var spinner_rect: TextureRect = $Center/Layout/SpinnerRect
@onready var status_label: Label = $Center/Layout/StatusLabel
@onready var progress_bar: ProgressBar = $Center/Layout/ProgressBar

var is_loading: bool = false
var rotation_speed: float = 5.0
var progress_tween: Tween
var fade_tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_logo()
	_update_pivot()

func _setup_logo() -> void:
	if not spinner_rect:
		return
	var logo_path = "res://assets/textures/drone_logo.png" if FileAccess.file_exists("res://assets/textures/drone_logo.png") else "res://icon.png"
	if ResourceLoader.has_cached(logo_path):
		var cached_tex = ResourceLoader.load(logo_path)
		if cached_tex is Texture2D:
			spinner_rect.texture = cached_tex
			return
	if FileAccess.file_exists(logo_path):
		var img = Image.load_from_file(logo_path)
		if img and not img.is_empty():
			spinner_rect.texture = ImageTexture.create_from_image(img)

func _update_pivot() -> void:
	if spinner_rect:
		spinner_rect.pivot_offset = spinner_rect.size / 2.0

func _process(delta: float) -> void:
	if visible and spinner_rect:
		spinner_rect.rotation += delta * rotation_speed

func show_loading(message: String = "Loading Environment...") -> void:
	show()
	is_loading = true
	
	if fade_tween and fade_tween.is_running():
		fade_tween.kill()
	if progress_tween and progress_tween.is_running():
		progress_tween.kill()

	# Explicitly restore opacity of ALL UI components
	if dimmer:
		dimmer.color.a = 0.96
	if spinner_rect:
		spinner_rect.modulate.a = 1.0
		spinner_rect.rotation = 0.0
		_update_pivot()
	if status_label:
		status_label.modulate.a = 1.0
		status_label.text = message
	if progress_bar:
		progress_bar.modulate.a = 1.0
		progress_bar.value = 10.0
		progress_tween = create_tween()
		progress_tween.tween_property(progress_bar, "value", 85.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func hide_loading() -> void:
	if not is_loading:
		return
	is_loading = false
	
	if not is_inside_tree():
		hide()
		return

	if progress_tween and progress_tween.is_running():
		progress_tween.kill()

	if progress_bar:
		progress_bar.value = 100.0

	fade_tween = create_tween().set_parallel(true)
	if dimmer:
		fade_tween.tween_property(dimmer, "color:a", 0.0, 0.25)
	if spinner_rect:
		fade_tween.tween_property(spinner_rect, "modulate:a", 0.0, 0.25)
	if status_label:
		fade_tween.tween_property(status_label, "modulate:a", 0.0, 0.25)
	if progress_bar:
		fade_tween.tween_property(progress_bar, "modulate:a", 0.0, 0.25)
		
	await fade_tween.finished
	hide()
