extends Node3D

const DroneTricksController = preload("res://scripts/drone/DroneTricksController.gd")
const DroneAutopilotController = preload("res://scripts/drone/DroneAutopilotController.gd")
const DroneShowModeController = preload("res://scripts/drone/DroneShowModeController.gd")

@export var drone_scene: PackedScene = preload("res://scenes/Drone.tscn")
@export var use_mavlink_bridge: bool = false
@export var mavlink_listen_port: int = 14550
@export var mavlink_remote_host: String = "127.0.0.1"
@export var mavlink_remote_port: int = 14551
var drone: RigidBody3D = null
var drone_input = null
var mavlink_bridge: MavlinkBridge = null

var swarm_controller = null
var swarm_mode: bool = false

var is_first_person: bool = true
var camera_toggle_cooldown: float = 0.0
var state_toggle_cooldown: float = 0.0

var spring_arm: SpringArm3D
var tp_camera: Camera3D
var fp_camera: Camera3D
var show_camera_rig: Node3D
var show_camera: Camera3D
var show_camera_active: bool = false
var show_camera_mode: int = 0
var show_camera_timer: float = 0.0
var show_camera_switch_interval: float = 3.5
var show_camera_presets: Array[Vector3] = [
	Vector3(0, -22, 10),
	Vector3(0, 58, 0.1),
	Vector3(0, 5, 48),
	Vector3(48, 16, 20),
	Vector3(-48, 16, -20),
	Vector3(32, 42, 32),
	Vector3(-32, 10, 38),
	Vector3(18, -14, 30),
]
var launch_pad: StaticBody3D = null
var launch_pad_mesh: MeshInstance3D = null
var launch_pad_marker: MeshInstance3D = null
var recharge_structure: Node3D = null
var low_battery_return_active: bool = false
var low_battery_landing_active: bool = false

enum FlightState { MANUAL, AUTOPILOT, TRICK_LOOP, TRICK_BARREL }
var flight_state = FlightState.MANUAL

enum ShowMode { NONE, STAR_FORMATION, CIRCLE, HEART, DIAMOND, WAVE }
var show_mode = ShowMode.NONE
var show_controller: Node3D = null

var show_mode_names: Dictionary = {
	"star": ShowMode.STAR_FORMATION,
	"circle": ShowMode.CIRCLE,
	"heart": ShowMode.HEART,
	"diamond": ShowMode.DIAMOND,
	"wave": ShowMode.WAVE,
}

var tricks_controller: DroneTricksController
var autopilot_controller: DroneAutopilotController
var show_mode_controller: DroneShowModeController

var show_target_positions: Array[Vector3]:
	get: return show_mode_controller.show_target_positions if show_mode_controller else []
var show_center: Vector3:
	get: return show_mode_controller.show_center if show_mode_controller else Vector3.ZERO
var post_trick_state = FlightState.MANUAL

func _init() -> void:
	tricks_controller = DroneTricksController.new()
	autopilot_controller = DroneAutopilotController.new()
	show_mode_controller = DroneShowModeController.new()

func _ready():
	spring_arm = SpringArm3D.new()
	spring_arm.spring_length = 4.0
	add_child(spring_arm)

	tp_camera = Camera3D.new()
	spring_arm.add_child(tp_camera)

	fp_camera = Camera3D.new()
	add_child(fp_camera)

	show_camera_rig = Node3D.new()
	show_camera_rig.name = "ShowCameraRig"
	add_child(show_camera_rig)

	show_camera = Camera3D.new()
	show_camera.current = false
	show_camera_rig.add_child(show_camera)
	show_camera.position = Vector3(0, 18, 32)
	show_camera.look_at(Vector3.ZERO, Vector3.UP)

	create_launch_pad()
	show_pad_always_visible(true)

	drone_input = preload("res://scripts/drone/DroneInput.gd").new()
	drone_input.initialize(3.5)
	drone_input.input_sampled.connect(_on_drone_input_sampled)
	_setup_mavlink_bridge()

	spawn_drone()
	if mavlink_bridge and is_instance_valid(mavlink_bridge):
		mavlink_bridge.control_received.connect(_on_mavlink_control_received)

