extends Node3D
class_name BoidManager

const SpatialHash3D = preload("res://scripts/swarm/SpatialHash3D.gd")

@export var drone_scene: PackedScene = preload("res://scenes/Drone.tscn")
@export var boid_count: int = 20
@export var neighborhood_radius: float = 14.0
@export var separation_radius: float = 4.2
@export var max_neighbours: int = 6

# Steering weights
@export var cohesion_weight: float = 0.8
@export var separation_weight: float = 3.5
@export var alignment_weight: float = 1.0
@export var target_weight: float = 3.2
@export var target_separation_weight: float = 3.8
@export var ground_avoid_weight: float = 4.0

@export var target_separation_radius: float = 4.5

@export var max_speed: float = 55.0
@export var max_force: float = 60.0

var boids: Array[RigidBody3D] = []
var formation_offsets: Array[Vector3] = []
var boid_smoothed_inputs: Array[Vector4] = []
var target_node: Node3D = null
var swarm_audio: SwarmAudio = null
var sim_time: float = 0.0
var _spatial_hash

func _init() -> void:
	_spatial_hash = SpatialHash3D.new(neighborhood_radius)

func _get_target_velocity() -> Vector3:
	if target_node is RigidBody3D:
		return (target_node as RigidBody3D).linear_velocity
	return Vector3.ZERO

func get_swarm_centroid() -> Vector3:
	var total_pos = Vector3.ZERO
	var count = 0
	for b in boids:
		if b and is_instance_valid(b):
			total_pos += b.global_position
			count += 1
	return (total_pos / float(count)) if count > 0 else (target_node.global_position if target_node else Vector3.ZERO)

func get_terrain_height_at(pos: Vector3) -> float:
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return 0.0
	var from = Vector3(pos.x, 300.0, pos.z)
	var to = Vector3(pos.x, -50.0, pos.z)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 2
	var result = space_state.intersect_ray(query)
	return result.position.y if result.has("position") else 0.0

func initialize(target: Node3D):
	target_node = target
	spawn_boids()

func _ready():
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _ensure_swarm_audio() -> void:
	if swarm_audio == null or not is_instance_valid(swarm_audio):
		swarm_audio = SwarmAudio.new()
		swarm_audio.name = "BoidSwarmAudio"
		add_child(swarm_audio)

func spawn_boids():
	var spawn_center = target_node.global_position if target_node else Vector3.ZERO
	formation_offsets.clear()
	boid_smoothed_inputs.clear()

	# Create a clean, spacious 3D golden-ratio formation envelope around the player (4.0m to 8.5m radius)
	var golden_ratio = (1.0 + sqrt(5.0)) / 2.0
	for i in range(boid_count):
		var theta = 2.0 * PI * i / golden_ratio
		var phi = acos(1.0 - 2.0 * (i + 0.5) / float(boid_count))
		var r = 4.2 + fmod(i * 0.7, 4.3)
		var offset = Vector3(r * sin(phi) * cos(theta), r * sin(phi) * sin(theta), r * cos(phi))
		formation_offsets.append(offset)
		boid_smoothed_inputs.append(Vector4.ZERO)

		var drone_inst: RigidBody3D = drone_scene.instantiate()
		drone_inst.collision_layer = 0
		drone_inst.collision_mask = 0
		drone_inst.contact_monitor = false
		drone_inst.max_contacts_reported = 0
		drone_inst.audio_enabled = false
		if drone_inst.has_method("set_audio_enabled"):
			drone_inst.set_audio_enabled(false)
		
		add_child(drone_inst)
		drone_inst.global_position = spawn_center + offset
		drone_inst.freeze = false
		drone_inst.gravity_scale = 0.0
		drone_inst.linear_damp = 2.5
		drone_inst.angular_damp = 6.0
		
		if drone_inst.get("show_rig") != null and drone_inst.show_rig:
			drone_inst.show_rig.set_show_lighting_enabled(false)
		
		boids.append(drone_inst)

