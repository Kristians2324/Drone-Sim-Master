extends Node

## Swarm Controller & Drone Formation Manager
## Handles boid flocking, ground takeoff staging, and smooth 3D shape-to-shape transitions with Spatial Nearest Assignment.

const SpatialHash3D = preload("res://scripts/swarm/SpatialHash3D.gd")

var drones: Array[Node] = []
var leader_drone: Node = null
var target_position: Vector3 = Vector3.ZERO

# Boid flocking parameters
var neighborhood_radius: float = 12.0
var separation_radius: float = 3.5
var max_speed: float = 18.0
var min_speed: float = 4.0
var max_force: float = 12.0

var boid_count: int = 15
var update_divisor: int = 2
var update_phase: int = 0
var spatial_hash: SpatialHash3D
var active: bool = false
var boid_scatter_offsets: Array[Vector3] = []

# Formation parameters
var formation_active: bool = false
var formation_settling: bool = false
var formation_transition_time: float = 0.0
var formation_transition_duration: float = 3.2
var formation_targets: Array[Vector3] = []
var formation_hold_altitude: float = 25.0

# Smooth Flying Transition State
var is_transitioning: bool = false
var transition_elapsed: float = 0.0
var start_positions: Array[Vector3] = []
var target_positions: Array[Vector3] = []

var drone_scene: PackedScene = preload("res://scenes/Drone.tscn")
var drone_last_input_vectors: Array[Vector4] = []
var drone_terrain_heights: Array[float] = []
var terrain_exclusions: Array[Dictionary] = []

var swarm_audio_component: SwarmAudio = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	spatial_hash = SpatialHash3D.new(8.0)

func cleanup() -> void:
	clear_swarm()

func clear_swarm() -> void:
	active = false
	formation_active = false
	is_transitioning = false
	if swarm_audio_component and is_instance_valid(swarm_audio_component):
		swarm_audio_component.set_swarm_enabled(false)
	for d in drones:
		if d and is_instance_valid(d):
			d.queue_free()
	drones.clear()
	formation_targets.clear()
	start_positions.clear()
	target_positions.clear()
	boid_scatter_offsets.clear()
	drone_last_input_vectors.clear()
	drone_terrain_heights.clear()

func initialize_swarm(leader: Node, count: int = 15, spawn_center: Vector3 = Vector3.ZERO) -> void:
	clear_swarm()
	if spatial_hash == null:
		spatial_hash = SpatialHash3D.new(8.0)
	leader_drone = leader
	boid_count = count
	update_divisor = 1 if boid_count <= 25 else (2 if boid_count <= 80 else 4)
	update_phase = 0
	active = true
	formation_active = false

	var center = spawn_center if spawn_center != Vector3.ZERO else (leader.global_position if leader else Vector3(0, 10, 0))

	drone_last_input_vectors.resize(boid_count)
	drone_last_input_vectors.fill(Vector4.ZERO)
	drone_terrain_heights.resize(boid_count)
	drone_terrain_heights.fill(0.0)

	boid_scatter_offsets.clear()
	for i in range(boid_count):
		var drone_inst: RigidBody3D = drone_scene.instantiate()
		drone_inst.low_detail_visuals = true
		drone_inst.audio_enabled = true
		get_parent().add_child(drone_inst)

		var theta = randf() * TAU
		var phi = acos(randf_range(-0.85, 0.85))
		var r = randf_range(4.0, 12.0)
		var offset = Vector3(r * sin(phi) * cos(theta), r * sin(phi) * sin(theta), r * cos(phi))
		boid_scatter_offsets.append(offset)

		drone_inst.global_position = center + offset
		drone_inst.scale = Vector3(0.6, 0.6, 0.6)
		drone_inst.freeze = false
		drone_inst.collision_layer = 0
		drone_inst.collision_mask = 0
		
		if drone_inst.has_method("set_audio_enabled"):
			drone_inst.set_audio_enabled(true)
		if drone_inst.has_method("set_hover_mode"):
			drone_inst.set_hover_mode(true)
		if drone_inst.has_method("set_input_vector"):
			drone_inst.set_input_vector(Vector4.ZERO)
		
		if drone_inst.has_method("setup_show_lights") and drone_inst.get("show_rig") != null:
			drone_inst.show_rig.configure(i, boid_count, false)
			drone_inst.show_rig.set_low_cost_mode(true)
			drone_inst.show_rig.set_show_lighting_enabled(true)
		if drone_inst.has_method("set_low_detail_visuals"):
			drone_inst.set_low_detail_visuals(true)
		if drone_inst.has_method("refresh_visual_state"):
			drone_inst.refresh_visual_state()
			
		drones.append(drone_inst)

	print("SwarmController: Swarm initialized with ", drones.size(), " follower drones.")
	_rebuild_terrain_exclusions()

