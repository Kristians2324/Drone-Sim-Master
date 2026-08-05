extends Node3D
class_name BoidManager

const SpatialHash3D = preload("res://scripts/swarm/SpatialHash3D.gd")

@export var drone_scene: PackedScene = preload("res://scenes/Drone.tscn")
@export var boid_count: int = 15
@export var neighborhood_radius: float = 12.0
@export var separation_radius: float = 3.5
@export var max_neighbours: int = 7

# Steering weights
@export var cohesion_weight: float = 1.0
@export var separation_weight: float = 2.2
@export var alignment_weight: float = 0.8
@export var target_weight: float = 2.5
@export var target_separation_weight: float = 3.5
@export var ground_avoid_weight: float = 5.0

@export var target_arrival_radius: float = 15.0
@export var target_separation_radius: float = 6.0

@export var target_lead_time: float = 0.45
@export var target_catchup_distance: float = 55.0
@export var target_catchup_speed_bonus: float = 16.0
@export var min_target_speed_ratio: float = 0.7

@export var max_speed: float = 20.0
@export var max_force: float = 12.0

var boids: Array[RigidBody3D] = []
var target_node: Node3D = null
var _spatial_hash

func _init() -> void:
	_spatial_hash = SpatialHash3D.new(neighborhood_radius)

func _get_target_velocity() -> Vector3:
	if target_node is RigidBody3D:
		return (target_node as RigidBody3D).linear_velocity
	return Vector3.ZERO

func _get_pursuit_point(target_pos: Vector3, distance_to_target: float) -> Vector3:
	var target_velocity := _get_target_velocity()
	if target_velocity.is_zero_approx():
		return target_pos
	var distance_factor: float = clampf(distance_to_target / maxf(target_catchup_distance, 0.001), 0.0, 1.0)
	var lead_time: float = lerpf(target_lead_time * 0.35, target_lead_time, distance_factor)
	return target_pos + (target_velocity * lead_time)

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

func spawn_boids():
	var spawn_center = target_node.global_position if target_node else Vector3.ZERO
	for i in range(boid_count):
		var drone_inst = drone_scene.instantiate()
		drone_inst.audio_enabled = false
		if drone_inst.has_method("set_audio_enabled"):
			drone_inst.set_audio_enabled(false)
		add_child(drone_inst)
		var offset = Vector3(
			randf_range(-10.0, 10.0),
			randf_range(2.0, 10.0),
			randf_range(-10.0, 10.0)
		)
		drone_inst.global_position = spawn_center + offset
		drone_inst.linear_velocity = Vector3(
			randf_range(-5.0, 5.0),
			randf_range(-2.0, 5.0),
			randf_range(-5.0, 5.0)
		).normalized() * randf_range(5.0, 10.0)
		if drone_inst.show_rig:
			drone_inst.show_rig.configure(i, boid_count, false)
		boids.append(drone_inst)

func _physics_process(_delta):
	if get_tree().paused or boids.size() == 0:
		return

	var target_pos = target_node.global_position if target_node else Vector3.ZERO
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
				var diff = (pos - other_pos).normalized() / dist
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
			steer_separation = (desired - vel).limit_length(max_force)

		var dist_to_target = pos.distance_to(target_pos)
		var pursuit_point = _get_pursuit_point(target_pos, dist_to_target)
		var steer_target = Vector3.ZERO
		if dist_to_target > 0.001:
			var catchup_factor: float = clampf((dist_to_target - target_arrival_radius) / maxf(target_catchup_distance, 0.001), 0.0, 1.0)
			var speed_floor: float = max_speed * min_target_speed_ratio
			var speed_ceiling: float = max_speed + target_catchup_speed_bonus
			var speed: float = lerpf(speed_floor, speed_ceiling, catchup_factor)
			if dist_to_target < target_arrival_radius:
				var approach_ratio: float = clampf(dist_to_target / maxf(target_arrival_radius, 0.001), 0.0, 1.0)
				speed = maxf(speed_floor, lerpf(speed_floor, max_speed, approach_ratio))
			var desired_target = (pursuit_point - pos).normalized() * speed
			var catchup_force: float = max_force
			if dist_to_target > target_arrival_radius:
				catchup_force *= lerpf(1.0, 1.75, catchup_factor)
			steer_target = (desired_target - vel).limit_length(catchup_force)

		var steer_target_separation = Vector3.ZERO
		if dist_to_target < target_separation_radius and dist_to_target > 0.001:
			var diff = (pos - pursuit_point).normalized() / dist_to_target
			var desired = diff * max_speed
			steer_target_separation = (desired - vel).limit_length(max_force * 1.5)

		var steer_ground = Vector3.ZERO
		var terrain_height = get_terrain_height_at(pos)
		var min_height_above_ground = 7.0
		if pos.y < terrain_height + min_height_above_ground:
			var desired_up = Vector3(vel.x, max_speed, vel.z).normalized() * max_speed
			var correction_depth = (terrain_height + min_height_above_ground) - pos.y
			var scale_factor = clamp(1.0 + (correction_depth / 2.0), 1.0, 3.0)
			steer_ground = (desired_up - vel).limit_length(max_force * scale_factor)

		var total_force = (
			steer_cohesion * cohesion_weight +
			steer_separation * separation_weight +
			steer_alignment * alignment_weight +
			steer_target * target_weight +
			steer_target_separation * target_separation_weight +
			steer_ground * ground_avoid_weight
		)

		var local_force = boid.global_transform.basis.inverse() * total_force
		var throttle = clamp(0.5 + total_force.y * 0.05, 0.0, 1.0)
		var yaw = 0.0

		if vel.length_squared() > 1.0:
			var target_dir = vel.normalized()
			var current_dir = -boid.global_transform.basis.z
			var angle = current_dir.signed_angle_to(target_dir, Vector3.UP)
			yaw = clamp(angle * 1.5, -1.0, 1.0)

		var pitch = clamp(-local_force.z * 0.05, -1.0, 1.0)
		var roll = clamp(local_force.x * 0.05, -1.0, 1.0)

		boid.set_input_vector(Vector4(throttle, yaw, pitch, roll))
