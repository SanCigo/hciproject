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

func highlight_button(hand: String, button_name: String, color: Color) -> void:
	var controller = $RightController if hand == "right" else $LeftController
	if not controller.has_node("ControllerModel"):
		return
	var model_root = controller.get_node("ControllerModel")
	var button_mesh = _find_mesh_by_name(model_root, button_name.to_lower())
	if button_mesh:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 2.0
		button_mesh.set_surface_override_material(0, mat)

func reset_button_highlight(hand: String, button_name: String) -> void:
	var controller = $RightController if hand == "right" else $LeftController
	if not controller.has_node("ControllerModel"):
		return
	var model_root = controller.get_node("ControllerModel")
	var button_mesh = _find_mesh_by_name(model_root, button_name.to_lower())
	if button_mesh:
		button_mesh.set_surface_override_material(0, null)

func _find_mesh_by_name(node: Node, partial_name: String) -> MeshInstance3D:
	if node is MeshInstance3D and partial_name in node.name.to_lower():
		return node as MeshInstance3D
	for child in node.get_children():
		var found = _find_mesh_by_name(child, partial_name)
		if found:
			return found
	return null