func initialize_formation(leader: Node, targets: Array[Vector3], spawn_pos: Vector3 = Vector3(0, 15, 0)):
	leader_drone = leader
	var new_swarm_count = targets.size()
	target_position = spawn_pos
	formation_hold_altitude = spawn_pos.y + 28.0

	active = true
	formation_active = true

	var ground_y = get_terrain_height_at(spawn_pos) + 1.0

	# Case A: First time starting formation (no drones in sky yet) -> Spawn all on ground staging pad
	if drones.size() == 0:
		boid_count = new_swarm_count
		drone_last_input_vectors.resize(new_swarm_count)
		drone_last_input_vectors.fill(Vector4.ZERO)
		drone_terrain_heights.resize(new_swarm_count)
		drone_terrain_heights.fill(0.0)

		var grid_cols = int(ceil(sqrt(float(new_swarm_count))))
		var grid_spacing = 1.8
		var from_ground_pts: Array[Vector3] = []

		for i in range(new_swarm_count):
			var col = i % grid_cols
			var row = i / grid_cols
			var x = (col - grid_cols / 2.0) * grid_spacing
			var z = (row - grid_cols / 2.0) * grid_spacing
			var ground_xz = Vector3(spawn_pos.x + x, 0.0, spawn_pos.z + z)
			var real_ground_y = get_terrain_height_at(ground_xz) + 0.6
			var ground_pos = Vector3(spawn_pos.x + x, real_ground_y, spawn_pos.z + z)
			from_ground_pts.append(ground_pos)

			var drone_inst: RigidBody3D = drone_scene.instantiate()
			drone_inst.low_detail_visuals = true
			drone_inst.audio_enabled = true
			get_parent().add_child(drone_inst)
			drone_inst.global_position = ground_pos
			drone_inst.linear_velocity = Vector3.ZERO
			drone_inst.angular_velocity = Vector3.ZERO
			drone_inst.scale = Vector3(0.55, 0.55, 0.55)
			drone_inst.freeze = true
			drone_inst.collision_layer = 0
			drone_inst.collision_mask = 0

			if drone_inst.has_method("set_audio_enabled"):
				drone_inst.set_audio_enabled(true)
			if drone_inst.has_method("set_hover_mode"):
				drone_inst.set_hover_mode(true)
			if drone_inst.has_method("set_input_vector"):
				drone_inst.set_input_vector(Vector4.ZERO)
			if drone_inst.has_method("setup_show_lights") and drone_inst.get("show_rig") != null:
				drone_inst.show_rig.configure(i, new_swarm_count, false)
				drone_inst.show_rig.set_low_cost_mode(true)
				drone_inst.show_rig.set_show_lighting_enabled(true)
			if drone_inst.has_method("set_low_detail_visuals"):
				drone_inst.set_low_detail_visuals(true)
			if drone_inst.has_method("refresh_visual_state"):
				drone_inst.refresh_visual_state()

			drones.append(drone_inst)

		_start_smooth_transition(from_ground_pts, targets)

	# Case B: Drones ALREADY in mid-air -> Seamlessly transition from current 3D positions!
	else:
		var current_pts: Array[Vector3] = []

		# If new shape needs MORE drones (e.g. 50 -> 120):
		if drones.size() < new_swarm_count:
			var extra_needed = new_swarm_count - drones.size()
			var grid_cols = int(ceil(sqrt(float(extra_needed))))
			var grid_spacing = 1.8

			for d in drones:
				current_pts.append(d.global_position if (d and is_instance_valid(d)) else spawn_pos)

			# Spawn additional drones on ground staging pad to fly up and join the formation
			for i in range(extra_needed):
				var col = i % grid_cols
				var row = i / grid_cols
				var x = (col - grid_cols / 2.0) * grid_spacing
				var z = (row - grid_cols / 2.0) * grid_spacing
				var ground_xz = Vector3(spawn_pos.x + x, 0.0, spawn_pos.z + z)
				var real_ground_y = get_terrain_height_at(ground_xz) + 0.6
				var ground_pos = Vector3(spawn_pos.x + x, real_ground_y, spawn_pos.z + z)
				current_pts.append(ground_pos)

				var drone_inst: RigidBody3D = drone_scene.instantiate()
				drone_inst.low_detail_visuals = true
				drone_inst.audio_enabled = true
				get_parent().add_child(drone_inst)
				drone_inst.global_position = ground_pos
				drone_inst.linear_velocity = Vector3.ZERO
				drone_inst.angular_velocity = Vector3.ZERO
				drone_inst.scale = Vector3(0.55, 0.55, 0.55)
				drone_inst.freeze = true
				drone_inst.collision_layer = 0
				drone_inst.collision_mask = 0

				if drone_inst.has_method("set_audio_enabled"):
					drone_inst.set_audio_enabled(true)
				if drone_inst.has_method("set_hover_mode"):
					drone_inst.set_hover_mode(true)
				if drone_inst.has_method("set_input_vector"):
					drone_inst.set_input_vector(Vector4.ZERO)
				if drone_inst.has_method("setup_show_lights") and drone_inst.get("show_rig") != null:
					drone_inst.show_rig.configure(drones.size(), new_swarm_count, false)
					drone_inst.show_rig.set_low_cost_mode(true)
					drone_inst.show_rig.set_show_lighting_enabled(true)
				if drone_inst.has_method("set_low_detail_visuals"):
					drone_inst.set_low_detail_visuals(true)
				if drone_inst.has_method("refresh_visual_state"):
					drone_inst.refresh_visual_state()

				drones.append(drone_inst)

		# If new shape needs FEWER drones (e.g. 120 -> 50):
		elif drones.size() > new_swarm_count:
			var surplus = drones.size() - new_swarm_count
			for k in range(surplus):
				var extra_drone = drones.pop_back()
				if extra_drone and is_instance_valid(extra_drone):
					extra_drone.queue_free()

			for d in drones:
				current_pts.append(d.global_position if (d and is_instance_valid(d)) else spawn_pos)

		else:
			for d in drones:
				current_pts.append(d.global_position if (d and is_instance_valid(d)) else spawn_pos)

		boid_count = drones.size()
		drone_last_input_vectors.resize(boid_count)
		drone_terrain_heights.resize(boid_count)

		_start_smooth_transition(current_pts, targets)

	_rebuild_terrain_exclusions()

