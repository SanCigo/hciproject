extends XROrigin3D
class_name VRPlayer

signal restart_requested()

const HOLD_TIME_SEC := 2.0
var _hold_timer := 0.0
var _restart_triggered := false

func _process(delta: float) -> void:
	if $RightController.is_button_pressed("by_button") or $LeftController.is_button_pressed("by_button"):
		_hold_timer += delta
		if _hold_timer >= HOLD_TIME_SEC and not _restart_triggered:
			_restart_triggered = true
			restart_requested.emit()
			print("[VRPlayer] Restart requested via controller button.")
	else:
		_hold_timer = 0.0
		_restart_triggered = false

func get_trackers() -> Array[Node3D]:
	return [$RightController/GestureInputTrackerR, $LeftController/GestureInputTrackerL]
