class_name SpatialHash3D
extends RefCounted

var cell_size: float = 8.0
var _grid: Dictionary = {}

func _init(p_cell_size: float = 8.0) -> void:
	cell_size = maxf(p_cell_size, 0.1)

func clear() -> void:
	_grid.clear()

func _get_cell_key(pos: Vector3) -> Vector3i:
	return Vector3i(
		int(floor(pos.x / cell_size)),
		int(floor(pos.y / cell_size)),
		int(floor(pos.z / cell_size))
	)

func insert(index: int, pos: Vector3) -> void:
	var key := _get_cell_key(pos)
	if not _grid.has(key):
		_grid[key] = []
	(_grid[key] as Array).append(index)

func get_neighbor_indices(pos: Vector3, radius: float) -> Array[int]:
	var result: Array[int] = []
	var min_cell := _get_cell_key(pos - Vector3(radius, radius, radius))
	var max_cell := _get_cell_key(pos + Vector3(radius, radius, radius))

	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			for z in range(min_cell.z, max_cell.z + 1):
				var key := Vector3i(x, y, z)
				if _grid.has(key):
					for idx in (_grid[key] as Array):
						result.append(idx)
	return result
