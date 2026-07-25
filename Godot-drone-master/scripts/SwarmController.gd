extends Node3D

@export var drone_scene: PackedScene = preload("res://scenes/Drone.tscn")
@export var swarm_count: int = 15
@export var neighborhood_radius: float = 12.0
@export var separation_radius: float = 3.5

@export var max_speed: float = 24.0
@export var min_speed: float = 6.0
@export var max_force: float = 18.0

@export var weight_separation: float = 2.2
@export var weight_cohesion: float = 1.0
@export var weight_alignment: float = 1.2
@export var weight_target: float = 2.8

@export var update_divisor: int = 2
var update_phase: int = 0

var leader_drone: RigidBody3D = null
var drones: Array[RigidBody3D] = []
var drone_last_input_vectors: Array[Vector4] = []
var drone_terrain_heights: Array[float] = []

var active: bool = false
var spatial_hash: SpatialHash3D = SpatialHash3D.new(8.0)
var spatial_cell_size: float = 8.0

var formation_active: bool = false
var formation_targets: Array[Vector3] = []
var formation_settling: bool = false
var formation_transition_time: float = 0.0
var formation_transition_duration: float = 4.0
var formation_arrival_radius: float = 1.5
var formation_hold_altitude: float = 30.0
var formation_hold_tolerance: float = 0.5
var ground_clearance: float = 2.5
var target_position: Vector3 = Vector3.ZERO
var terrain_exclusions: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	spatial_cell_size = neighborhood_radius

func clear_swarm():
	active = false
	formation_active = false
	for d in drones:
		if d and is_instance_valid(d):
			d.queue_free()
	drones.clear()
	drone_last_input_vectors.clear()
	drone_terrain_heights.clear()
	formation_targets.clear()

func cleanup():
	clear_swarm()

func initialize_swarm(leader: RigidBody3D, count: int = 15, spawn_pos: Vector3 = Vector3(0, 15, 0)):
	clear_swarm()
	leader_drone = leader
	swarm_count = count
	update_divisor = 1 if swarm_count <= 18 else 2 if swarm_count <= 32 else 3
	update_phase = 0
	active = true
	formation_active = false

	drone_last_input_vectors.resize(swarm_count)
	drone_last_input_vectors.fill(Vector4.ZERO)
	drone_terrain_heights.resize(swarm_count)
	drone_terrain_heights.fill(0.0)

	target_position = spawn_pos

	for i in range(swarm_count):
		var drone_inst: RigidBody3D = drone_scene.instantiate()
		drone_inst.low_detail_visuals = true
		get_parent().add_child(drone_inst)
		var angle = randf() * TAU
		var dist = randf_range(3.0, 12.0)
		drone_inst.global_position = spawn_pos + Vector3(cos(angle) * dist, randf_range(-1.0, 3.0), sin(angle) * dist)
		drone_inst.linear_velocity = Vector3.ZERO
		drone_inst.angular_velocity = Vector3.ZERO
		if drone_inst.has_method("set_input_vector"):
			drone_inst.set_input_vector(Vector4.ZERO)
		drone_inst.collision_layer = 4
		drone_inst.collision_mask = 1
		
		if drone_inst.has_method("setup_show_lights") and drone_inst.get("show_rig") != null:
			drone_inst.show_rig.configure(i, swarm_count, false)
			drone_inst.show_rig.set_low_cost_mode(true)
			drone_inst.show_rig.set_show_lighting_enabled(false)
		if drone_inst.has_method("set_low_detail_visuals"):
			drone_inst.set_low_detail_visuals(true)
		if drone_inst.has_method("refresh_visual_state"):
			drone_inst.refresh_visual_state()
			
		drones.append(drone_inst)

	print("SwarmController: Swarm initialized with ", drones.size(), " follower drones.")
	_rebuild_terrain_exclusions()