func _start_smooth_transition(from_pts: Array[Vector3], to_targets_raw: Array[Vector3]) -> void:
	is_transitioning = true
	transition_elapsed = 0.0
	formation_transition_duration = 3.2

	var count = min(from_pts.size(), to_targets_raw.size())

	# Calculate absolute sky targets
	var sky_targets: Array[Vector3] = []
	for i in range(to_targets_raw.size()):
		var pt = to_targets_raw[i]
		if pt.y < 5.0:
			pt = Vector3(pt.x, target_position.y + 25.0 + pt.y, pt.z)
		sky_targets.append(pt)

	# SPATIAL NEAREST MATCHING ALGORITHM
	# Pairs each drone to its closest target point in the new shape.
	# Eliminates crossing paths, shape distortion, and geometric degradation!
	var matched_targets = match_drones_to_targets(from_pts, sky_targets)

	start_positions.resize(count)
	target_positions.resize(count)

	for i in range(count):
		start_positions[i] = from_pts[i]
		target_positions[i] = matched_targets[i]

	formation_targets = matched_targets.duplicate()

static func match_drones_to_targets(drone_positions: Array[Vector3], new_targets: Array[Vector3]) -> Array[Vector3]:
	var assigned_targets: Array[Vector3] = []
	assigned_targets.resize(drone_positions.size())

	var available_targets = new_targets.duplicate()
	var used_target_mask: Array[bool] = []
	used_target_mask.resize(available_targets.size())
	used_target_mask.fill(false)

	for i in range(drone_positions.size()):
		var drone_pos = drone_positions[i]
		var best_idx = -1
		var best_dist_sq = 1e12

		for j in range(available_targets.size()):
			if used_target_mask[j]:
				continue
			var dist_sq = drone_pos.distance_squared_to(available_targets[j])
			if dist_sq < best_dist_sq:
				best_dist_sq = dist_sq
				best_idx = j

		if best_idx != -1:
			used_target_mask[best_idx] = true
			assigned_targets[i] = available_targets[best_idx]
		else:
			assigned_targets[i] = available_targets[i % available_targets.size()]

	return assigned_targets

