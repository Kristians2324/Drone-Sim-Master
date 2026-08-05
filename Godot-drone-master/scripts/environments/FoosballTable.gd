class_name FoosballTable
extends EnvironmentObject

func setup_object():
	object_name = "Foosball Table"
	var model = preload("res://FooslTable.gltf").instantiate()
	add_child(model)
	
	_create_exact_collision(model)

static func _safe_relative_transform(parent: Node3D, child: Node3D) -> Transform3D:
	if not parent or not child or parent == child:
		return Transform3D.IDENTITY
	var xform := Transform3D.IDENTITY
	var curr: Node = child
	while curr and curr != parent and curr is Node3D:
		xform = (curr as Node3D).transform * xform
		curr = curr.get_parent()
	return xform

func _create_exact_collision(node: Node3D) -> void:
	var static_body := StaticBody3D.new()
	static_body.name = "FoosballTableCollision"
	node.add_child(static_body)
	
	var meshes: Array[MeshInstance3D] = []
	_find_meshes(node, meshes)
	for m in meshes:
		if m.mesh:
			var shape = m.mesh.create_trimesh_shape()
			if shape:
				var col_shape := CollisionShape3D.new()
				col_shape.shape = shape
				col_shape.transform = _safe_relative_transform(node, m)
				static_body.add_child(col_shape)

func _find_meshes(n: Node, list: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		list.append(n as MeshInstance3D)
	for child in n.get_children():
		_find_meshes(child, list)
