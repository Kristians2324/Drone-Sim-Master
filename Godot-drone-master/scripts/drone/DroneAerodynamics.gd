class_name DroneAerodynamics
extends RefCounted

const WIND_FORCE_SCALE = 14.0
const WIND_DRAG_SCALE = 0.35
const WIND_HOVER_BOBBLE_SCALE = 0.55
const WIND_ROTATION_SCALE = 0.08
const WIND_TURB_SCALE = 0.85
const WIND_TURB_FREQ_A = 1.90
const WIND_TURB_FREQ_B = 0.65
const WIND_TURB_FREQ_C = 0.22

var _turb_phase_x: float = 0.0
var _turb_phase_z: float = 0.37
var _turb_phase_y: float = 0.71

func advance_turbulence(delta: float, wind_strength: float) -> void:
	_turb_phase_x += delta * (WIND_TURB_FREQ_A + wind_strength * 0.06)
	_turb_phase_z += delta * (WIND_TURB_FREQ_B + wind_strength * 0.04)
	_turb_phase_y += delta * (WIND_TURB_FREQ_C + wind_strength * 0.02)

func calculate_wind_forces(
	forward_dir: Vector3,
	strafe_dir: Vector3,
	wind_velocity: Vector3,
	wind_strength: float,
	wind_gust_factor: float,
	wind_phase: float,
	hover_enabled: bool
) -> Dictionary:
	var wind_force := Vector3.ZERO
	var wind_bobble := Vector3.ZERO
	var wind_drag_factor := 1.0
	var bank_tilt_torque := 0.0
	var pitch_tilt_torque := 0.0
	var tilt_x_torque := 0.0
	var tilt_z_torque := 0.0

	if wind_strength > 0.0 and not wind_velocity.is_zero_approx():
		var tailwind_push := forward_dir.dot(wind_velocity)
		var crosswind_push := strafe_dir.dot(wind_velocity)

		var gust_env := 0.8 + wind_gust_factor * 0.5 + sin(wind_phase * 1.5) * 0.1
		wind_force = wind_velocity * (WIND_FORCE_SCALE * gust_env)
		wind_drag_factor = clampf(1.0 - (tailwind_push / maxf(wind_strength, 0.1)) * WIND_DRAG_SCALE, 0.70, 1.30)

		var ws := wind_strength * WIND_TURB_SCALE
		var turb_x := sin(_turb_phase_x * WIND_TURB_FREQ_A) * 0.5 + sin(_turb_phase_x * WIND_TURB_FREQ_B * 1.2) * 0.3
		var turb_z := cos(_turb_phase_z * WIND_TURB_FREQ_A * 0.9) * 0.5 + cos(_turb_phase_z * WIND_TURB_FREQ_B * 1.4) * 0.3

		var turb_scale := lerpf(0.4, 1.0, wind_gust_factor)
		wind_force.x += turb_x * ws * turb_scale
		wind_force.z += turb_z * ws * turb_scale

		bank_tilt_torque = -crosswind_push * WIND_ROTATION_SCALE * 0.8
		pitch_tilt_torque = tailwind_push * WIND_ROTATION_SCALE * 0.8

		if hover_enabled:
			wind_bobble = Vector3(
				turb_x * wind_strength * WIND_HOVER_BOBBLE_SCALE,
				0.0,
				turb_z * wind_strength * WIND_HOVER_BOBBLE_SCALE
			)

		var tx := sin(_turb_phase_x * WIND_TURB_FREQ_A * 0.7) * 0.65 + sin(_turb_phase_x * WIND_TURB_FREQ_B) * 0.35
		var tz := cos(_turb_phase_z * WIND_TURB_FREQ_A * 0.8) * 0.65 + cos(_turb_phase_z * WIND_TURB_FREQ_B * 1.2) * 0.35
		var tilt_scale := wind_strength * WIND_ROTATION_SCALE * lerpf(0.6, 1.4, wind_gust_factor)
		tilt_x_torque = tx * tilt_scale
		tilt_z_torque = tz * tilt_scale

	return {
		"wind_force": wind_force,
		"wind_bobble": wind_bobble,
		"wind_drag_factor": wind_drag_factor,
		"bank_tilt_torque": bank_tilt_torque,
		"pitch_tilt_torque": pitch_tilt_torque,
		"tilt_x_torque": tilt_x_torque,
		"tilt_z_torque": tilt_z_torque,
	}
