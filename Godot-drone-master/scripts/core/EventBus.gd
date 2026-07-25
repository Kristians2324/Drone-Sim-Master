extends Node

signal simulation_started
signal environment_changed(environment_name: String)
signal formation_triggered(formation_name: String)
signal hover_toggled(enabled: bool)
signal battery_updated(percent: float, low_warning: bool)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func emit_simulation_started() -> void:
	simulation_started.emit()

func emit_environment_changed(env_name: String) -> void:
	environment_changed.emit(env_name)

func emit_formation_triggered(form_name: String) -> void:
	formation_triggered.emit(form_name)

func emit_hover_toggled(enabled: bool) -> void:
	hover_toggled.emit(enabled)

func emit_battery_updated(percent: float, low_warning: bool) -> void:
	battery_updated.emit(percent, low_warning)
