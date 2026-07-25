extends RefCounted
class_name DroneSystemFacade

var controller_manager: Node3D

func _init(manager: Node3D) -> void:
	controller_manager = manager

func get_drone() -> RigidBody3D:
	return controller_manager.get_drone() if controller_manager and controller_manager.has_method("get_drone") else null

func toggle_hover() -> void:
	var drone = get_drone()
	if drone and drone.has_method("set_hover_mode"):
		drone.set_hover_mode(!drone.hover_enabled)

func toggle_autopilot() -> void:
	if controller_manager and controller_manager.has_method("toggle_autopilot"):
		controller_manager.toggle_autopilot()

func select_formation(formation_name: String) -> void:
	if controller_manager and controller_manager.has_method("select_show_shape"):
		controller_manager.select_show_shape(formation_name)

func restart_level() -> void:
	if controller_manager and controller_manager.has_method("restart_simulation"):
		controller_manager.restart_simulation()