func spawn_drone():
	if drone and is_instance_valid(drone):
		return

	await get_tree().physics_frame
	
	if launch_pad and is_instance_valid(launch_pad):
		var y_height = get_terrain_height_at(Vector3(350.0, 0.0, 350.0))
		launch_pad.global_position = Vector3(350.0, y_height, 350.0)
		launch_pad.visible = true

	drone = drone_scene.instantiate()
	get_parent().add_child(drone)
	
	if launch_pad and is_instance_valid(launch_pad):
		drone.global_position = launch_pad.global_position + Vector3(0.0, 18.5, 0.0)
	else:
		drone.global_position = Vector3(0.0, 5.0, 0.0)
		
	recharge_structure = launch_pad
	update_camera_views()
	print("DroneControllerManager: Spawned player drone at RechargeTower starting pad.")

func _setup_mavlink_bridge() -> void:
	if not use_mavlink_bridge:
		return
	mavlink_bridge = MavlinkBridge.new()
	mavlink_bridge.enabled = true
	mavlink_bridge.listen_port = mavlink_listen_port
	mavlink_bridge.set_endpoint(mavlink_remote_host, mavlink_remote_port)
	add_child(mavlink_bridge)
	mavlink_bridge.connection_changed.connect(_on_mavlink_connection_changed)
	mavlink_bridge.heartbeat_received.connect(_on_mavlink_heartbeat_received)

func _on_drone_input_sampled(input_vec: Vector4) -> void:
	if mavlink_bridge and is_instance_valid(mavlink_bridge):
		mavlink_bridge.send_control_input(input_vec)

func cleanup():
	if tp_camera: tp_camera.current = false
	if fp_camera: fp_camera.current = false
	if show_camera: show_camera.current = false
	if launch_pad and is_instance_valid(launch_pad):
		launch_pad.queue_free()
		launch_pad = null
		launch_pad_mesh = null
	if drone and is_instance_valid(drone):
		drone.queue_free()
		drone = null
	if swarm_controller and is_instance_valid(swarm_controller):
		if swarm_controller.has_method("cleanup"):
			swarm_controller.cleanup()
		swarm_controller.queue_free()
		swarm_controller = null
	print("DroneControllerManager: Cleaned up player drone and cameras.")

func update_camera_views():
	if not drone or not is_instance_valid(drone): return
	show_camera_active = show_mode != ShowMode.NONE
	if show_camera_active:
		tp_camera.current = false
		fp_camera.current = false
		show_camera.current = true
	elif is_first_person:
		tp_camera.current = false
		fp_camera.current = true
		show_camera.current = false
	else:
		tp_camera.current = true
		fp_camera.current = false
		show_camera.current = false

func _process(delta):
	if camera_toggle_cooldown > 0: camera_toggle_cooldown -= delta
	if state_toggle_cooldown > 0: state_toggle_cooldown -= delta

	if Input.is_key_pressed(KEY_TAB) and state_toggle_cooldown <= 0:
		state_toggle_cooldown = 0.5
		toggle_swarm_mode()
		return

	if Input.is_key_pressed(KEY_B) and state_toggle_cooldown <= 0:
		if show_mode != ShowMode.NONE:
			state_toggle_cooldown = 0.5
			stop_show_mode()
			return

	if Input.is_key_pressed(KEY_R) and state_toggle_cooldown <= 0:
		state_toggle_cooldown = 0.5
		restart_simulation()
		return

	if not drone or not is_instance_valid(drone) or not drone.is_inside_tree():
		return

	_update_low_battery_behavior(delta)

	if Input.is_key_pressed(KEY_C) and camera_toggle_cooldown <= 0:
		is_first_person = !is_first_person
		update_camera_views()
		camera_toggle_cooldown = 0.2

	if Input.is_key_pressed(KEY_H) and state_toggle_cooldown <= 0:
		state_toggle_cooldown = 0.3
		if drone.has_method("set_hover_mode"):
			drone.set_hover_mode(!drone.hover_enabled)
		else:
			drone.hover_enabled = !drone.hover_enabled
		print("DroneControllerManager: Hover mode ", "enabled" if drone.hover_enabled else "disabled")

	if Input.is_key_pressed(KEY_5) and state_toggle_cooldown <= 0:
		state_toggle_cooldown = 0.3
		toggle_autopilot()

	if Input.is_key_pressed(KEY_6) and state_toggle_cooldown <= 0:
		state_toggle_cooldown = 0.3
		start_trick_loop(flight_state == FlightState.MANUAL)

	if Input.is_key_pressed(KEY_7) and state_toggle_cooldown <= 0:
		state_toggle_cooldown = 0.3
		start_trick_barrel(flight_state == FlightState.MANUAL)

	if spring_arm and is_instance_valid(spring_arm) and spring_arm.is_inside_tree():
		if drone and is_instance_valid(drone) and drone.is_inside_tree():
			var follow_pos = drone.global_position
			if show_mode != ShowMode.NONE and swarm_controller and is_instance_valid(swarm_controller) and swarm_controller.has_method("get_swarm_centroid"):
				follow_pos = swarm_controller.get_swarm_centroid()

			spring_arm.global_position = follow_pos + Vector3(0, 0.5, 0)
			spring_arm.global_transform.basis = drone.global_transform.basis
			spring_arm.rotate_object_local(Vector3.RIGHT, deg_to_rad(-20))

	if show_mode != ShowMode.NONE and show_camera and is_instance_valid(show_camera):
		show_camera_timer += delta
		if show_camera_timer >= show_camera_switch_interval:
			show_camera_timer = 0.0
			show_camera_mode = (show_camera_mode + 1) % show_camera_presets.size()
		update_show_camera()

	if fp_camera and is_instance_valid(fp_camera) and fp_camera.is_inside_tree():
		if drone and is_instance_valid(drone) and drone.is_inside_tree():
			var fp_pos = drone.global_transform * Vector3(0, 0.15, -0.35)
			fp_camera.global_position = fp_pos
			fp_camera.global_transform.basis = drone.global_transform.basis.rotated(drone.global_transform.basis.x, deg_to_rad(15))