func initialize_formation(leader: RigidBody3D, targets: Array[Vector3], spawn_pos: Vector3 = Vector3(0, 15, 0)):
	clear_swarm()
	leader_drone = leader
	swarm_count = targets.size()
	update_divisor = 1 if swarm_count <= 18 else 2 if swarm_count <= 32 else 3
	update_phase = 0
	active = true
	formation_active = true
	formation_settling = true
	formation_transition_time = 0.0
	formation_targets = targets.duplicate()

	drone_last_input_vectors.resize(swarm_count)
	drone_last_input_vectors.fill(Vector4.ZERO)
	drone_terrain_heights.resize(swarm_count)
	drone_terrain_heights.fill(0.0)

	target_position = spawn_pos
	formation_hold_altitude = spawn_pos.y + 28.0

	var ground_y = spawn_pos.y
	for i in range(swarm_count):
		var drone_inst: RigidBody3D = drone_scene.instantiate()
		drone_inst.low_detail_visuals = true
		get_parent().add_child(drone_inst)
		var target_spawn: Vector3 = targets[i]
		drone_inst.global_position = Vector3(
			target_spawn.x + randf_range(-1.5, 1.5),
			ground_y + randf_range(0.5, 2.5),
			target_spawn.z + randf_range(-1.5, 1.5)
		)
		drone_inst.linear_velocity = Vector3.ZERO
		drone_inst.angular_velocity = Vector3.ZERO
		if drone_inst.has_method("set_hover_mode"):
			drone_inst.set_hover_mode(true)
		if drone_inst.has_method("set_input_vector"):
			drone_inst.set_input_vector(Vector4.ZERO)
		drone_inst.collision_layer = 4
		drone_inst.collision_mask = 1
		if drone_inst.has_method("setup_show_lights") and drone_inst.get("show_rig") != null:
			drone_inst.show_rig.configure(i, swarm_count, false)
			drone_inst.show_rig.set_low_cost_mode(true)
			drone_inst.show_rig.set_show_lighting_enabled(true)
		if drone_inst.has_method("set_low_detail_visuals"):
			drone_inst.set_low_detail_visuals(true)
		if drone_inst.has_method("refresh_visual_state"):
			drone_inst.refresh_visual_state()
		drones.append(drone_inst)

	print("SwarmController: Formation initialized with ", drones.size(), " drones at ground launch height.")
	_rebuild_terrain_exclusions()

func _rebuild_terrain_exclusions() -> void:
	terrain_exclusions.clear()
	var main_scene = get_tree().current_scene if get_tree() else null
	if not main_scene:
		return
	var env_node = main_scene.get_node_or_null("MapEarthNight")
	if not env_node:
		for child in main_scene.get_children():
			if child.name.begins_with("Map"):
				env_node = child
				break
	if env_node and env_node.has_method("get_exclusion_zones"):
		terrain_exclusions = env_node.get_exclusion_zones()

func _physics_process(delta: float) -> void:
	if not active or drones.size() == 0:
		return
	if get_tree().paused:
		return

	if formation_active:
		_process_formation(delta)
		return

	update_phase = (update_phase + 1) % update_divisor
	spatial_hash.clear()

	for i in range(drones.size()):
		var d = drones[i]
		if d and is_instance_valid(d):
			spatial_hash.insert(i, d.global_position)

	if leader_drone and is_instance_valid(leader_drone):
		target_position = leader_drone.global_position

	for i in range(drones.size()):
		if (i % update_divisor) != update_phase:
			var d_prev = drones[i]
			if d_prev and is_instance_valid(d_prev) and drone_last_input_vectors.size() > i:
				d_prev.set_input_vector(drone_last_input_vectors[i])
			continue

		var drone_inst: RigidBody3D = drones[i]
		if not drone_inst or not is_instance_valid(drone_inst):
			continue

		var pos: Vector3 = drone_inst.global_position
		var vel: Vector3 = drone_inst.linear_velocity

		var neighbor_indices = spatial_hash.get_neighbor_indices(pos, neighborhood_radius)

		var sep_force: Vector3 = Vector3.ZERO
		var coh_pos: Vector3 = Vector3.ZERO
		var ali_vel: Vector3 = Vector3.ZERO
		var neighbor_count: int = 0
		var sep_count: int = 0

		for idx in neighbor_indices:
			if idx == i or idx >= drones.size():
				continue
			var other: RigidBody3D = drones[idx]
			if not other or not is_instance_valid(other):
				continue

			var other_pos: Vector3 = other.global_position
			var diff: Vector3 = pos - other_pos
			var dist: float = diff.length()

			if dist < neighborhood_radius and dist > 0.001:
				neighbor_count += 1
				coh_pos += other_pos
				ali_vel += other.linear_velocity

				if dist < separation_radius:
					sep_force += (diff.normalized() / dist)
					sep_count += 1

		if neighbor_count > 0:
			coh_pos /= float(neighbor_count)
			ali_vel /= float(neighbor_count)
			coh_pos = (coh_pos - pos).normalized() * max_speed
			ali_vel = ali_vel.normalized() * max_speed

		if sep_count > 0:
			sep_force = sep_force.normalized() * max_speed

		var target_vel: Vector3 = _get_target_velocity()
		var steering: Vector3 = (
			sep_force * weight_separation +
			coh_pos * weight_cohesion +
			ali_vel * weight_alignment +
			target_vel * weight_target
		)

		if steering.length() > max_force:
			steering = steering.normalized() * max_force

		var desired_velocity: Vector3 = vel + steering * delta
		if desired_velocity.length() > max_speed:
			desired_velocity = desired_velocity.normalized() * max_speed

		var local_vel: Vector3 = drone_inst.global_transform.basis.inverse() * desired_velocity

		var forward_force: float = clamp(-local_vel.z / max_speed, -1.0, 1.0)
		var strafe_force: float = clamp(local_vel.x / max_speed, -1.0, 1.0)

		var target_y: float = target_position.y
		if (i % 8) == 0:
			var ray_y := get_terrain_height_at(pos)
			if drone_terrain_heights.size() > i:
				drone_terrain_heights[i] = ray_y
		elif drone_terrain_heights.size() > i:
			var cached_y := drone_terrain_heights[i]
			if cached_y > 0.0:
				target_y = max(target_y, cached_y + ground_clearance)

		for zone in terrain_exclusions:
			var center: Vector3 = zone["center"]
			var radius: float = zone["radius"]
			var height: float = zone["height"]
			var xz_dist = Vector2(pos.x - center.x, pos.z - center.z).length()
			if xz_dist < radius:
				target_y = max(target_y, center.y + height + ground_clearance)

		var vert_diff: float = target_y - pos.y
		var vertical_force: float = clamp(vert_diff * 0.15, -1.0, 1.0)
		var throttle: float = clamp(0.5 + vertical_force * 0.5, 0.0, 1.0)

		var local_force: Vector3 = drone_inst.global_transform.basis.inverse() * (desired_velocity - vel)
		var yaw = clamp(local_force.x * 0.10, -1.0, 1.0)
		var pitch = clamp(-local_force.z * 0.10, -1.0, 1.0)
		var roll = clamp(local_force.x * 0.10, -1.0, 1.0)

		var input_vector = Vector4(throttle, yaw, pitch, roll)
		if drone_last_input_vectors.size() > i:
			drone_last_input_vectors[i] = input_vector
		drone_inst.set_input_vector(input_vector)

