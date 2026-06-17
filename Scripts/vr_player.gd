extends XROrigin3D
class_name VRPlayer

signal restart_requested()
signal restart_progress(progress: float)
signal next_page()
signal previous_page()

const HOLD_TIME_SEC := 2.0
var _hold_timer := 0.0
var _restart_triggered := false

var _highlighted_meshes: Dictionary = {}
var _blinking_meshes: Array[MeshInstance3D] = []

@export var controller_tilt_degrees: float = 20.0

func _ready() -> void:
	$RightController.button_pressed.connect(_on_right_button_pressed)
	$LeftController.button_pressed.connect(_on_left_button_pressed)
	
	if $RightController.has_node("ControllerModel"):
		$RightController.get_node("ControllerModel").rotation_degrees.x += controller_tilt_degrees
	if $LeftController.has_node("ControllerModel"):
		$LeftController.get_node("ControllerModel").rotation_degrees.x += controller_tilt_degrees

func _on_right_button_pressed(button_name: String) -> void:
	if button_name == "by_button":
		next_page.emit()

func _on_left_button_pressed(button_name: String) -> void:
	if button_name == "by_button":
		previous_page.emit()

func _process(delta: float) -> void:
	if $RightController.is_button_pressed("by_button") or $LeftController.is_button_pressed("by_button"):
		_hold_timer += delta
		if _hold_timer >= HOLD_TIME_SEC and not _restart_triggered:
			_restart_triggered = true
			restart_requested.emit()
			restart_progress.emit(0.0)
			print("[VRPlayer] Restart requested via controller button.")
		elif not _restart_triggered:
			restart_progress.emit(_hold_timer / HOLD_TIME_SEC)
	else:
		if _hold_timer > 0.0 or _restart_triggered:
			_hold_timer = 0.0
			_restart_triggered = false
			restart_progress.emit(0.0)
			
	var time = Time.get_ticks_msec() / 1000.0
	var blink_energy = (sin(time * 8.0) + 1.0) # oscillates between 0 and 2
	for mesh in _blinking_meshes:
		if is_instance_valid(mesh):
			var mat = mesh.get_surface_override_material(0)
			if mat and mat is StandardMaterial3D:
				mat.emission_energy_multiplier = blink_energy

func get_trackers() -> Array[Node3D]:
	return [$RightController/GestureInputTrackerR, $LeftController/GestureInputTrackerL]

func highlight_button(hand: String, button_name: String, color: Color, blink: bool = false) -> void:
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
		
		_highlighted_meshes[button_mesh] = true
		if blink:
			if not _blinking_meshes.has(button_mesh):
				_blinking_meshes.append(button_mesh)
		else:
			_blinking_meshes.erase(button_mesh)

func reset_button_highlight(hand: String, button_name: String) -> void:
	var controller = $RightController if hand == "right" else $LeftController
	if not controller.has_node("ControllerModel"):
		return
	var model_root = controller.get_node("ControllerModel")
	var button_mesh = _find_mesh_by_name(model_root, button_name.to_lower())
	if button_mesh:
		button_mesh.set_surface_override_material(0, null)
		_highlighted_meshes.erase(button_mesh)
		_blinking_meshes.erase(button_mesh)

func clear_all_highlights() -> void:
	for mesh in _highlighted_meshes.keys():
		if is_instance_valid(mesh):
			mesh.set_surface_override_material(0, null)
	_highlighted_meshes.clear()
	_blinking_meshes.clear()

func _find_mesh_by_name(node: Node, partial_name: String) -> MeshInstance3D:
	if node is MeshInstance3D and partial_name in node.name.to_lower():
		return node as MeshInstance3D
	for child in node.get_children():
		var found = _find_mesh_by_name(child, partial_name)
		if found:
			return found
	return null