func restart_simulation() -> void:
	if drone and is_instance_valid(drone):
		drone.queue_free()
		drone = null
	spawn_drone()

func _physics_process(delta):
	if not drone or not is_instance_valid(drone) or not drone.is_inside_tree():
		return

	match flight_state:
		FlightState.MANUAL:
			if show_mode != ShowMode.NONE:
				process_show_mode(delta)
			else:
				var input_vec = _get_control_input(delta)
				drone.set_input_vector(input_vec)
		FlightState.AUTOPILOT:
			process_autopilot_flight(delta)
		FlightState.TRICK_LOOP:
			process_trick_loop(delta)
		FlightState.TRICK_BARREL:
			process_trick_barrel(delta)

func get_drone() -> RigidBody3D:
	return drone

func _get_control_input(delta: float) -> Vector4:
	if mavlink_bridge and use_mavlink_bridge:
		return drone_input.smoothed_input if drone_input else Vector4.ZERO
	return drone_input.get_smoothed_input(delta) if drone_input else Vector4.ZERO

func _on_mavlink_control_received(control: Vector4) -> void:
	if not drone_input: return
	drone_input.smoothed_input = control

func _on_mavlink_connection_changed(connected: bool) -> void:
	print("DroneControllerManager: MAVLink bridge ", "connected" if connected else "disconnected")

func _on_mavlink_heartbeat_received(sys_id: int, comp_id: int) -> void:
	print("DroneControllerManager: MAVLink heartbeat received from sys ", sys_id, " comp ", comp_id)

