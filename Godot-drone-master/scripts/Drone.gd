extends RigidBody3D

const DroneBatteryManager = preload("res://scripts/drone/DroneBatteryManager.gd")
const DroneAerodynamics = preload("res://scripts/drone/DroneAerodynamics.gd")
const DronePropellerController = preload("res://scripts/drone/DronePropellerController.gd")

const THROTTLE_POWER = 210.0   
const FORWARD_POWER = 150.0    
const TURN_POWER = 20.0
const STABILIZE_FORCE = 45.0
const INPUT_SMOOTHING = 3.5
const HOVER_MIN_CLEARANCE = 2.0
const HOVER_HOLD_FORCE = 55.0
const HOVER_HOLD_DAMPING = 12.0
const HOVER_MAX_HOLD_FORCE = 90.0
const MAX_PITCH_DEGREES = 30.0
const MAX_TILT_DEGREES = 35.0

var smoothed_input = Vector4.ZERO
var hover_enabled = false
var speed_multiplier: float = 1.0
var turn_sensitivity_multiplier: float = 1.0
var custom_stabilize_force: float = 45.0

var wind_velocity: Vector3 = Vector3.ZERO
var wind_strength: float = 0.0
var wind_gust_factor: float = 0.25
var wind_state_name: String = "Normal"
var wind_phase: float = 0.0

const DroneAudioClass = preload("res://scripts/drone/DroneAudio.gd")

var low_cost_mode: bool = false
var low_detail_visuals: bool = false

var battery_manager: DroneBatteryManager
var aerodynamics: DroneAerodynamics
var propeller_controller: DronePropellerController
var audio_component: DroneAudio
@export var audio_enabled: bool = true
var telemetry_beep_timer: float = 0.0

var battery_percent: float:
	get: return battery_manager.battery_percent if battery_manager else 100.0
var battery_low_warning: bool:
	get: return battery_manager.battery_low_warning if battery_manager else false
var battery_critical: bool:
	get: return battery_manager.battery_critical if battery_manager else false
var battery_auto_landing: bool:
	get: return battery_manager.battery_auto_landing if battery_manager else false
var battery_failed: bool:
	get: return battery_manager.battery_failed if battery_manager else false
var battery_exhausted: bool:
	get: return battery_manager.battery_exhausted_flag if battery_manager else false
var battery_recharging: bool:
	get: return battery_manager.battery_recharging if battery_manager else false
	set(val):
		if battery_manager: battery_manager.battery_recharging = val

var propeller_datas: Array[Dictionary] = []
@onready var design = $Design
@onready var collision_shape: CollisionShape3D = $Collision
var drone_model: Node3D
var propellers: Array[Node3D] = []
var show_rig: DroneShowLightRig
const CAMERA_COLLISION_LAYER := 1 << 31

func _init() -> void:
	battery_manager = DroneBatteryManager.new()
	aerodynamics = DroneAerodynamics.new()
	propeller_controller = DronePropellerController.new()

func set_hover_mode(enabled: bool) -> void:
	hover_enabled = enabled
	linear_damp = 2.0
	angular_damp = 8.0

func apply_hover_mode() -> void:
	set_hover_mode(hover_enabled)

func set_swarm_mode_active(active: bool):
	if is_instance_valid(design):
		design.visible = !active
	if is_instance_valid(show_rig):
		show_rig.visible = true
		show_rig.set_show_lighting_enabled(false)

func set_low_cost_mode(enabled: bool) -> void:
	low_cost_mode = enabled
	if is_instance_valid(show_rig):
		show_rig.set_low_cost_mode(enabled)
		show_rig.visible = true
		show_rig.set_show_lighting_enabled(false)
	if is_instance_valid(design) and speed_multiplier <= 1.0:
		design.visible = true

func set_low_detail_visuals(enabled: bool) -> void:
	low_detail_visuals = enabled
	if enabled:
		contact_monitor = false
		max_contacts_reported = 0
		set_process(false)
		set_physics_process(false)
	else:
		set_process(true)
		set_physics_process(true)

	audio_enabled = not enabled
	if is_instance_valid(audio_component):
		audio_component.set_audio_enabled(audio_enabled)

	if is_instance_valid(design):
		design.visible = not enabled
	if is_instance_valid(show_rig):
		show_rig.visible = true

	_disable_shadow_casting_recursive(self)

