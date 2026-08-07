class_name DroneBatteryManager
extends RefCounted

signal battery_changed(percent: float)
signal battery_warning(message: String)
signal battery_exhausted()

const BATTERY_DRAIN_PER_SECOND := 0.0537  # Exact 31 minutes full flight time for 2250mAh LiPo (100% / 1860s)
const BATTERY_AGGRESSIVE_DRAIN_MULTIPLIER := 1.8
const BATTERY_HOVER_DRAIN_MULTIPLIER := 0.8
const BATTERY_RECHARGE_RATE_PER_SECOND := 5.0 # ~20 seconds for 0% -> 100% full charge!

const BATTERY_LOW_WARNING_PERCENT := 20.0
const BATTERY_CRITICAL_PERCENT := 8.0
const BATTERY_AUTO_LAND_PERCENT := 3.0

var battery_percent: float = 100.0
var battery_low_warning: bool = false
var battery_critical: bool = false
var battery_auto_landing: bool = false
var battery_failed: bool = false
var battery_exhausted_flag: bool = false
var battery_recharging: bool = false
var infinite_battery: bool = false

func set_infinite_battery(enabled: bool) -> void:
	infinite_battery = enabled
	if infinite_battery:
		reset()

func update_battery(delta: float, input_vec: Vector4, hover_enabled: bool) -> void:
	if infinite_battery:
		battery_percent = 100.0
		battery_low_warning = false
		battery_critical = false
		battery_auto_landing = false
		battery_failed = false
		battery_exhausted_flag = false
		battery_changed.emit(100.0)
		return

	if battery_recharging:
		recharge(delta * BATTERY_RECHARGE_RATE_PER_SECOND)
		return

	var is_aggressive := input_vec.length_squared() > 0.8
	var drain_mult := BATTERY_AGGRESSIVE_DRAIN_MULTIPLIER if is_aggressive else (BATTERY_HOVER_DRAIN_MULTIPLIER if hover_enabled else 1.0)
	battery_percent = maxf(0.0, battery_percent - BATTERY_DRAIN_PER_SECOND * drain_mult * delta)

	battery_changed.emit(battery_percent)

	if battery_percent <= BATTERY_LOW_WARNING_PERCENT and not battery_low_warning:
		battery_low_warning = true
		battery_warning.emit("LOW BATTERY (20%) - Return to Home recommended!")

	if battery_percent <= BATTERY_CRITICAL_PERCENT and not battery_critical:
		battery_critical = true
		battery_warning.emit("CRITICAL BATTERY (8%) - Reserve landing engaged!")

	if battery_percent <= BATTERY_AUTO_LAND_PERCENT:
		battery_auto_landing = true

	if battery_percent <= 0.0 and not battery_exhausted_flag:
		battery_exhausted_flag = true
		battery_failed = true
		battery_exhausted.emit()

func drain(amount: float) -> void:
	battery_percent = maxf(0.0, battery_percent - amount)
	if battery_percent <= 0.0 and not battery_exhausted_flag:
		battery_exhausted_flag = true
		battery_failed = true
		battery_exhausted.emit()
	battery_changed.emit(battery_percent)

func set_percent(val: float) -> void:
	battery_percent = clampf(val, 0.0, 100.0)
	if battery_percent > BATTERY_LOW_WARNING_PERCENT:
		battery_low_warning = false
		battery_critical = false
		battery_auto_landing = false
		battery_failed = false
		battery_exhausted_flag = false
	elif battery_percent <= 0.0:
		battery_exhausted_flag = true
		battery_failed = true
		battery_exhausted.emit()
	battery_changed.emit(battery_percent)

func recharge(amount: float) -> void:
	battery_percent = minf(100.0, battery_percent + amount)
	if battery_percent > BATTERY_LOW_WARNING_PERCENT:
		battery_low_warning = false
		battery_critical = false
		battery_auto_landing = false
		battery_failed = false
		battery_exhausted_flag = false
	battery_changed.emit(battery_percent)

func stop_recharge() -> void:
	battery_recharging = false

func reset() -> void:
	battery_percent = 100.0
	battery_low_warning = false
	battery_critical = false
	battery_auto_landing = false
	battery_failed = false
	battery_exhausted_flag = false
	battery_recharging = false
	battery_changed.emit(battery_percent)

func is_exhausted() -> bool:
	return battery_failed or battery_exhausted_flag

func is_auto_landing() -> bool:
	return battery_auto_landing
