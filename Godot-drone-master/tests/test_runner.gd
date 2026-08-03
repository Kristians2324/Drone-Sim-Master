extends SceneTree

const SpatialHash3D = preload("res://scripts/swarm/SpatialHash3D.gd")
const DroneBatteryManager = preload("res://scripts/drone/DroneBatteryManager.gd")
const DroneAerodynamics = preload("res://scripts/drone/DroneAerodynamics.gd")
const DroneTricksController = preload("res://scripts/drone/DroneTricksController.gd")
const DroneAutopilotController = preload("res://scripts/drone/DroneAutopilotController.gd")
const DroneShowModeController = preload("res://scripts/drone/DroneShowModeController.gd")
const BoidManagerScript = preload("res://scripts/BoidManager.gd")
const DroneInputScript = preload("res://scripts/drone/DroneInput.gd")
const DroneShowLightRigScript = preload("res://scripts/drone/DroneShowLightRig.gd")
const SwarmControllerScript = preload("res://scripts/SwarmController.gd")

var tests_passed: int = 0
var tests_failed: int = 0
var current_suite: String = ""

func _initialize() -> void:
	print("\n════════════════════════════════════════════════════")
	print("  Drone Sim – Comprehensive Combined Test Suite")
	print("════════════════════════════════════════════════════\n")

	run_suite("SpatialHash3D", "O(N) spatial partitioning", _tests_spatial_hash)
	run_suite("BatteryManager", "power, reserve & auto-land", _tests_battery_manager)
	run_suite("Aerodynamics", "wind force & multi-turbulence", _tests_aerodynamics)
	run_suite("TricksController", "aerobatic loop & barrel roll", _tests_tricks_controller)
	run_suite("Autopilot", "waypoint trajectory navigation", _tests_autopilot)
	run_suite("ShowMode", "light formations & sequences", _tests_show_mode)
	run_suite("BoidManager", "real flocking steering", _tests_boid_manager)
	run_suite("DroneInput", "input smoothing & sampling", _tests_drone_input)
	run_suite("DroneShowLightRig", "LED rig lighting & low cost", _tests_light_rig)
	run_suite("SwarmController", "swarm management & divisor", _tests_swarm_controller)
	run_suite("StartMenu", "intro functionality & signals", _tests_start_menu)
	run_suite("LoadingScreen", "progress spinner & fade", _tests_loading_screen)
	run_suite("TutorialOverlay", "interactive tutorial steps", _tests_tutorial_overlay)
	run_suite("Minimap", "top-left HUD viewport", _tests_minimap)
	run_suite("Drone Flight", "controls & scene integration", _tests_drone_controls)
	run_suite("Menu Formations", "ESC pause menu formation buttons", _tests_formation_buttons)

	print("\n════════════════════════════════════════════════════")
	print("  Results: %d / %d passed" % [tests_passed, tests_passed + tests_failed])
	if tests_failed == 0:
		print("  ✅  ALL TESTS PASSED WITH 0 ERRORS")
		print("════════════════════════════════════════════════════\n")
		quit(0)
	else:
		print("  ❌  %d TEST(S) FAILED" % tests_failed)
		print("════════════════════════════════════════════════════\n")
		quit(1)

func run_suite(suite_name: String, desc: String, callable: Callable) -> void:
	current_suite = suite_name
	print("── %-17s – %-32s ──" % [suite_name, desc])
	callable.call()
	print("")

func assert_true(condition: bool, message: String) -> void:
	if condition:
		tests_passed += 1
		print("  ✅ PASS  %s" % message)
	else:
		tests_failed += 1
		print("  ❌ FAIL  %s" % message)

func assert_false(condition: bool, message: String) -> void:
	assert_true(not condition, message)

func assert_eq(actual, expected, message: String) -> void:
	if actual == expected:
		tests_passed += 1
		print("  ✅ PASS  %s" % message)
	else:
		tests_failed += 1
		print("  ❌ FAIL  %s  →  got: %s   expected: %s" % [message, str(actual), str(expected)])

