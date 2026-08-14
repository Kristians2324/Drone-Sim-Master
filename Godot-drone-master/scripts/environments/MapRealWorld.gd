## MapRealWorld.gd
## Real-world Pattaya 3D terrain via Google Photorealistic 3D Tiles (Cesium ion).
class_name MapRealWorld
extends BaseEnvironment

## 0 = Day, 1 = Night
@export_enum("Day", "Night") var time_of_day: int = 0

## 0 = Clear, 1 = Cloudy, 2 = Rainy
@export_enum("Clear", "Cloudy", "Rainy") var weather: int = 0

## Miniature tile scale (e.g. 0.05 = 1:20 scale, 0.01 = 1:100 tabletop scale)
@export var mini_scale: float = 0.05

## 3D position offset in Godot meters
@export var tile_offset: Vector3 = Vector3.ZERO

## Rotation around Y axis in degrees
@export var tile_rotation_y: float = 0.0

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

	# Lower safety floor so real-world 3D Cesium mesh collision is used without an artificial invisible barrier
	var safety_floor = get_node_or_null("UniversalSafetyFloor")
	if safety_floor:
		safety_floor.position.y = -500.0

	# 2. Build Cesium georeference + World Terrain tileset + Satellite Overlay
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

	# Set Cartographic Origin (Pattaya or dynamic user coordinates from ThemeManager)
	var lat: float = 12.9236
	var lng: float = 100.8825
	var theme_mgr = get_node_or_null("/root/ThemeManager")
	if theme_mgr and "user_lat" in theme_mgr and "user_lng" in theme_mgr:
		lat = theme_mgr.user_lat
		lng = theme_mgr.user_lng

	if "origin_type" in geo:
		geo.origin_type = 0 # CartographicOrigin
	if "longitude" in geo: geo.longitude = lng
	if "latitude"  in geo: geo.latitude  = lat
	if "altitude"  in geo: geo.altitude  = 0.0

	# Scale & Transform Cesium terrain
	geo.position = tile_offset
	geo.rotation_degrees.y = tile_rotation_y
	geo.scale = Vector3(mini_scale, mini_scale, mini_scale)

	# Add CesiumGeoreference to tree (it automatically maintains the local ENU->Godot orientation)
	add_child(geo)
	geo_node = geo

	# Cesium3DTileset — Cesium World Terrain (Asset 1)
	var tileset = ClassDB.instantiate("Cesium3DTileset")
	if tileset == null:
		print("MapRealWorld WARNING: Failed to instantiate Cesium3DTileset.")
		return

	tileset.name = "Cesium3DTileset"
	if "ion_asset_id" in tileset: tileset.ion_asset_id = 1
	
	if "maximum_screen_space_error" in tileset:
		tileset.maximum_screen_space_error = 8.0
	
	if "preload_ancestors" in tileset:
		tileset.preload_ancestors = false
	if "preload_siblings" in tileset:
		tileset.preload_siblings = false
	if "forbid_holes" in tileset:
		tileset.forbid_holes = false
	if "loading_descendant_limit" in tileset:
		tileset.loading_descendant_limit = 2

	if "create_physics_meshes" in tileset:
		tileset.create_physics_meshes = true
	if "createPhysicsMeshes" in tileset:
		tileset.createPhysicsMeshes = true

	tileset.transform = Transform3D.IDENTITY

	geo.add_child(tileset)
	tileset_node = tileset

	# Attach Bing Maps Aerial Imagery (Asset 2) for satellite photo textures
	if ClassDB.class_exists("CesiumIonRasterOverlay"):
		var overlay = ClassDB.instantiate("CesiumIonRasterOverlay")
		overlay.name = "BingMapsOverlay"
		if "asset_id" in overlay:
			overlay.asset_id = 2
		tileset.add_child(overlay)

	print("MapRealWorld SUCCESS: Cesium 3D World Terrain + Satellite Overlay initialized flat on ground plane.")

func _process(_delta: float) -> void:
	if tileset_node != null and geo_node != null:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			cam.near = 0.1
			cam.far = 3500.0

			if geo_node.has_method("get_tx_engine_to_ecef") and tileset_node.has_method("update_tileset"):
				var engine_to_ecef: Transform3D = geo_node.get_tx_engine_to_ecef()
				var ecef_origin := Vector3(geo_node.ecefX, geo_node.ecefY, geo_node.ecefZ)
				var camera_xform: Transform3D = engine_to_ecef * cam.global_transform
				camera_xform.origin += ecef_origin
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
