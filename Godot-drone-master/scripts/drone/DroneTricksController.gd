class_name DroneTricksController
extends RefCounted

const LOOP_DURATION = 2.2
const BARREL_DURATION = 1.2

var trick_time: float = 0.0
var loop_start_pos: Vector3 = Vector3.ZERO
var loop_center: Vector3 = Vector3.ZERO
var loop_forward: Vector3 = Vector3.ZERO
var loop_up: Vector3 = Vector3.ZERO
var loop_radius: float = 20.0

var barrel_start_pos: Vector3 = Vector3.ZERO
var barrel_forward: Vector3 = Vector3.ZERO
var barrel_left: Vector3 = Vector3.ZERO
var barrel_up: Vector3 = Vector3.ZERO
var barrel_start_basis: Basis = Basis.IDENTITY
var barrel_speed: float = 20.0
var barrel_radius: float = 2.0

func start_loop(drone: RigidBody3D) -> void:
	if not is_instance_valid(drone): return
	trick_time = 0.0
	loop_start_pos = drone.global_position
	loop_forward = -drone.global_transform.basis.z.normalized()
	loop_up = drone.global_transform.basis.y.normalized()
	loop_radius = 20.0
	loop_center = loop_start_pos + loop_up * loop_radius
	if "audio_component" in drone and drone.audio_component and drone.audio_component.has_method("play_trick_whoosh"):
		drone.audio_component.play_trick_whoosh()

func process_loop(delta: float, drone: RigidBody3D) -> bool:
	if not is_instance_valid(drone): return false
	trick_time += delta
	var progress = trick_time / LOOP_DURATION
	if progress >= 1.0:
		drone.global_position = loop_start_pos
		drone.rotation = Vector3.ZERO
		drone.linear_velocity = Vector3.ZERO
		drone.angular_velocity = Vector3.ZERO
		return false # Finished

	var angle = progress * TAU - (PI / 2.0)
	var pos = loop_center + loop_forward * (cos(angle) * loop_radius) + loop_up * (sin(angle) * loop_radius)
	var tangent = (-loop_forward * sin(angle) + loop_up * cos(angle)).normalized()

	drone.global_position = pos
	var new_transform = drone.global_transform
	new_transform.basis = Basis.looking_at(tangent, Vector3.UP)
	drone.global_transform = new_transform
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	return true # Still running

func start_barrel_roll(drone: RigidBody3D) -> void:
	if not is_instance_valid(drone): return
	trick_time = 0.0
	barrel_start_pos = drone.global_position
	barrel_start_basis = drone.global_transform.basis
	barrel_forward = -drone.global_transform.basis.z.normalized()
	barrel_left = -drone.global_transform.basis.x.normalized()
	barrel_up = drone.global_transform.basis.y.normalized()
	if "audio_component" in drone and drone.audio_component and drone.audio_component.has_method("play_trick_whoosh"):
		drone.audio_component.play_trick_whoosh()

func process_barrel_roll(delta: float, drone: RigidBody3D) -> bool:
	if not is_instance_valid(drone): return false
	trick_time += delta
	var progress = trick_time / BARREL_DURATION
	if progress >= 1.0:
		drone.global_transform.basis = barrel_start_basis
		drone.linear_velocity = Vector3.ZERO
		drone.angular_velocity = Vector3.ZERO
		return false # Finished

	var roll_angle = progress * TAU
	var forward_progress = barrel_forward * (barrel_speed * trick_time)
	var corkscrew_offset = barrel_left * (sin(roll_angle) * barrel_radius) + barrel_up * ((1.0 - cos(roll_angle)) * barrel_radius)

	drone.global_position = barrel_start_pos + forward_progress + corkscrew_offset
	var rotated_basis = barrel_start_basis.rotated(barrel_forward, roll_angle)
	var new_transform = drone.global_transform
	new_transform.basis = rotated_basis
	drone.global_transform = new_transform
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	return true # Still running
