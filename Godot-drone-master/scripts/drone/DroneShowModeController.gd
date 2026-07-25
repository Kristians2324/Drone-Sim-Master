extends Node3D

const DroneFormationStrategy = preload("res://scripts/drone/DroneFormationStrategy.gd")

enum ShowMode { NONE, STAR_FORMATION, CIRCLE, HEART, DIAMOND, WAVE }

var show_target_positions: Array[Vector3] = []
var show_center: Vector3 = Vector3.ZERO
var show_formation_radius: float = 28.0

var strategies: Dictionary = {}

func _init() -> void:
	strategies[ShowMode.STAR_FORMATION] = DroneFormationStrategy.StarFormationStrategy.new()
	strategies[ShowMode.CIRCLE] = DroneFormationStrategy.CircleFormationStrategy.new()
	strategies[ShowMode.HEART] = DroneFormationStrategy.HeartFormationStrategy.new()
	strategies[ShowMode.DIAMOND] = DroneFormationStrategy.DiamondFormationStrategy.new()
	strategies[ShowMode.WAVE] = DroneFormationStrategy.WaveFormationStrategy.new()

func generate_formation(mode: int, count: int, center: Vector3) -> Array[Vector3]:
	show_center = center
	show_target_positions.clear()
	var strategy: DroneFormationStrategy = strategies.get(mode, strategies[ShowMode.STAR_FORMATION])
	show_target_positions = strategy.generate_formation(count, center, show_formation_radius)
	return show_target_positions