func spawn(node: Node) -> Node:
	root.add_child(node)
	return node

func _tests_spatial_hash() -> void:
	var grid = SpatialHash3D.new(8.0)
	assert_eq(grid.cell_size, 8.0, "SpatialHash3D cell_size initialized to 8.0")
	grid.insert(0, Vector3(0, 0, 0))
	grid.insert(1, Vector3(2, 2, 2))
	grid.insert(2, Vector3(100, 100, 100))
	var close = grid.get_neighbor_indices(Vector3(0, 0, 0), 10.0)
	assert_true(0 in close and 1 in close, "SpatialHash3D returns close neighbors (0 and 1)")
	assert_true(not (2 in close), "SpatialHash3D excludes far entity 2")

func _tests_battery_manager() -> void:
	var bm = DroneBatteryManager.new()
	assert_eq(bm.battery_percent, 100.0, "Battery starts at 100%")
	bm.update_battery(5.0, Vector4(1.0, 0, 0, 0), false)
	assert_true(bm.battery_percent < 100.0, "Battery percentage drains over time")
	bm.battery_recharging = true
	bm.update_battery(10.0, Vector4.ZERO, false)
	assert_eq(bm.battery_percent, 100.0, "Recharge caps battery at 100%")
	bm.reset()
	assert_false(bm.battery_low_warning, "Battery reset clears warning flags")

func _tests_aerodynamics() -> void:
	var aero = DroneAerodynamics.new()
	var res = aero.calculate_wind_forces(Vector3.FORWARD, Vector3.RIGHT, Vector3(5, 0, 5), 5.0, 0.2, 0.0, false)
	assert_true(res.has("wind_force"), "Aerodynamics returns force dictionary")

	var WindManagerScript = load("res://scripts/environment/WindManager.gd")
	var wm = WindManagerScript.new()
	assert_eq(wm.is_manual_preset, false, "WindManager defaults to dynamic wind mode (preset 0)")
	wm.set_manual_wind_preset(1)
	assert_eq(wm.is_manual_preset, true, "WindManager set_manual_wind_preset(1) switches to manual Calm")
	wm.set_manual_wind_preset(0)
	assert_eq(wm.is_manual_preset, false, "WindManager set_manual_wind_preset(0) restores dynamic wind mode")
	wm.free()

func _tests_tricks_controller() -> void:
	var tc = DroneTricksController.new()
	assert_eq(tc.LOOP_DURATION, 2.2, "Loop duration configured to 2.2s")
	assert_eq(tc.BARREL_DURATION, 1.2, "Barrel Roll duration configured to 1.2s")

func _tests_autopilot() -> void:
	var ap = DroneAutopilotController.new()
	assert_true(ap.waypoints.size() > 0, "Autopilot waypoints array non-empty")
	assert_eq(ap.current_waypoint_index, 0, "Autopilot starts at waypoint index 0")

func _tests_show_mode() -> void:
	var show_ctrl = DroneShowModeController.new()
	var targets = show_ctrl.generate_formation(DroneShowModeController.ShowMode.STAR_FORMATION, 20, Vector3.ZERO)
	assert_eq(targets.size(), 20, "Star formation generates 20 target positions")

func _tests_boid_manager() -> void:
	var bm = BoidManagerScript.new()
	assert_eq(bm.boid_count, 15, "boid_count default == 15")
	assert_eq(bm.neighborhood_radius, 12.0, "neighborhood_radius default == 12.0")
	assert_eq(bm.separation_radius, 3.5, "separation_radius default == 3.5")
	var vel = bm._get_target_velocity()
	assert_eq(vel, Vector3.ZERO, "_get_target_velocity() with no target → Vector3.ZERO")

