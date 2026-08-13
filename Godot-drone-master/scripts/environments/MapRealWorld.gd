## MapRealWorld.gd
## Real-world Pattaya 3D terrain via Google Photorealistic 3D Tiles (Cesium ion).
class_name MapRealWorld
extends BaseEnvironment

## 0 = Day, 1 = Night
@export_enum("Day", "Night") var time_of_day: int = 0

## 0 = Clear, 1 = Cloudy, 2 = Rainy
@export_enum("Clear", "Cloudy", "Rainy") var weather: int = 0

var geo_node: Node3D = null
var tileset_node: Node = null

func setup_environment() -> void:
	# 1. Sky & Lighting
	var env_scene: Node3D
	if time_of_day == 1:
		env_scene = load("res://scenes/Environment_Night.tscn").instantiate()
	else:
		env_scene = load("res://scenes/Environment.tscn").instantiate()
	add_child(env_scene)
	_apply_weather(env_scene)

	# 2. Build Cesium georeference + tileset
	_build_cesium_terrain()

func _build_cesium_terrain() -> void:
	if not ClassDB.class_exists("CesiumGeoreference") or not ClassDB.class_exists("Cesium3DTileset"):
		print("MapRealWorld WARNING: Cesium plugin classes not registered in ClassDB.")
		return

	# CesiumGeoreference — anchors Pattaya (12.9236° N, 100.8825° E) flat to Godot XZ ground
	var geo = ClassDB.instantiate("CesiumGeoreference")
	if geo == null:
		print("MapRealWorld WARNING: Failed to instantiate CesiumGeoreference.")
		return

	geo.name = "CesiumGeoreference"

	# Set Cartographic Origin to Pattaya
	if "origin_type" in geo:
		geo.origin_type = 0 # CartographicOrigin
	if "longitude" in geo: geo.longitude = 100.8825
	if "latitude"  in geo: geo.latitude  = 12.9236
	if "height"    in geo: geo.height    = 0.0

	# Zero rotation: CartographicOrigin aligns ground normal to Godot +Y UP (flat ground plane)
	geo.rotation_degrees = Vector3.ZERO
	add_child(geo)
	geo_node = geo

	# Cesium3DTileset — Google Photorealistic 3D Tiles
	var tileset = ClassDB.instantiate("Cesium3DTileset")
	if tileset == null:
		print("MapRealWorld WARNING: Failed to instantiate Cesium3DTileset.")
		return

	tileset.name = "Cesium3DTileset"
	if "ion_asset_id" in tileset: tileset.ion_asset_id = 2275207
	
	if "maximum_screen_space_error" in tileset:
		tileset.maximum_screen_space_error = 16.0
	
	if "create_physics_meshes" in tileset:
		tileset.create_physics_meshes = true
	if "createPhysicsMeshes" in tileset:
		tileset.createPhysicsMeshes = true

	tileset.rotation_degrees = Vector3.ZERO

	geo.add_child(tileset)
	tileset_node = tileset
	print("MapRealWorld SUCCESS: Cesium 3D Tileset initialized flat on ground plane.")

func _process(_delta: float) -> void:
	if tileset_node != null and geo_node != null:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			cam.near = 0.1
			cam.far = 30000.0

			if geo_node.has_method("get_tx_engine_to_ecef") and tileset_node.has_method("update_tileset"):
				# Correct camera basis X-axis mirroring for Cesium Native frustum culler
				var cam_xform: Transform3D = cam.global_transform
				cam_xform.basis.x = -cam_xform.basis.x
				
				var camera_xform: Transform3D = geo_node.get_tx_engine_to_ecef() * cam_xform
				tileset_node.update_tileset(camera_xform)

func _apply_weather(env_scene: Node3D) -> void:
	var world_env := env_scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env == null or world_env.environment == null:
		return
	var env: Environment = world_env.environment.duplicate()
	world_env.environment = env
	var base_sun := 2.6 if time_of_day == 0 else 0.5
	match weather:
		0: # Clear
			env.volumetric_fog_enabled = false
			env.fog_enabled = false
			env.glow_intensity = 0.85
			_set_sun(env_scene, base_sun)
		1: # Cloudy
			env.fog_enabled = true
			env.fog_density = 0.003
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = 0.008
			env.glow_intensity = 0.4
			_set_sun(env_scene, base_sun * 0.5)
		2: # Rainy
			env.fog_enabled = true
			env.fog_density = 0.008
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = 0.04
			env.glow_enabled = false
			_set_sun(env_scene, base_sun * 0.22)

func _set_sun(env_scene: Node3D, energy: float) -> void:
	var sun := env_scene.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sun:
		sun.light_energy = energy
