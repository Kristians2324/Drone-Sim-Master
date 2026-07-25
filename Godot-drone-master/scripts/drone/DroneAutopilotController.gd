class_name DroneAutopilotController
extends RefCounted

var waypoints: Array[Vector3] = [
	Vector3(0, 15, 0),
	Vector3(120, 25, -120),
	Vector3(250, 45, -50),
	Vector3(150, 30, 150),
	Vector3(-100, 25, 200),
	Vector3(-250, 35, 50),
	Vector3(-150, 20, -150)
]
var current_waypoint_index: int = 0
var autopilot_speed: float = 22.0
var waypoint_reach_distance: float = 12.0

func process_autopilot(delta: float, drone: RigidBody3D) -> void:
	if not is_instance_valid(drone): return
	if waypoints.is_empty(): return

	var target = waypoints[current_waypoint_index]
	var dir = target - drone.global_position

	if dir.length() < waypoint_reach_distance:
		current_waypoint_index = (current_waypoint_index + 1) % waypoints.size()
		target = waypoints[current_waypoint_index]
		dir = target - drone.global_position

	var move_dir = dir.normalized()
	drone.linear_velocity = drone.linear_velocity.lerp(move_dir * autopilot_speed, delta * 3.0)

	var target_basis = Basis.looking_at(move_dir, Vector3.UP)
	drone.global_transform.basis = drone.global_transform.basis.slerp(target_basis, delta * 4.0)

func reset() -> void:
	current_waypoint_index = 0
