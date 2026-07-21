extends SceneTree

func _init():
	var actions = {
		"throttle_up": KEY_SPACE,
		"throttle_down": KEY_SHIFT,
		"move_forward": KEY_W,
		"move_back": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"turn_left": KEY_Q,
		"turn_right": KEY_E
	}
	
	for action in actions:
		# Remove the action if it exists to overwrite cleanly
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		
		InputMap.add_action(action)
		var event = InputEventKey.new()
		event.physical_keycode = actions[action]
		InputMap.action_add_event(action, event)
		
		# Set in ProjectSettings
		var action_dict = {
			"deadzone": 0.5,
			"events": InputMap.action_get_events(action)
		}
		ProjectSettings.set_setting("input/" + action, action_dict)
		
	var err = ProjectSettings.save()
	if err == OK:
		print("SUCCESS: Input actions configured and saved to project.godot!")
	else:
		print("ERROR: Failed to save project settings: ", err)
	quit()
