class_name DronePropellerController
extends RefCounted

var prop_rotation_angle: float = 0.0

func update_propellers(delta: float, throttle_input: float, propeller_datas: Array[Dictionary], legacy_props_node: Node) -> void:
	var prop_speed = 30.0 + (throttle_input * 60.0)
	prop_rotation_angle = fmod(prop_rotation_angle + delta * prop_speed, PI * 2.0)

	for data in propeller_datas:
		var prop = data.get("node")
		if is_instance_valid(prop):
			var orig: Transform3D = data.get("original_transform", Transform3D.IDENTITY)
			var t := orig
			t.basis = orig.basis.rotated(Vector3.UP, prop_rotation_angle)
			prop.transform = t

	if legacy_props_node and is_instance_valid(legacy_props_node):
		for prop in legacy_props_node.get_children():
			if prop is Node3D:
				prop.rotate_y(delta * prop_speed)