func _update_low_battery_behavior(_delta: float) -> void:
	if not drone or not is_instance_valid(drone) or not drone.is_inside_tree(): return

	var recharge_node := _get_recharge_target()
	var is_on_tower: bool = false
	if recharge_node and is_instance_valid(recharge_node) and recharge_node.is_inside_tree():
		var horiz_dist = Vector2(drone.global_position.x, drone.global_position.z).distance_to(Vector2(recharge_node.global_position.x, recharge_node.global_position.z))
		var vert_dist = absf(drone.global_position.y - (recharge_node.global_position.y + 18.5))
		if horiz_dist <= 6.5 and vert_dist <= 3.5:
			is_on_tower = true

	if is_on_tower:
		if drone.has_method("start_battery_recharge"):
			drone.start_battery_recharge()
	else:
		if drone.has_method("stop_battery_recharge"):
			drone.stop_battery_recharge()

	if drone.has_method("is_battery_empty") and drone.is_battery_empty(): return
	if not drone.has_method("is_battery_auto_landing") or not drone.is_battery_auto_landing():
		low_battery_return_active = false
		low_battery_landing_active = false
		return

	var target := _get_recharge_target()
	if target == null or not target.is_inside_tree(): return

	if drone.global_position.distance_to(target.global_position) <= 3.5:
		if drone.has_method("set_hover_mode"):
			drone.set_hover_mode(true)
		if drone.has_method("start_battery_recharge"):
			drone.start_battery_recharge()
		low_battery_return_active = false
		low_battery_landing_active = false
		return

	low_battery_return_active = true
	var target_pos := target.global_position + Vector3.UP * 2.0
	var to_target := target_pos - drone.global_position
	var distance := to_target.length()
	var direction := to_target.normalized() if distance > 0.01 else Vector3.ZERO

	if not drone.has_method("set_input_vector"): return

	var input := Vector4.ZERO
	var local_dir := drone.global_transform.basis.inverse() * direction
	input.x = clamp((target_pos.y - drone.global_position.y) * 0.12, -0.55, 0.65)
	input.z = clamp(-local_dir.z * 0.6, -0.75, 0.75)
	input.w = clamp(local_dir.x * 0.6, -0.75, 0.75)

	if distance < 10.0:
		low_battery_landing_active = true
		input.x = -0.15 if drone.global_position.y > target.global_position.y + 0.6 else 0.0
		input.z = 0.0
		input.w = 0.0

	drone.set_input_vector(input)

	if low_battery_landing_active and distance < 4.0:
		if drone.has_method("set_hover_mode"):
			drone.set_hover_mode(true)
		if drone.has_method("start_battery_recharge"):
			drone.start_battery_recharge()
			low_battery_return_active = false
			low_battery_landing_active = false

func _get_recharge_target() -> Node3D:
	if recharge_structure and is_instance_valid(recharge_structure): return recharge_structure
	if launch_pad and is_instance_valid(launch_pad): return launch_pad
	return null

func get_terrain_height_at(pos: Vector3) -> float:
	var space_state = get_world_3d().direct_space_state
	if not space_state: return 0.0
	var from = Vector3(pos.x, 500.0, pos.z)
	var to = Vector3(pos.x, -50.0, pos.z)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 2
	var result = space_state.intersect_ray(query)
	return result.position.y if result.has("position") else 0.0

func process_autopilot_flight(delta):
	autopilot_controller.process_autopilot(delta, drone)

func toggle_autopilot():
	if flight_state == FlightState.AUTOPILOT:
		flight_state = FlightState.MANUAL
		print("DroneControllerManager: Autopilot DISABLED.")
	else:
		flight_state = FlightState.AUTOPILOT
		autopilot_controller.reset()
		print("DroneControllerManager: Autopilot ENABLED.")

func start_trick_loop(from_manual: bool = true):
	post_trick_state = FlightState.MANUAL if from_manual else FlightState.AUTOPILOT
	flight_state = FlightState.TRICK_LOOP
	tricks_controller.start_loop(drone)
	print("DroneControllerManager: Started LOOP trick.")

func process_trick_loop(delta):
	if not tricks_controller.process_loop(delta, drone):
		flight_state = post_trick_state
		print("DroneControllerManager: LOOP trick completed.")

func start_trick_barrel(from_manual: bool = true):
	post_trick_state = FlightState.MANUAL if from_manual else FlightState.AUTOPILOT
	flight_state = FlightState.TRICK_BARREL
	tricks_controller.start_barrel_roll(drone)
	print("DroneControllerManager: Started BARREL ROLL trick.")

func process_trick_barrel(delta):
	if not tricks_controller.process_barrel_roll(delta, drone):
		flight_state = post_trick_state
		print("DroneControllerManager: BARREL ROLL trick completed.")

func select_show_shape(shape_name: String) -> void:
	var mode_val = show_mode_names.get(shape_name.to_lower(), ShowMode.NONE)
	if mode_val != ShowMode.NONE:
		set_show_mode(mode_val)

func toggle_show_mode():
	if show_mode != ShowMode.NONE:
		stop_show_mode()
	else:
		start_show_mode(ShowMode.STAR_FORMATION)

func set_show_mode(mode_id: int):
	if mode_id == ShowMode.NONE:
		stop_show_mode()
	else:
		start_show_mode(mode_id)

