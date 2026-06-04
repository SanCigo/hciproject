extends XROrigin3D
class_name VRPlayer

func get_trackers() -> Array[Node3D]:
	return [$RightController/GestureInputTrackerR, $LeftController/GestureInputTrackerL]