func set_audio_enabled(enabled: bool) -> void:
	audio_enabled = enabled
	if is_instance_valid(audio_component):
		audio_component.set_audio_enabled(enabled)

func set_first_person(is_fp: bool) -> void:
	if is_instance_valid(audio_component) and audio_component.has_method("set_first_person"):
		audio_component.set_first_person(is_fp)

static func _disable_shadow_casting_recursive(node: Node) -> void:
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_shadow_casting_recursive(child)

func set_show_lighting_enabled(enabled: bool) -> void:
	if is_instance_valid(show_rig):
		show_rig.set_show_lighting_enabled(enabled)

func _ready():
	add_to_group("drone_quality_targets")
	collision_layer = 1
	collision_mask = 0xFFFFFFFF & ~CAMERA_COLLISION_LAYER
	mass = 5.0
	gravity_scale = 1.0
	linear_damp = 2.0
	angular_damp = 8.0

	process_mode = Node.PROCESS_MODE_PAUSABLE

	contact_monitor = true
	max_contacts_reported = 4
	if not body_entered.is_connected(_on_drone_collision):
		body_entered.connect(_on_drone_collision)

	if collision_shape:
		collision_shape.shape = BoxShape3D.new()
		collision_shape.shape.size = Vector3(1.2, 0.2, 1.2)
		collision_shape.transform = Transform3D.IDENTITY

	replace_drone_model()
	apply_hover_mode()
	audio_component = DroneAudio.new()
	audio_component.name = "Audio"
	add_child(audio_component)
	audio_component.initialize()
	audio_component.set_audio_enabled(audio_enabled)
	call_deferred("_connect_wind_manager")

func _connect_wind_manager() -> void:
	var scene := get_tree().current_scene if get_tree() else null
	if scene == null: return
	var wm: WindManager = null
	var direct := scene.get_node_or_null("WindManager")
	if direct is WindManager:
		wm = direct as WindManager
	if wm == null:
		for child in scene.get_children():
			if child is WindManager:
				wm = child as WindManager
				break
			var nested := child.find_child("WindManager", true, false)
			if nested is WindManager:
				wm = nested as WindManager
				break
	if wm and wm.has_signal("wind_changed") and not wm.wind_changed.is_connected(set_wind_profile):
		wm.wind_changed.connect(set_wind_profile)
		set_wind_profile(wm.wind_direction, wm.get_wind_strength(), wm.gust_factor, wm.get_state_name())

func set_wind_profile(dir: Vector3, strength: float, gust: float, state: String) -> void:
	wind_velocity = dir * strength
	wind_strength = strength
	wind_gust_factor = gust
	wind_state_name = state

func replace_drone_model():
	if low_detail_visuals:
		setup_show_lights()
		return

	if design == null: return

	for child in design.get_children():
		if not child is Camera3D and not child is XROrigin3D:
			if child == show_rig:
				show_rig = null
			child.queue_free()

	if not FileAccess.file_exists("res://assets/drone_model/scene.gltf"):
		push_error("Drone: scene.gltf NOT FOUND")
		return

	var model_scene: PackedScene = load("res://assets/drone_model/scene.gltf")
	if model_scene:
		drone_model = model_scene.instantiate()
		design.add_child(drone_model)
		design.visible = true

		var nodes_to_hide = ["Circle_16", "Fan_006_20"]
		for node_name in nodes_to_hide:
			var n = drone_model.find_child(node_name, true, false)
			if n: n.visible = false

		var model_aabb: AABB = _center_spline_model(drone_model)
		var max_dim: float = max(model_aabb.size.x, model_aabb.size.z)
		var target_scale := 1.3 / max_dim if max_dim > 0 else 1.0
		drone_model.scale = Vector3(target_scale, target_scale, target_scale)
		drone_model.rotation_degrees.y = 0

		var arm_positions: Array = [
			Vector3(-0.249101,  0.109929, -0.132448),
			Vector3( 0.249100,  0.109079, -0.132448),
			Vector3(-0.249101,  0.109079,  0.134621),
			Vector3( 0.226978,  0.109079,  0.134621),
		]

		var blade_mat := StandardMaterial3D.new()
		blade_mat.albedo_color = Color(0.08, 0.08, 0.08, 0.88)
		blade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		blade_mat.metallic = 0.15
		blade_mat.roughness = 0.55

		propellers.clear()
		propeller_datas.clear()

		var scene_root_node = drone_model.find_child("GLTF_SceneRootNode", true, false)
		var disc_parent: Node3D = scene_root_node if scene_root_node else drone_model

		for i in range(4):
			var holder := Node3D.new()
			holder.name = "PropDisc_%d" % i
			holder.position = arm_positions[i]
			disc_parent.add_child(holder)

			var disc := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius    = 0.1
			cyl.bottom_radius = 0.1
			cyl.height        = 0.005
			cyl.radial_segments = 20
			disc.mesh = cyl
			disc.material_override = blade_mat
			holder.add_child(disc)

			var b1 := MeshInstance3D.new()
			var b1m := BoxMesh.new()
			b1m.size = Vector3(0.185, 0.006, 0.032)
			b1.mesh = b1m
			b1.material_override = blade_mat
			holder.add_child(b1)

			var b2 := MeshInstance3D.new()
			var b2m := BoxMesh.new()
			b2m.size = Vector3(0.032, 0.006, 0.185)
			b2.mesh = b2m
			b2.material_override = blade_mat
			holder.add_child(b2)

			propellers.append(holder)
			propeller_datas.append({"node": holder, "original_transform": holder.transform})

		setup_show_lights()