func start_custom_image_shape(image_path: String, custom_points_override: Array[Vector3] = []) -> void:
	var center = drone.global_position + Vector3(0, 15, 0) if is_instance_valid(drone) and drone.is_inside_tree() else Vector3(0, 20, 0)
	var custom_points: Array[Vector3] = custom_points_override.duplicate()

	if custom_points.size() == 0:
		var ImageEdgeDetectorClass = load("res://scripts/python/ImageEdgeDetector.gd")
		custom_points = ImageEdgeDetectorClass.process_image_to_formation(image_path, 0, 28.0)

	if custom_points.size() == 0:
		print("DroneControllerManager: Custom image edge detection returned 0 points for: ", image_path)
		return

	var targets: Array[Vector3] = []
	for p in custom_points:
		targets.append(center + p)

	show_mode = 99 # Custom Image Edge Mode

	if not swarm_controller or not is_instance_valid(swarm_controller):
		swarm_controller = preload("res://scripts/SwarmController.gd").new()
		swarm_controller.name = "SwarmController"
		get_parent().add_child(swarm_controller)

	swarm_controller.initialize_formation(drone, targets, center)

	if swarm_controller and is_instance_valid(swarm_controller):
		for d in swarm_controller.drones:
			if is_instance_valid(d) and d.has_method("set_show_lighting_enabled"):
				d.set_show_lighting_enabled(true)

	if is_instance_valid(drone) and drone.has_method("set_show_lighting_enabled"):
		drone.set_show_lighting_enabled(false)

	update_camera_views()
	print("DroneControllerManager: Python Custom Image Shape Airshow started with ", targets.size(), " drones forming shape from image: ", image_path)

func start_show_mode(mode_id: int):
	show_mode = mode_id
	var count = 39
	var center = drone.global_position + Vector3(0, 15, 0) if is_instance_valid(drone) and drone.is_inside_tree() else Vector3(0, 20, 0)
	var targets = show_mode_controller.generate_formation(mode_id, count, center)

	if not swarm_controller or not is_instance_valid(swarm_controller):
		swarm_controller = preload("res://scripts/SwarmController.gd").new()
		swarm_controller.name = "SwarmController"
		get_parent().add_child(swarm_controller)

	swarm_controller.initialize_formation(drone, targets, center)

	if swarm_controller and is_instance_valid(swarm_controller):
		for d in swarm_controller.drones:
			if is_instance_valid(d) and d.has_method("set_show_lighting_enabled"):
				d.set_show_lighting_enabled(true)

	if is_instance_valid(drone) and drone.has_method("set_show_lighting_enabled"):
		drone.set_show_lighting_enabled(true)

	update_camera_views()
	print("DroneControllerManager: Airshow mode ", mode_id, " started with ", targets.size(), " target positions.")

func stop_show_mode():
	show_mode = ShowMode.NONE
	if swarm_controller and is_instance_valid(swarm_controller):
		swarm_controller.clear_swarm()
		swarm_controller.queue_free()
		swarm_controller = null

	if is_instance_valid(drone) and drone.has_method("set_show_lighting_enabled"):
		drone.set_show_lighting_enabled(false)

	show_camera_active = false
	update_camera_views()
	print("DroneControllerManager: Airshow mode stopped.")

func process_show_mode(_delta):
	pass

func toggle_swarm_mode():
	if swarm_mode:
		disable_swarm_mode()
	else:
		enable_swarm_mode()

func enable_swarm_mode():
	if swarm_mode: return
	swarm_mode = true

	if swarm_controller and is_instance_valid(swarm_controller):
		swarm_controller.clear_swarm()
		swarm_controller.queue_free()

	swarm_controller = preload("res://scripts/SwarmController.gd").new()
	swarm_controller.name = "SwarmController"
	get_parent().add_child(swarm_controller)

	var spawn_pos = drone.global_position if is_instance_valid(drone) and drone.is_inside_tree() else Vector3(0, 15, 0)
	swarm_controller.initialize_swarm(drone, 39, spawn_pos + Vector3(0, 3, 0))

	if is_instance_valid(drone):
		drone.set_swarm_mode_active(true)
	print("DroneControllerManager: Swarm Mode ENABLED.")

func disable_swarm_mode():
	if not swarm_mode: return
	swarm_mode = false

	if swarm_controller and is_instance_valid(swarm_controller):
		swarm_controller.clear_swarm()
		swarm_controller.queue_free()
		swarm_controller = null

	if is_instance_valid(drone):
		drone.set_swarm_mode_active(false)

	print("DroneControllerManager: Swarm Mode DISABLED.")

