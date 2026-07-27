class_name BaseEnvironment
extends Node3D

# Common objects that can be added to any environment
var foosball_table: FoosballTable = null

func _ready():
	_ensure_global_floor_collision()
	setup_environment()

func _ensure_global_floor_collision():
	if get_node_or_null("UniversalSafetyFloor") != null:
		return
	var floor_body := StaticBody3D.new()
	floor_body.name = "UniversalSafetyFloor"
	floor_body.collision_layer = 3 # Layer 1 + Layer 2
	floor_body.collision_mask = 3
	floor_body.position = Vector3(0, -0.1, 0)
	
	var col_shape := CollisionShape3D.new()
	var plane_shape := WorldBoundaryShape3D.new()
	col_shape.shape = plane_shape
	floor_body.add_child(col_shape)
	add_child(floor_body)

func setup_environment():
	# To be overridden by subclasses
	pass

func add_foosball_table(pos: Vector3, rot: Vector3 = Vector3.ZERO, sca: Vector3 = Vector3.ONE):
	var obj = FoosballTable.new()
	obj.position = pos
	obj.rotation_degrees = rot
	obj.scale = sca
	add_child(obj)
	return obj

func add_charging_station(pos: Vector3, rot: Vector3 = Vector3.ZERO, sca: Vector3 = Vector3.ONE):
	var obj = ChargingStation.new()
	obj.position = pos
	obj.rotation_degrees = rot
	obj.scale = sca
	return obj