func _rebuild_terrain_exclusions() -> void:
	terrain_exclusions.clear()
	if not is_inside_tree() or get_tree() == null:
		return
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

func _ensure_swarm_audio() -> void:
	if swarm_audio_component == null or not is_instance_valid(swarm_audio_component):
		swarm_audio_component = SwarmAudio.new()
		swarm_audio_component.name = "SwarmAudioComponent"
		add_child(swarm_audio_component)

func _physics_process(delta: float) -> void:
	if not active or drones.size() == 0:
		if swarm_audio_component and is_instance_valid(swarm_audio_component):
			swarm_audio_component.set_swarm_enabled(false)
		return
	if is_inside_tree() and get_tree() and get_tree().paused:
		if swarm_audio_component and is_instance_valid(swarm_audio_component):
			swarm_audio_component.set_swarm_enabled(false)
		return

	# Update Aggregate Swarm Audio Centroid and Speed
	_ensure_swarm_audio()
	var centroid = get_swarm_centroid()
	var avg_vel = Vector3.ZERO
	var valid_c = 0
	for d in drones:
		if d and is_instance_valid(d) and d is RigidBody3D:
			avg_vel += d.linear_velocity
			valid_c += 1
	var avg_speed = (avg_vel / float(valid_c)).length() if valid_c > 0 else 0.0
	if swarm_audio_component:
		swarm_audio_component.set_swarm_enabled(true)
		swarm_audio_component.update_swarm_audio(centroid, avg_speed, drones.size(), delta)

	if formation_active:
		_process_formation(delta)
		return

	update_phase = (update_phase + 1) % update_divisor
	spatial_hash.clear()

	for i in range(drones.size()):
		var d = drones[i]
		if d and is_instance_valid(d) and d.is_inside_tree():
			spatial_hash.insert(i, d.global_position)

	if leader_drone and is_instance_valid(leader_drone) and leader_drone.is_inside_tree():
		target_position = leader_drone.global_position

	for i in range(drones.size()):
		if (i % update_divisor) != update_phase:
			var d_prev = drones[i]
			if d_prev and is_instance_valid(d_prev) and drone_last_input_vectors.size() > i:
				d_prev.set_input_vector(drone_last_input_vectors[i])
			continue

		var drone_inst: RigidBody3D = drones[i]
		if not drone_inst or not is_instance_valid(drone_inst) or not drone_inst.is_inside_tree():
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
			if not other or not is_instance_valid(other) or not other.is_inside_tree():
				continue

			var other_pos: Vector3 = other.global_position
			var diff: Vector3 = pos - other_pos
			var dist: float = diff.length()

			if dist < neighborhood_radius and dist > 0.001:
				neighbor_count += 1
				coh_pos += other_pos
				ali_vel += other.linear_velocity

				if dist < separation_radius:
					var repulsion = (separation_radius - dist) / separation_radius
					sep_force += diff.normalized() * (repulsion * 6.0 / maxf(dist, 0.2))
					sep_count += 1

		var steer_cohesion := Vector3.ZERO
		var steer_alignment := Vector3.ZERO
		var steer_separation := Vector3.ZERO

		if neighbor_count > 0:
			coh_pos /= float(neighbor_count)
			ali_vel /= float(neighbor_count)
			var desired_coh = (coh_pos - pos).normalized() * max_speed
			steer_cohesion = (desired_coh - vel).limit_length(max_force)

			var desired_ali = ali_vel.normalized() * max_speed
			steer_alignment = (desired_ali - vel).limit_length(max_force)

		if sep_count > 0:
			steer_separation = sep_force.limit_length(max_force * 1.5)

		var target_offset = boid_scatter_offsets[i] if i < boid_scatter_offsets.size() else Vector3.ZERO
		var desired_target_pos = target_position + target_offset
		var target_dir = (desired_target_pos - pos)
		var dist_to_target = target_dir.length()
		var steer_target := Vector3.ZERO
		if dist_to_target > 0.3:
			var speed_demand = clampf(dist_to_target * 3.5, min_speed, max_speed * 1.5)
			var desired_target = target_dir.normalized() * speed_demand
			steer_target = (desired_target - vel).limit_length(max_force * 2.0)

		var total_force = steer_separation * 3.0 + steer_cohesion * 0.6 + steer_alignment * 0.5 + steer_target * 2.5
		var desired_velocity = (vel + total_force * delta).limit_length(max_speed * 1.5)

		var ground_clearance: float = 4.0
		var cached_y = drone_terrain_heights[i]
		if update_phase == 0 or cached_y == 0.0:
			cached_y = get_terrain_height_at(pos)
			drone_terrain_heights[i] = cached_y

		var target_y = cached_y + ground_clearance
		if leader_drone and is_instance_valid(leader_drone):
			target_y = max(target_y, leader_drone.global_position.y - 3.0)

		if pos.y < target_y:
			desired_velocity.y = maxf(desired_velocity.y, lerpf(min_speed, max_speed * 0.8, clampf((target_y - pos.y) / 5.0, 0.0, 1.0)))

		drone_inst.linear_velocity = drone_inst.linear_velocity.lerp(desired_velocity, clampf(delta * 9.0, 0.05, 1.0))

		if desired_velocity.length_squared() > 0.5:
			var target_dir_rot = desired_velocity.normalized()
			var current_fwd = -drone_inst.global_transform.basis.z
			var rot_axis = current_fwd.cross(target_dir_rot)
			if rot_axis.length_squared() > 0.001:
				var angle = current_fwd.angle_to(target_dir_rot)
				drone_inst.rotate(rot_axis.normalized(), clampf(angle * delta * 6.0, 0.01, 0.5))