func _process_formation(delta: float) -> void:
	formation_transition_time = min(formation_transition_time + delta, formation_transition_duration)
	var formation_count: int = min(drones.size(), formation_targets.size())
	if formation_count == 0:
		return

	for i in range(formation_count):
		var drone_inst: RigidBody3D = drones[i]
		if not drone_inst or not is_instance_valid(drone_inst):
			continue

		var target_offset: Vector3 = formation_targets[i]
		var pos: Vector3 = drone_inst.global_position
		var target_y: float = target_position.y + 28.0 + target_offset.y
		var show_target: Vector3 = Vector3(target_offset.x, target_y, target_offset.z)

		var vert_err: float = show_target.y - pos.y
		var horiz_diff: Vector3 = Vector3(show_target.x - pos.x, 0.0, show_target.z - pos.z)

		# Horizontal position snap & lerp toward target formation point
		drone_inst.global_position.x = lerpf(pos.x, show_target.x, clampf(delta * 4.0, 0.01, 1.0))
		drone_inst.global_position.z = lerpf(pos.z, show_target.z, clampf(delta * 4.0, 0.01, 1.0))

		# Vertical ascent and strict altitude lock
		if pos.y < show_target.y - 0.5:
			drone_inst.linear_velocity.y = lerpf(drone_inst.linear_velocity.y, clampf(vert_err * 2.5, 2.0, 12.0), delta * 5.0)
		else:
			drone_inst.linear_velocity.y = lerpf(drone_inst.linear_velocity.y, 0.0, delta * 10.0)
			drone_inst.global_position.y = lerpf(pos.y, show_target.y, clampf(delta * 6.0, 0.01, 1.0))

		if drone_inst.has_method("set_hover_mode"):
			drone_inst.set_hover_mode(true)
		if drone_inst.has_method("set_input_vector"):
			drone_inst.set_input_vector(Vector4.ZERO)

func get_terrain_height_at(pos: Vector3) -> float:
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return 0.0
	var from = Vector3(pos.x, 300.0, pos.z)
	var to = Vector3(pos.x, -50.0, pos.z)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 2

	var result = space_state.intersect_ray(query)
	if result.has("position"):
		return result.position.y
	return 0.0

func _get_target_velocity() -> Vector3:
	if not leader_drone or not is_instance_valid(leader_drone):
		return Vector3.ZERO
	return leader_drone.linear_velocity

func get_swarm_centroid() -> Vector3:
	var center = Vector3.ZERO
	var count = 0
	if leader_drone and is_instance_valid(leader_drone):
		center += leader_drone.global_position
		count += 1
	for d in drones:
		if d and is_instance_valid(d):
			center += d.global_position
			count += 1
	if count > 0:
		return center / count
	return target_position

func get_swarm_average_velocity() -> Vector3:
	var avg_vel = Vector3.ZERO
	var count = 0
	if leader_drone and is_instance_valid(leader_drone):
		avg_vel += leader_drone.linear_velocity
		count += 1
	for d in drones:
		if d and is_instance_valid(d):
			avg_vel += d.linear_velocity
			count += 1
	if count > 0:
		return avg_vel / count
	return Vector3.ZERO

func _get_spatial_cell(pos: Vector3) -> Vector3i:
	return Vector3i(
		int(floor(pos.x / spatial_cell_size)),
		int(floor(pos.y / spatial_cell_size)),
		int(floor(pos.z / spatial_cell_size))
	)

func _get_spatial_cell_key(pos: Vector3) -> Vector3i:
	return _get_spatial_cell(pos)