func _physics_process(delta: float):
	if get_tree().paused or boids.size() == 0:
		if swarm_audio and is_instance_valid(swarm_audio):
			swarm_audio.set_swarm_enabled(false)
		return

	sim_time += delta
	var target_pos = target_node.global_position if target_node else Vector3.ZERO
	var target_vel = _get_target_velocity()

	# Manage single spatialized 3D swarm audio (Soft, non-intrusive background hive sound)
	_ensure_swarm_audio()
	var centroid = get_swarm_centroid()
	var avg_speed = target_vel.length()
	if swarm_audio:
		swarm_audio.set_swarm_enabled(true)
		swarm_audio.update_swarm_audio(centroid, avg_speed, boids.size(), delta)

	var positions: Array[Vector3] = []
	var velocities: Array[Vector3] = []
	positions.resize(boids.size())
	velocities.resize(boids.size())

	_spatial_hash.clear()
	for i in range(boids.size()):
		var b = boids[i]
		if b and is_instance_valid(b):
			positions[i] = b.global_position
			velocities[i] = b.linear_velocity
			_spatial_hash.insert(i, positions[i])
		else:
			positions[i] = Vector3.ZERO
			velocities[i] = Vector3.ZERO

	var nr_sq = neighborhood_radius * neighborhood_radius

	for i in range(boids.size()):
		var boid = boids[i]
		if not boid or not is_instance_valid(boid):
			continue

		var pos = positions[i]
		var vel = velocities[i]

		var steer_cohesion = Vector3.ZERO
		var steer_separation = Vector3.ZERO
		var steer_alignment = Vector3.ZERO
		var cohesion_center = Vector3.ZERO
		var alignment_vel = Vector3.ZERO
		var cohesion_count = 0
		var separation_count = 0
		var alignment_count = 0

		var candidate_indices: Array[int] = _spatial_hash.get_neighbor_indices(pos, neighborhood_radius)
		var neighbour_entries: Array = []
		for j in candidate_indices:
			if i == j: continue
			var d_sq = pos.distance_squared_to(positions[j])
			if d_sq < nr_sq:
				neighbour_entries.append([d_sq, j])

		if neighbour_entries.size() > max_neighbours:
			neighbour_entries.sort_custom(func(a, b): return a[0] < b[0])
			neighbour_entries = neighbour_entries.slice(0, max_neighbours)

		for entry in neighbour_entries:
			var j = entry[1]
			var other_pos = positions[j]
			var other_vel = velocities[j]
			var dist = sqrt(entry[0])

			cohesion_center += other_pos
			cohesion_count += 1
			alignment_vel += other_vel
			alignment_count += 1

			if dist < separation_radius and dist > 0.001:
				var diff = (pos - other_pos).normalized() * ((separation_radius - dist) / separation_radius)
				steer_separation += diff
				separation_count += 1

		if cohesion_count > 0:
			cohesion_center /= cohesion_count
			var desired = (cohesion_center - pos).normalized() * max_speed
			steer_cohesion = (desired - vel).limit_length(max_force)

		if alignment_count > 0:
			alignment_vel /= alignment_count
			var desired = alignment_vel.normalized() * max_speed
			steer_alignment = (desired - vel).limit_length(max_force)

		if separation_count > 0:
			steer_separation /= separation_count
			var desired = steer_separation.normalized() * max_speed
			steer_separation = (desired - vel).limit_length(max_force * 1.5)

		# Target slot in formation around player (Matches 3D player altitude)
		var slot_offset = formation_offsets[i] if i < formation_offsets.size() else Vector3.ZERO
		var target_slot_pos = target_pos + slot_offset
		if not target_vel.is_zero_approx():
			target_slot_pos += target_vel * 0.20

		var terrain_h = get_terrain_height_at(target_slot_pos)
		target_slot_pos.y = maxf(target_slot_pos.y, terrain_h + 3.0)
			
		var dist_to_slot = pos.distance_to(target_slot_pos)
		var steer_target = Vector3.ZERO
		if dist_to_slot > 0.001:
			var player_speed = target_vel.length()
			var catchup_mult = 1.0 + clampf(dist_to_slot / 4.0, 0.0, 2.5)
			var target_speed = maxf(player_speed + 6.0, 30.0) * catchup_mult
			var desired_target = (target_slot_pos - pos).normalized() * target_speed
			steer_target = (desired_target - vel).limit_length(max_force * 2.0 * catchup_mult)

		# Repel from camera/invisible center player node
		var dist_to_player = pos.distance_to(target_pos)
		var steer_target_separation = Vector3.ZERO
		if dist_to_player < target_separation_radius and dist_to_player > 0.001:
			var diff = (pos - target_pos).normalized() * ((target_separation_radius - dist_to_player) / target_separation_radius)
			var desired = diff * max_speed
			steer_target_separation = (desired - vel).limit_length(max_force * 1.5)

		var steer_ground = Vector3.ZERO
		var terrain_height = get_terrain_height_at(pos)
		var min_height_above_ground = 4.0
		if pos.y < terrain_height + min_height_above_ground:
			var desired_up = Vector3(vel.x, max_speed, vel.z).normalized() * max_speed
			var correction_depth = (terrain_height + min_height_above_ground) - pos.y
			var scale_factor = clamp(1.0 + (correction_depth / 2.0), 1.0, 3.0)
			steer_ground = (desired_up - vel).limit_length(max_force * scale_factor)

		# 1. Total Steering Acceleration
		var total_force = (
			steer_cohesion * cohesion_weight +
			steer_separation * separation_weight +
			steer_alignment * alignment_weight +
			steer_target * target_weight +
			steer_target_separation * target_separation_weight +
			steer_ground * ground_avoid_weight
		)

		# 2. Organic Hover Float Oscillation (Gives every follower drone natural life and floating movement)
		var float_x = sin(sim_time * 1.8 + float(i) * 1.3) * 0.4
		var float_y = sin(sim_time * 2.6 + float(i) * 0.8) * 0.3
		var float_z = cos(sim_time * 2.1 + float(i) * 1.7) * 0.4
		total_force += Vector3(float_x, float_y, float_z)

		# 3. Transform to Local Basis for Quadrotor Pitch & Roll Dynamic Tilting
		var local_force = boid.global_transform.basis.inverse() * total_force

		# Synthesize quadrotor flight control inputs
		var target_throttle = clampf(0.50 + total_force.y * 0.025, 0.05, 1.0)
		var target_pitch = clampf(-local_force.z * 0.035, -0.5, 0.5)
		var target_roll = clampf(local_force.x * 0.035, -0.5, 0.5)
		var target_yaw = 0.0

		if vel.length_squared() > 0.5:
			var target_dir = vel.normalized()
			var current_dir = -boid.global_transform.basis.z
			var angle = current_dir.signed_angle_to(target_dir, Vector3.UP)
			target_yaw = clampf(angle * 1.2, -1.0, 1.0)

		# Smooth control input vector (Silk-smooth physics quadrotor simulation)
		var prev_input = boid_smoothed_inputs[i] if i < boid_smoothed_inputs.size() else Vector4.ZERO
		var target_input = Vector4(target_throttle, target_yaw, target_pitch, target_roll)
		var lerped_input = prev_input.lerp(target_input, clampf(delta * 4.5, 0.05, 0.25))
		if i < boid_smoothed_inputs.size():
			boid_smoothed_inputs[i] = lerped_input

		boid.set_input_vector(lerped_input)
