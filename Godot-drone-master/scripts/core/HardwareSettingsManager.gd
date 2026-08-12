extends Node
class_name HardwareSettingsManager

enum QualityTier { LOW, MEDIUM, ULTRA }

var current_tier: QualityTier = QualityTier.ULTRA
var detected_cpu: String = ""
var detected_gpu: String = ""
var thread_count: int = 4

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	auto_detect_and_apply()

func auto_detect_and_apply() -> void:
	if DisplayServer.get_name() == "headless":
		return

	detected_cpu = OS.get_processor_name()
	detected_gpu = RenderingServer.get_video_adapter_name()
	thread_count = OS.get_processor_count()

	var gpu_lower := detected_gpu.to_lower()

	var is_integrated := (
		gpu_lower.contains("intel") or
		gpu_lower.contains("uhd") or
		gpu_lower.contains("iris") or
		gpu_lower.contains("graphics 6") or
		gpu_lower.contains("vega") or
		gpu_lower.contains("mali") or
		gpu_lower.contains("adreno") or
		thread_count <= 4
	)

	var is_midtier := (
		gpu_lower.contains("gtx 1050") or
		gpu_lower.contains("gtx 1060") or
		gpu_lower.contains("gtx 1650") or
		gpu_lower.contains("gtx 1660") or
		gpu_lower.contains("rtx 3050") or
		gpu_lower.contains("rx 570") or
		gpu_lower.contains("rx 580")
	)

	if is_integrated:
		current_tier = QualityTier.LOW
	elif is_midtier:
		current_tier = QualityTier.MEDIUM
	else:
		current_tier = QualityTier.ULTRA

	apply_quality_preset(current_tier)

func apply_quality_preset(tier: QualityTier) -> void:
	current_tier = tier
	var vp := get_viewport()
	var rs := RenderingServer

	# Apply shadow max distance & 4-split PSSM on Directional Lights
	var scene = get_tree().current_scene if get_tree() else null
	if scene:
		var sun = scene.find_child("DirectionalLight3D", true, false) as DirectionalLight3D
		if sun:
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_split_1 = 0.08
			sun.directional_shadow_split_2 = 0.22
			sun.directional_shadow_split_3 = 0.55
			match tier:
				QualityTier.LOW:
					sun.directional_shadow_max_distance = 400.0
				QualityTier.MEDIUM:
					sun.directional_shadow_max_distance = 800.0
				QualityTier.ULTRA:
					sun.directional_shadow_max_distance = 1500.0

	match tier:
		QualityTier.LOW:
			print("HardwareSettingsManager: Auto-configured LOW graphics preset (%s / %s)." % [detected_cpu, detected_gpu])
			if vp:
				vp.msaa_3d = Viewport.MSAA_DISABLED
				vp.use_debanding = false
				vp.scaling_3d_scale = 0.90
			rs.directional_shadow_atlas_set_size(2048, true)
			rs.positional_soft_shadow_filter_set_quality(rs.SHADOW_QUALITY_HARD)
			rs.directional_soft_shadow_filter_set_quality(rs.SHADOW_QUALITY_HARD)

		QualityTier.MEDIUM:
			print("HardwareSettingsManager: Auto-configured MEDIUM graphics preset (%s / %s)." % [detected_cpu, detected_gpu])
			if vp:
				vp.msaa_3d = Viewport.MSAA_2X
				vp.use_debanding = true
				vp.scaling_3d_scale = 1.0
			rs.directional_shadow_atlas_set_size(4096, true)
			rs.positional_soft_shadow_filter_set_quality(rs.SHADOW_QUALITY_SOFT_MEDIUM)
			rs.directional_soft_shadow_filter_set_quality(rs.SHADOW_QUALITY_SOFT_MEDIUM)

		QualityTier.ULTRA:
			print("HardwareSettingsManager: Auto-configured ULTRA graphics preset (%s / %s)." % [detected_cpu, detected_gpu])
			if vp:
				vp.msaa_3d = Viewport.MSAA_4X
				vp.use_debanding = true
				vp.scaling_3d_scale = 1.0
			rs.directional_shadow_atlas_set_size(4096, true)
			rs.positional_soft_shadow_filter_set_quality(rs.SHADOW_QUALITY_SOFT_ULTRA)
			rs.directional_soft_shadow_filter_set_quality(rs.SHADOW_QUALITY_SOFT_ULTRA)

func get_quality_tier_name() -> String:
	match current_tier:
		QualityTier.LOW: return "LOW (Integrated / Laptop)"
		QualityTier.MEDIUM: return "MEDIUM (Balanced)"
		QualityTier.ULTRA: return "ULTRA (High-End GPU)"
		_: return "CUSTOM"