func setup_show_lights():
	if is_instance_valid(show_rig):
		show_rig.queue_free()
		show_rig = null

	show_rig = preload("res://scripts/drone/DroneShowLightRig.gd").new()
	show_rig.name = "ShowLightRig"
	add_child(show_rig)

static func _safe_relative_transform(parent: Node3D, child: Node3D) -> Transform3D:
	if not parent or not child or parent == child:
		return Transform3D.IDENTITY
	var xform := Transform3D.IDENTITY
	var curr: Node = child
	while curr and curr != parent and curr is Node3D:
		xform = (curr as Node3D).transform * xform
		curr = curr.get_parent()
	return xform

func _center_spline_model(model: Node3D) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	_get_all_meshes(model, meshes)
	var aabb = AABB()
	var first = true
	for mesh in meshes:
		var mesh_transform = _safe_relative_transform(model, mesh)
		var mesh_aabb = mesh_transform * mesh.get_aabb()
		if first:
			aabb = mesh_aabb
			first = false
		else:
			aabb = aabb.merge(mesh_aabb)
	return aabb if not first else AABB()

func _get_all_meshes(node: Node, meshes: Array[MeshInstance3D]):
	if node is MeshInstance3D: meshes.append(node)
	for child in node.get_children(): _get_all_meshes(child, meshes)

func _physics_process(delta):
	if get_tree().paused: return
	if battery_exhausted:
		_apply_battery_lockout()
		return

	wind_phase += delta * (1.2 + wind_strength * 0.08)
	aerodynamics.advance_turbulence(delta, wind_strength)
	battery_manager.update_battery(delta, smoothed_input, hover_enabled)

	_apply_input_forces(delta, smoothed_input)
	if audio_enabled and audio_component:
		if audio_component.has_method("update_flight_audio"):
			audio_component.update_flight_audio(smoothed_input, linear_velocity, delta)
		else:
			audio_component.update_audio(smoothed_input.x)

		telemetry_beep_timer += delta
		if battery_low_warning or battery_critical:
			var interval = 0.6 if battery_critical else 1.6
			if telemetry_beep_timer >= interval:
				telemetry_beep_timer = 0.0
				if audio_component.has_method("play_telemetry_beep"):
					audio_component.play_telemetry_beep(battery_critical)

	if battery_auto_landing:
		smoothed_input.y = 0.0
		smoothed_input.z = 0.0
		smoothed_input.w = 0.0

func _apply_battery_lockout():
	smoothed_input = Vector4.ZERO
	linear_velocity = linear_velocity.lerp(Vector3.ZERO, 0.05)
	angular_velocity = angular_velocity.lerp(Vector3.ZERO, 0.05)