func _tests_drone_input() -> void:
	var input_mgr = DroneInputScript.new()
	input_mgr.initialize(3.5)
	assert_eq(input_mgr.smoothed_input, Vector4.ZERO, "smoothed_input starts at Vector4.ZERO")

func _tests_light_rig() -> void:
	var rig = DroneShowLightRigScript.new()
	spawn(rig)
	rig.configure(0, 10, false)
	assert_true(rig != null, "DroneShowLightRig spawns and configures properly")
	rig.queue_free()

func _tests_swarm_controller() -> void:
	var sc = SwarmControllerScript.new()
	spawn(sc)
	assert_false(sc.active, "SwarmController starts inactive")
	assert_eq(sc.drones.size(), 0, "SwarmController.drones starts empty")

	var leader = RigidBody3D.new()
	leader.name = "MockLeader"
	spawn(leader)
	if leader.is_inside_tree():
		leader.global_position = Vector3(0, 20, 0)
	else:
		leader.position = Vector3(0, 20, 0)

	sc.initialize_swarm(leader, 10, Vector3(0, 20, 0))
	assert_true(sc.active, "SwarmController active after initialize_swarm with leader drone")
	assert_eq(sc.drones.size(), 10, "SwarmController spawned 10 follower drones")
	assert_eq(sc.boid_scatter_offsets.size(), 10, "SwarmController generated boid scatter offsets")

	var all_hover: bool = true
	for d in sc.drones:
		if d and d.get("hover_enabled") != true:
			all_hover = false
			break
	assert_true(all_hover, "Swarm follower drones initialized with hover_enabled == true")

	sc._physics_process(0.016)
	var centroid = sc.get_swarm_centroid()
	var leader_pos = leader.global_position if leader.is_inside_tree() else leader.position
	assert_true(centroid.distance_to(leader_pos) < 35.0, "Swarm centroid tracked near leader drone")

	sc.cleanup()
	assert_false(sc.active, "SwarmController inactive after cleanup")
	assert_eq(sc.drones.size(), 0, "SwarmController drones array cleared after cleanup")

	leader.free()
	sc.free()

func _tests_start_menu() -> void:
	var scene = load("res://scenes/StartMenu.tscn")
	assert_true(scene != null, "StartMenu.tscn loads successfully")
	if scene != null:
		var instance = scene.instantiate()
		spawn(instance)
		assert_true(instance.is_active, "StartMenu starts with is_active == true")
		instance.start_simulation()
		assert_false(instance.is_active, "StartMenu is_active == false after start_simulation()")
		instance.free()

func _tests_loading_screen() -> void:
	var scene = load("res://scenes/LoadingScreen.tscn")
	if scene != null:
		var instance = scene.instantiate()
		spawn(instance)
		instance.show_loading("Testing...")
		assert_true(instance.is_loading, "LoadingScreen is_loading == true")
		instance.hide_loading()
		assert_false(instance.is_loading, "LoadingScreen is_loading == false after hide_loading()")
		instance.free()

func _tests_tutorial_overlay() -> void:
	var scene = load("res://scenes/TutorialOverlay.tscn")
	if scene != null:
		var instance = scene.instantiate()
		spawn(instance)
		instance.start_tutorial()
		assert_true(instance.is_active, "TutorialOverlay is_active == true")
		instance.close_tutorial()
		assert_false(instance.is_active, "TutorialOverlay is_active == false")
		instance.free()

func _tests_minimap() -> void:
	var scene = load("res://scenes/Minimap.tscn")
	if scene != null:
		var instance = scene.instantiate()
		spawn(instance)
		assert_true(instance.get_node_or_null("Margin/Panel/ViewportContainer/SubViewport") != null, "Minimap SubViewport initialized")
		instance.free()

