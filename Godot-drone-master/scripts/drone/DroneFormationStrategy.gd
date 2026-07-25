extends RefCounted
class_name DroneFormationStrategy

func generate_formation(count: int, center: Vector3, radius: float) -> Array[Vector3]:
	return []

class StarFormationStrategy extends DroneFormationStrategy:
	func generate_formation(count: int, center: Vector3, radius: float) -> Array[Vector3]:
		var points: Array[Vector3] = []
		var total: int = max(count - 2, 18) if count >= 20 else count
		var outer_r: float = radius
		var inner_r: float = radius * 0.45
		for i in range(total):
			var a: float = TAU * float(i) / float(total)
			var use_outer: bool = (i % 2) == 0
			var r: float = outer_r if use_outer else inner_r
			points.append(center + Vector3(cos(a) * r, 0.0, sin(a) * r))
		if count >= 20:
			points.append(center)
			points.append(center + Vector3(0.0, 0.0, outer_r * 0.25))
		return points

class CircleFormationStrategy extends DroneFormationStrategy:
	func generate_formation(count: int, center: Vector3, radius: float) -> Array[Vector3]:
		var points: Array[Vector3] = []
		var total: int = max(count, 24)
		for i in range(total):
			var a: float = TAU * float(i) / float(total)
			points.append(center + Vector3(cos(a) * radius, 0.0, sin(a) * radius))
		return points

class HeartFormationStrategy extends DroneFormationStrategy:
	func generate_formation(count: int, center: Vector3, _radius: float) -> Array[Vector3]:
		var points: Array[Vector3] = []
		var total: int = max(count, 24)
		for i in range(total):
			var t: float = TAU * float(i) / float(total)
			var x: float = 16.0 * pow(sin(t), 3)
			var z: float = 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
			points.append(center + Vector3(x, 0.0, z) * 1.3)
		return points

class DiamondFormationStrategy extends DroneFormationStrategy:
	func generate_formation(count: int, center: Vector3, radius: float) -> Array[Vector3]:
		var points: Array[Vector3] = []
		var total: int = max(count, 24)
		var outer_r: float = radius
		for i in range(total):
			var t: float = float(i) / float(total)
			var scaled: float = t * 4.0
			var side: int = int(floor(scaled))
			var u: float = scaled - float(side)
			var p: Vector3 = Vector3.ZERO
			if side == 0:
				p = Vector3(lerp(0.0, outer_r, u), 0.0, lerp(0.0, outer_r, u))
			elif side == 1:
				p = Vector3(lerp(outer_r, 0.0, u), 0.0, lerp(outer_r, -outer_r, u))
			elif side == 2:
				p = Vector3(lerp(0.0, -outer_r, u), 0.0, lerp(-outer_r, outer_r, u))
			else:
				p = Vector3(lerp(-outer_r, 0.0, u), 0.0, lerp(outer_r, 0.0, u))
			points.append(center + p)
		return points

class WaveFormationStrategy extends DroneFormationStrategy:
	func generate_formation(count: int, center: Vector3, radius: float) -> Array[Vector3]:
		var points: Array[Vector3] = []
		var total: int = max(count, 24)
		var outer_r: float = radius
		for i in range(total):
			var s: float = float(i) / float(total - 1)
			var x: float = lerp(-outer_r, outer_r, s)
			var y: float = sin(s * TAU * 2.0) * 8.0
			var z: float = cos(s * TAU * 3.0) * 6.0
			points.append(center + Vector3(x, y, z))
		return points