func _apply_input_forces(delta, input_vec: Vector4):
	var local_up = Vector3.UP if hover_enabled else global_transform.basis.y
	var forward_dir = -global_transform.basis.z
	var strafe_dir = global_transform.basis.x
	if hover_enabled:
		forward_dir.y = 0.0
		strafe_dir.y = 0.0
		if not forward_dir.is_zero_approx(): forward_dir = forward_dir.normalized()
		if not strafe_dir.is_zero_approx(): strafe_dir = strafe_dir.normalized()

	var vertical_thrust = local_up * input_vec.x * THROTTLE_POWER * speed_multiplier
	var forward_force = forward_dir * input_vec.z * FORWARD_POWER * speed_multiplier
	var strafe_force = strafe_dir * input_vec.w * FORWARD_POWER * speed_multiplier

	if hover_enabled:
		var anti_gravity = Vector3.UP * (mass * 9.8)
		apply_central_force(anti_gravity)
		if abs(input_vec.x) < 0.05:
			linear_velocity.y = lerpf(linear_velocity.y, 0.0, 0.25)

	var aero_res = aerodynamics.calculate_wind_forces(
		forward_dir, strafe_dir, wind_velocity, wind_strength, wind_gust_factor, wind_phase, hover_enabled
	)

	var wind_force: Vector3 = aero_res["wind_force"]
	var wind_bobble: Vector3 = aero_res["wind_bobble"]
	var wind_drag_factor: float = aero_res["wind_drag_factor"]

	forward_force *= wind_drag_factor
	strafe_force *= lerpf(wind_drag_factor, 1.0, 0.2)
	vertical_thrust += Vector3(0.0, wind_force.y * 0.08, 0.0)

	apply_central_force(vertical_thrust + forward_force + strafe_force + wind_force + wind_bobble)

	if hover_enabled:
		var space_state = get_world_3d().direct_space_state
		if space_state:
			var from = global_position + Vector3.UP * 0.1
			var to = global_position + Vector3.DOWN * 20.0
			var query = PhysicsRayQueryParameters3D.create(from, to)
			query.exclude = [get_rid()]
			var result = space_state.intersect_ray(query)
			if result.has("position"):
				var ground_distance = global_position.y - result.position.y
				if ground_distance < HOVER_MIN_CLEARANCE:
					var hover_force = (HOVER_MIN_CLEARANCE - ground_distance) * HOVER_HOLD_FORCE
					hover_force -= linear_velocity.y * HOVER_HOLD_DAMPING
					hover_force = clamp(hover_force, 0.0, HOVER_MAX_HOLD_FORCE)
					apply_central_force(Vector3.UP * hover_force)

	var effective_turn_power = TURN_POWER * speed_multiplier * turn_sensitivity_multiplier
	apply_torque(global_transform.basis.x * (-input_vec.z * effective_turn_power))
	apply_torque(global_transform.basis.z * (-input_vec.w * effective_turn_power))
	apply_torque(global_transform.basis.y * (-input_vec.y * effective_turn_power))

	apply_torque(global_transform.basis.z * float(aero_res["bank_tilt_torque"]))
	apply_torque(global_transform.basis.x * float(aero_res["pitch_tilt_torque"]))
	apply_torque(global_transform.basis.x * float(aero_res["tilt_x_torque"]))
	apply_torque(global_transform.basis.z * float(aero_res["tilt_z_torque"]))

	var up = global_transform.basis.y
	var correction = up.cross(Vector3.UP)
	var current_stabilize = custom_stabilize_force
	if abs(input_vec.z) < 0.05 and abs(input_vec.w) < 0.05:
		current_stabilize = custom_stabilize_force * 3.0
	apply_torque(correction * current_stabilize)

	var current_pitch = rad_to_deg(get_rotation().x)
	var current_tilt = max(abs(rad_to_deg(get_rotation().z)), abs(rad_to_deg(get_rotation().x)))
	if abs(current_pitch) > MAX_PITCH_DEGREES:
		var pitch_correction = clamp(-current_pitch * 0.05, -1.0, 1.0)
		apply_torque(global_transform.basis.x * pitch_correction * TURN_POWER * speed_multiplier)
	if current_tilt > MAX_TILT_DEGREES:
		var tilt_error = current_tilt - MAX_TILT_DEGREES
		var tilt_correction = clamp(tilt_error * 0.05, 0.0, 1.0)
		apply_torque(global_transform.basis.z * tilt_correction * TURN_POWER * speed_multiplier)

	var legacy_props = design.get_node_or_null("Props") if design else null
	propeller_controller.update_propellers(delta, input_vec.x, propeller_datas, legacy_props)