func _process_formation(delta: float) -> void:
	var formation_count: int = min(drones.size(), target_positions.size())
	if formation_count == 0:
		return

	if is_transitioning:
		transition_elapsed += delta
		var t = clampf(transition_elapsed / formation_transition_duration, 0.0, 1.0)
		# Smoothstep S-Curve for ultra-realistic acceleration & deceleration
		var s_t = t * t * (3.0 - 2.0 * t)

		for i in range(formation_count):
			var drone_inst: RigidBody3D = drones[i]
			if not drone_inst or not is_instance_valid(drone_inst):
				continue

			drone_inst.linear_velocity = Vector3.ZERO
			drone_inst.angular_velocity = Vector3.ZERO

			var lerped_pos = start_positions[i].lerp(target_positions[i], s_t)
			drone_inst.global_position = lerped_pos

		if t >= 1.0:
			is_transitioning = false
			# Lock exactly onto target positions to prevent geometric drift
			for i in range(formation_count):
				var drone_inst: RigidBody3D = drones[i]
				if drone_inst and is_instance_valid(drone_inst):
					drone_inst.global_position = target_positions[i]
			play_formation_chime()

	else:
		for i in range(formation_count):
			var drone_inst: RigidBody3D = drones[i]
			if not drone_inst or not is_instance_valid(drone_inst):
				continue

			drone_inst.linear_velocity = Vector3.ZERO
			drone_inst.angular_velocity = Vector3.ZERO
			drone_inst.global_position = target_positions[i]