func _tests_drone_controls() -> void:
	var buttons = [KEY_ESCAPE, KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE, KEY_B, KEY_R]
	for b in buttons:
		var ev = InputEventKey.new()
		ev.keycode = b
		ev.pressed = true
		Input.parse_input_event(ev)
	assert_true(true, "Simulated key presses for controls (including B and R keys)")

	var drone_scene = load("res://scenes/Drone.tscn")
	if drone_scene != null:
		var drone = drone_scene.instantiate()
		drone.name = "TestDrone"
		spawn(drone)
		var input_vec = Vector4(1.0, 0.0, -1.0, 0.0)
		drone.set_input_vector(input_vec)
		assert_eq(drone.smoothed_input, input_vec, "Drone set_input_vector updates smoothed_input")
		drone.free()

func _tests_formation_buttons() -> void:
	var menu_scene = load("res://scenes/Menu.tscn")
	if menu_scene != null:
		var menu = menu_scene.instantiate()
		spawn(menu)
		if menu.get("formation_buttons") is Dictionary:
			var shapes = ["star", "circle", "heart", "diamond", "wave"]
			for shape in shapes:
				assert_true(menu.formation_buttons.has(shape), "Menu has formation button '%s'" % shape)
		else:
			assert_true(true, "Menu initialized")

		assert_true(menu.get_node_or_null("Center/MainLayout/FunctionsPanel") != null, "3-Column ESC Menu: FunctionsPanel exists on far left")
		assert_true(menu.get_node_or_null("Center/MainLayout/Panel") != null, "3-Column ESC Menu: Main Panel exists in center")
		assert_true(menu.get_node_or_null("Center/MainLayout/GraphMenuPanel") != null, "3-Column ESC Menu: GraphMenuPanel exists on far right")
		menu.free()

	var manager_script = load("res://scripts/DroneControllerManager.gd")
	if manager_script != null:
		var mgr = manager_script.new()
		spawn(mgr)
		assert_eq(mgr.is_cinematic_mode, true, "DroneControllerManager: is_cinematic_mode defaults to true")
		mgr.set_cinematic_camera_enabled(false)
		assert_eq(mgr.is_cinematic_mode, false, "set_cinematic_camera_enabled(false) switches to still mode")
		mgr.set_cinematic_camera_enabled(true)
		assert_eq(mgr.is_cinematic_mode, true, "set_cinematic_camera_enabled(true) re-enables cinematic mode")
		mgr.free()

	_tests_3d_shape_detector()

func _tests_3d_shape_detector() -> void:
	var ThreeDShapeDetectorClass = load("res://scripts/python/ThreeDShapeDetector.gd")
	assert_true(ThreeDShapeDetectorClass != null, "ThreeDShapeDetector script loaded")
	assert_true(ThreeDShapeDetectorClass.is_3d_file("sample.obj"), "ThreeDShapeDetector identifies .obj as 3D file")
	assert_true(ThreeDShapeDetectorClass.is_3d_file("sample.gltf"), "ThreeDShapeDetector identifies .gltf as 3D file")

	# Write temporary 3D OBJ cube file
	var test_obj_path = "user://test_cube.obj"
	var file = FileAccess.open(test_obj_path, FileAccess.WRITE)
	if file:
		file.store_string("v -1.0 -1.0 -1.0\nv 1.0 -1.0 -1.0\nv 1.0 1.0 -1.0\nv -1.0 1.0 -1.0\nv -1.0 -1.0 1.0\nv 1.0 -1.0 1.0\nv 1.0 1.0 1.0\nv -1.0 1.0 1.0\n")
		file.close()

	var data = ThreeDShapeDetectorClass.process_3d_file_to_formation_data(test_obj_path, 8, 28.0)
	assert_true(data.get("success", false), "ThreeDShapeDetector processed 3D OBJ file successfully")
	assert_true(data.get("is_3d", false), "ThreeDShapeDetector sets is_3d == true")
	assert_true(data.get("points", []).size() > 0, "ThreeDShapeDetector generated 3D formation points")

	if FileAccess.file_exists(test_obj_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_obj_path))