func set_input_vector(input_vec: Vector4) -> void:
	if battery_exhausted:
		smoothed_input = Vector4.ZERO
		return
	smoothed_input = input_vec

func get_battery_percent() -> float:
	return battery_manager.battery_percent

func is_battery_low_warning() -> bool:
	return battery_manager.battery_low_warning

func is_battery_critical() -> bool:
	return battery_manager.battery_critical

func is_battery_auto_landing() -> bool:
	return battery_manager.battery_auto_landing

func is_battery_empty() -> bool:
	return battery_manager.battery_failed

func is_battery_recharging() -> bool:
	return battery_manager.battery_recharging

func start_battery_recharge() -> void:
	if battery_manager:
		battery_manager.battery_recharging = true

func stop_battery_recharge() -> void:
	if battery_manager:
		battery_manager.battery_recharging = false

func set_infinite_battery_enabled(enabled: bool) -> void:
	if battery_manager:
		battery_manager.set_infinite_battery(enabled)

static func detect_surface_type(body: Node) -> int:
	if not body or not is_instance_valid(body):
		return 0 # CONCRETE
	
	var name_lower = body.name.to_lower()
	var path_lower = body.get_path().get_concatenated_subnames().to_lower() if body.is_inside_tree() else ""
	var parent_name = body.get_parent().name.to_lower() if body.get_parent() else ""
	var combined = name_lower + " " + path_lower + " " + parent_name

	if body.get("material") and body.material:
		combined += " " + (body.material.resource_name.to_lower() if body.material.resource_name else "")
	if body.get("material_override") and body.material_override:
		combined += " " + (body.material_override.resource_name.to_lower() if body.material_override.resource_name else "")

	if "tarp" in combined or "canopy" in combined or "canvas" in combined or "awning" in combined or "fabric" in combined:
		return 4 # TARP / CANVAS
	elif "tree" in combined or "wood" in combined or "leaf" in combined or "branch" in combined or "foliage" in combined or "pine" in combined or "bush" in combined:
		return 1 # TREE
	elif "grass" in combined or "dirt" in combined or "terrain" in combined or "ground" in combined or "lawn" in combined or "mud" in combined or "earth" in combined or "fallbackfloor" in combined:
		return 2 # GRASS
	elif "metal" in combined or "steel" in combined or "pipe" in combined or "pole" in combined or "fence" in combined or "iron" in combined:
		return 3 # METAL
	
	return 0 # CONCRETE (buildings, roofs, walls, asphalt, structures)

func _on_drone_collision(body: Node) -> void:
	if not audio_enabled or not audio_component:
		return

	var impact = linear_velocity.length()
	if is_nan(impact) or is_inf(impact):
		linear_velocity = Vector3.ZERO
		impact = 0.0

	# Always ensure forceful landings and roof/tarp strikes produce solid audio!
	impact = maxf(impact, 0.45)

	var surface_type = detect_surface_type(body)
	var hit_zone = 3 # BODY_SIDE default

	var local_cpos = Vector3.ZERO
	var contact_normal = Vector3.UP
	var state = PhysicsServer3D.body_get_direct_state(get_rid())
	if state and state.get_contact_count() > 0:
		local_cpos = state.get_contact_local_position(0)
		contact_normal = state.get_contact_local_normal(0)

	var is_blade_hit = Vector2(local_cpos.x, local_cpos.z).length() > 0.12

	if is_blade_hit:
		hit_zone = 0 # PROPELLER
	elif local_cpos.y > 0.04 or (linear_velocity.y > 1.2 and contact_normal.y < -0.3):
		hit_zone = 1 # TOP
	elif local_cpos.y < -0.04 or (linear_velocity.y < -1.2 and contact_normal.y > 0.3):
		hit_zone = 2 # BELLY / LANDING
	else:
		hit_zone = 3 # BODY_SIDE

	if audio_component.has_method("play_surface_impact"):
		audio_component.play_surface_impact(impact, surface_type, hit_zone)
	elif audio_component.has_method("play_crash"):
		audio_component.play_crash(impact)