func get_terrain_height_at(pos: Vector3) -> float:
	if not is_inside_tree():
		return 0.0
	var viewport = get_viewport()
	if not viewport or not viewport.find_world_3d():
		return 0.0
	var space_state = viewport.find_world_3d().direct_space_state
	if not space_state:
		return 0.0
	var from = Vector3(pos.x, 600.0, pos.z)
	var to = Vector3(pos.x, -100.0, pos.z)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1 | 2 | 4
	var hit = space_state.intersect_ray(query)
	if hit and hit.has("position"):
		return hit.position.y
	return 0.0

func get_swarm_centroid() -> Vector3:
	if drones.size() == 0:
		return Vector3.ZERO
	var sum := Vector3.ZERO
	var valid_count := 0
	for d in drones:
		if d and is_instance_valid(d) and d.is_inside_tree():
			sum += d.global_position
			valid_count += 1
	return sum / float(valid_count) if valid_count > 0 else Vector3.ZERO

var chime_player: AudioStreamPlayer = null
static var shared_chime_stream: AudioStreamWAV = null

static func _build_formation_chime_wav() -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = 44100

	var num_samples = int(44100 * 0.45)
	var byte_array = PackedByteArray()
	byte_array.resize(num_samples * 4)

	# Frequencies for C major chord resonance: 523.25 Hz (C5), 659.25 Hz (E5), 783.99 Hz (G5)
	for i in range(num_samples):
		var t = float(i) / 44100.0
		var decay = exp(-7.5 * t)
		var s1 = sin(TAU * 523.25 * t) * 0.35
		var s2 = sin(TAU * 659.25 * t) * 0.30
		var s3 = sin(TAU * 783.99 * t) * 0.25
		var spark = sin(TAU * 1567.98 * t) * 0.10 * exp(-20.0 * t)
		var sample_val = clampf((s1 + s2 + s3 + spark) * decay * 0.6, -0.95, 0.95)
		var int_val = int(sample_val * 32767.0)

		var b0 = int_val & 0xFF
		var b1 = (int_val >> 8) & 0xFF

		var idx = i * 4
		byte_array[idx]     = b0
		byte_array[idx + 1] = b1
		byte_array[idx + 2] = b0
		byte_array[idx + 3] = b1

	wav.data = byte_array
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return wav

func play_formation_chime() -> void:
	if not is_inside_tree():
		return
	if shared_chime_stream == null:
		shared_chime_stream = _build_formation_chime_wav()
	if chime_player == null:
		chime_player = AudioStreamPlayer.new()
		chime_player.name = "FormationChimePlayer"
		chime_player.bus = "Master"
		chime_player.stream = shared_chime_stream
		add_child(chime_player)
	chime_player.pitch_scale = randf_range(0.98, 1.02)
	chime_player.volume_db = -4.0
	chime_player.play()
