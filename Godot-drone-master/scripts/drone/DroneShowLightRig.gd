extends Node3D
class_name DroneShowLightRig

var drone_index: int = 0
var drone_total: int = 1
var is_player_drone: bool = false

var show_time: float = 0.0
var phase_offset: float = 0.0

var palette_core: Color = Color.CYAN
var palette_secondary: Color = Color.MAGENTA
var palette_highlight: Color = Color.WHITE
var palette_body: Color = Color(0.1, 0.1, 0.14)

var halo_light: OmniLight3D
var down_light: SpotLight3D
var halo_mesh: MeshInstance3D
var halo_material: StandardMaterial3D
var visuals_enabled: bool = true
var light_update_interval: float = 0.0
var light_update_timer: float = 0.0
var _last_visuals_enabled: bool = true
var _low_cost_cached: bool = false
var _saved_visual_state: bool = true
var _show_lighting_enabled: bool = false

func _ready():
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(true)
	_build_rig()
	_rebuild_palette()
	_apply_palette_to_visuals()

func set_visuals_enabled(enabled: bool) -> void:
	visuals_enabled = enabled
	_last_visuals_enabled = enabled
	_saved_visual_state = enabled
	_apply_light_output_state()

func set_color_all(color: Color) -> void:
	palette_core = color
	palette_secondary = color.lerp(Color.WHITE, 0.3)
	palette_highlight = color.lerp(Color.WHITE, 0.6)
	palette_body = color.darkened(0.5)
	_apply_palette_to_visuals()

func configure(index: int, total: int, player_drone: bool = false):
	drone_index = max(index, 0)
	drone_total = max(total, 1)
	is_player_drone = player_drone
	_rebuild_palette()
	_apply_palette_to_visuals()

func get_palette() -> Dictionary:
	return {
		"core": palette_core,
		"secondary": palette_secondary,
		"highlight": palette_highlight,
		"body": palette_body,
	}

func _build_rig():
	if halo_light != null:
		return

	halo_light = OmniLight3D.new()
	halo_light.name = "UnderglowLight"
	halo_light.omni_range = 14.0
	halo_light.omni_attenuation = 1.0
	halo_light.light_energy = 5.5
	halo_light.shadow_enabled = false
	halo_light.visible = false
	add_child(halo_light)

	down_light = SpotLight3D.new()
	down_light.name = "UnderglowSpot"
	down_light.position = Vector3(0.0, -0.05, 0.0)
	down_light.rotation_degrees.x = -90.0
	down_light.spot_angle = 65.0
	down_light.spot_attenuation = 0.95
	down_light.light_energy = 6.0
	down_light.shadow_enabled = false
	down_light.visible = false
	add_child(down_light)

	halo_mesh = MeshInstance3D.new()
	halo_mesh.name = "UnderglowSphere"
	var sphere = SphereMesh.new()
	sphere.radius = 0.38
	sphere.height = 0.76
	sphere.radial_segments = 16
	sphere.rings = 12
	halo_mesh.mesh = sphere
	halo_mesh.position = Vector3(0.0, -0.05, 0.0)
	halo_mesh.visible = false
	add_child(halo_mesh)

	halo_material = StandardMaterial3D.new()
	halo_material.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	halo_material.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	halo_material.albedo_color = Color(1, 1, 1, 0.96)
	halo_material.emission_enabled = true
	halo_material.emission = Color.WHITE
	halo_material.emission_energy_multiplier = 10.0
	halo_mesh.material_override = halo_material

func _rebuild_palette():
	var count: int = int(drone_total)
	if count < 1:
		count = 1

	phase_offset = float(drone_index) * (TAU / float(count))

	var color_options = [
		Color(0.2, 0.85, 1.0),  # Cyan
		Color(0.1, 0.9, 0.3),   # Emerald Green
		Color(1.0, 0.6, 0.1),   # Amber
		Color(0.95, 0.2, 0.8),  # Magenta
		Color(1.0, 0.9, 0.2),   # Bright Yellow
		Color(0.3, 0.5, 1.0)    # Deep Blue
	]

	var palette_idx = drone_index % color_options.size()
	palette_core = color_options[palette_idx]
	palette_secondary = color_options[(palette_idx + 1) % color_options.size()]
	palette_highlight = Color.WHITE
	palette_body = palette_core.darkened(0.6)

func _apply_palette_to_visuals():
	if halo_light == null or halo_material == null:
		return

	var base_color: Color = palette_core.lerp(palette_secondary, 0.35)
	halo_light.light_color = base_color
	if down_light:
		down_light.light_color = base_color.lerp(Color.WHITE, 0.15)
	halo_material.albedo_color = Color(base_color.r, base_color.g, base_color.b, 0.98)
	halo_material.emission = base_color
	halo_material.emission_energy_multiplier = 10.0
	_apply_light_output_state()

func _process(delta: float):
	if not visuals_enabled or not _show_lighting_enabled:
		return

	show_time += delta
	light_update_timer += delta
	if light_update_interval > 0.0 and light_update_timer < light_update_interval:
		return
	light_update_timer = 0.0

	var slow_wave: float = 0.5 + 0.5 * sin(show_time * 2.8 + phase_offset)
	var fast_wave: float = 0.5 + 0.5 * sin(show_time * 5.5 + phase_offset * 1.8)

	var color: Color = palette_core.lerp(palette_secondary, slow_wave)
	color = color.lerp(palette_highlight, fast_wave * 0.45)

	if halo_light:
		halo_light.light_color = color
		halo_light.light_energy = 4.0 + slow_wave * 1.5
	if down_light:
		down_light.light_color = color.lerp(Color.WHITE, 0.12)
		down_light.light_energy = 4.5 + slow_wave * 1.5

	if halo_material:
		halo_material.albedo_color = Color(color.r, color.g, color.b, 0.98)
		halo_material.emission = color
		halo_material.emission_energy_multiplier = 10.0 + fast_wave * 3.0

func set_low_cost_mode(enabled: bool) -> void:
	_low_cost_cached = enabled
	light_update_interval = 0.15 if enabled else 0.0
	_apply_light_output_state()

func set_high_performance_mode(enabled: bool) -> void:
	light_update_interval = 0.0 if enabled else light_update_interval

func set_show_lighting_enabled(enabled: bool) -> void:
	_show_lighting_enabled = enabled
	_apply_light_output_state()

func _apply_light_output_state() -> void:
	var active = _show_lighting_enabled and visuals_enabled
	var use_dynamic_lights = active and not _low_cost_cached
	if halo_light:
		halo_light.visible = use_dynamic_lights
		halo_light.light_energy = 4.0 if use_dynamic_lights else 0.0
	if down_light:
		down_light.visible = use_dynamic_lights
		down_light.light_energy = 4.5 if use_dynamic_lights else 0.0
	if halo_mesh:
		halo_mesh.visible = active
	if halo_material:
		halo_material.emission_energy_multiplier = 10.0 if active else 0.0