func update_show_camera():
	if not show_camera or not is_instance_valid(show_camera): return
	var live_center = Vector3.ZERO
	if swarm_controller and is_instance_valid(swarm_controller) and swarm_controller.has_method("get_swarm_centroid"):
		live_center = swarm_controller.get_swarm_centroid()
	elif show_mode != ShowMode.NONE:
		live_center = show_center
	else:
		live_center = drone.global_position if is_instance_valid(drone) and drone.is_inside_tree() else Vector3.ZERO

	var preset_offset = show_camera_presets[show_camera_mode]
	show_camera_rig.global_position = show_camera_rig.global_position.lerp(live_center, 0.12)
	show_camera.global_position = show_camera_rig.global_position + preset_offset
	show_camera.look_at(show_camera_rig.global_position, Vector3.UP)

func create_launch_pad() -> void:
	if launch_pad and is_instance_valid(launch_pad):
		return

	launch_pad = StaticBody3D.new()
	launch_pad.name = "RechargeTower"
	launch_pad.collision_layer = 1
	launch_pad.collision_mask = 1
	launch_pad.position = Vector3(350.0, 0.0, 350.0)
	add_child(launch_pad)

	var collision_shape := CollisionShape3D.new()
	var tower_shape := CylinderShape3D.new()
	tower_shape.height = 18.0
	tower_shape.radius = 4.5
	collision_shape.shape = tower_shape
	collision_shape.position = Vector3(0.0, 9.0, 0.0)
	launch_pad.add_child(collision_shape)

	var tower := MeshInstance3D.new()
	var tower_mesh := CylinderMesh.new()
	tower_mesh.top_radius = 4.8
	tower_mesh.bottom_radius = 5.6
	tower_mesh.height = 18.0
	tower_mesh.radial_segments = 6
	tower.mesh = tower_mesh
	tower.position = Vector3(0.0, 9.0, 0.0)
	launch_pad.add_child(tower)

	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.12, 0.12, 0.15, 1.0)
	pad_mat.metallic = 0.85
	pad_mat.roughness = 0.2
	tower.material_override = pad_mat

	var neon_mat := StandardMaterial3D.new()
	neon_mat.albedo_color = Color(1.0, 0.45, 0.0, 1.0)
	neon_mat.emission_enabled = true
	neon_mat.emission = Color(1.0, 0.45, 0.0, 1.0)
	neon_mat.emission_energy_multiplier = 3.5
	neon_mat.roughness = 0.1

	var corner_radius = 5.3
	for i in range(6):
		var angle = i * PI / 3.0
		var bar := MeshInstance3D.new()
		var bar_mesh := BoxMesh.new()
		bar_mesh.size = Vector3(0.2, 18.0, 0.2)
		bar.mesh = bar_mesh
		bar.position = Vector3(cos(angle) * corner_radius, 9.0, sin(angle) * corner_radius)
		bar.material_override = neon_mat
		launch_pad.add_child(bar)

	var landing_stand := MeshInstance3D.new()
	var stand_mesh := CylinderMesh.new()
	stand_mesh.top_radius = 1.2
	stand_mesh.bottom_radius = 1.2
	stand_mesh.height = 2.5
	stand_mesh.radial_segments = 16
	landing_stand.mesh = stand_mesh
	landing_stand.position = Vector3(0.0, 1.25, 0.0)
	landing_stand.material_override = pad_mat
	launch_pad.add_child(landing_stand)

	var pad_ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.outer_radius = 1.1
	ring_mesh.inner_radius = 0.95
	pad_ring.mesh = ring_mesh
	pad_ring.position = Vector3(0.0, 2.51, 0.0)
	pad_ring.material_override = neon_mat
	launch_pad.add_child(pad_ring)

	var top_light := OmniLight3D.new()
	top_light.light_color = Color(1.0, 0.45, 0.0)
	top_light.light_energy = 2.5
	top_light.omni_range = 15.0
	top_light.position = Vector3(0.0, 3.5, 0.0)
	launch_pad.add_child(top_light)

	launch_pad_mesh = tower
	launch_pad_marker = null
	launch_pad.visible = true

func show_pad_always_visible(vis: bool):
	if launch_pad and is_instance_valid(launch_pad):
		launch_pad.visible = vis
