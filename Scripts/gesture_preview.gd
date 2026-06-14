extends Node

## Gesture Preview Scene — run with F6 to preview gesture animations on the
## actual avatar.  Reads exclusively from gesture_editor_data.json (the new
## hand-authored keyframe format).  A sidebar with one button per gesture lets
## you trigger animations; a speed slider and loop checkbox let you tweak playback.
##
## Keyboard shortcuts (focus anywhere in the scene):
##   F   — switch to FRONT plane
##   S   — switch to SIDE plane
##   P   — toggle palm-faces-player
##   Space / Enter — replay current gesture

@onready var avatar: Avatar              = $GameWorld/Avatar
@onready var sidebar: VBoxContainer      = $UI/Panel/Sidebar
@onready var speed_slider: HSlider       = $UI/Panel/Sidebar/SpeedRow/SpeedSlider
@onready var speed_label: Label          = $UI/Panel/Sidebar/SpeedRow/SpeedValue
@onready var loop_check: CheckBox        = $UI/Panel/Sidebar/LoopCheck
@onready var info_label: Label           = $UI/Panel/Sidebar/InfoLabel
@onready var gesture_list: VBoxContainer = $UI/Panel/Sidebar/ScrollContainer/GestureList

var _gesture_defs: Array = []   # Array of gesture entry dicts from gesture_editor_data.json
var _current_gesture: String = ""
var _looping: bool = false

# Plane / palm controls — created in code so they work even if the .tscn
# hasn't been reloaded by the editor after external edits.
var _plane_front_btn: Button     = null
var _plane_side_btn: Button      = null
var _palm_check: CheckBox        = null
var _plane_label: Label          = null
var _side_offset_slider: HSlider = null
var _side_offset_label: Label    = null


func _ready() -> void:
	_load_editor_gestures()
	_build_buttons()

	# Wait two frames: one for the scene tree, one for avatar._ready() to
	# dynamically add GestureAnimator.
	await get_tree().process_frame
	await get_tree().process_frame

	if avatar and avatar.gesture_animator:
		avatar.animation_finished.connect(_on_avatar_animation_finished)
		print("[GesturePreview] GestureAnimator found OK.")
	else:
		push_error("[GesturePreview] GestureAnimator not found on avatar!")

	speed_slider.value_changed.connect(_on_speed_changed)
	loop_check.toggled.connect(func(on: bool): _looping = on)

	# Build the plane / palm controls in GDScript so they always exist.
	_build_plane_controls()

	_update_info("Select a gesture.\n[F]=Front  [S]=Side  [P]=Palm toggle")


# ──────────────────────────────────────────────────────────────────────────────
# Build the extra controls in code (appended below LoopCheck in the sidebar)
# ──────────────────────────────────────────────────────────────────────────────
func _build_plane_controls() -> void:
	# Separator
	var sep := HSeparator.new()
	sidebar.add_child(sep)

	# Section label
	_plane_label = Label.new()
	_plane_label.text = "Gesture Plane  [F] / [S]"
	sidebar.add_child(_plane_label)

	# Front / Side buttons in a row
	var row := HBoxContainer.new()
	sidebar.add_child(row)

	_plane_front_btn = Button.new()
	_plane_front_btn.text = "Front"
	_plane_front_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_plane_front_btn.tooltip_text = "Gesture plays in front of the avatar (default)"
	_plane_front_btn.pressed.connect(_on_plane_front)
	row.add_child(_plane_front_btn)

	_plane_side_btn = Button.new()
	_plane_side_btn.text = "Side"
	_plane_side_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_plane_side_btn.tooltip_text = "Gesture plays to the side of the avatar"
	_plane_side_btn.pressed.connect(_on_plane_side)
	row.add_child(_plane_side_btn)

	# Side offset slider
	var off_label := Label.new()
	off_label.text = "Side Offset (cm)"
	sidebar.add_child(off_label)

	var off_row := HBoxContainer.new()
	sidebar.add_child(off_row)

	_side_offset_slider = HSlider.new()
	_side_offset_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side_offset_slider.min_value = 30.0
	_side_offset_slider.max_value = 500.0
	_side_offset_slider.step = 5.0
	_side_offset_slider.value = 80.0
	_side_offset_slider.value_changed.connect(_on_side_offset_changed)
	off_row.add_child(_side_offset_slider)

	_side_offset_label = Label.new()
	_side_offset_label.text = "80"
	_side_offset_label.custom_minimum_size = Vector2(36, 0)
	off_row.add_child(_side_offset_label)

	# Palm toggle
	_palm_check = CheckBox.new()
	_palm_check.text = "Palm faces player  [P]"
	_palm_check.button_pressed = true
	_palm_check.tooltip_text = "Rotate wrist so the palm faces toward the camera"
	_palm_check.toggled.connect(_on_palm_toggled)
	sidebar.add_child(_palm_check)

	# Sync initial state from the animator if already available
	if avatar and avatar.gesture_animator:
		var ga := avatar.gesture_animator
		_palm_check.button_pressed = ga.palm_faces_player
		_side_offset_slider.value  = ga.gesture_side_offset

	_refresh_plane_buttons()


# ──────────────────────────────────────────────────────────────────────────────
# Gesture list — loaded exclusively from gesture_editor_data.json
# ──────────────────────────────────────────────────────────────────────────────
func _load_editor_gestures() -> void:
	_gesture_defs.clear()
	var path := "res://gestures/gesture_editor_data.json"
	if not FileAccess.file_exists(path):
		push_warning("[GesturePreview] gesture_editor_data.json not found. " +
			"Export from gesture_editor.html first.")
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[GesturePreview] Could not open: " + path)
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("[GesturePreview] JSON parse error: " + json.get_error_message())
		file.close()
		return
	file.close()
	var data = json.get_data()
	if not data is Array:
		push_error("[GesturePreview] Unexpected root type in gesture_editor_data.json.")
		return
	_gesture_defs = data
	print("[GesturePreview] Loaded %d gesture(s) from gesture_editor_data.json." % _gesture_defs.size())


func _build_buttons() -> void:
	if _gesture_defs.is_empty():
		var lbl := Label.new()
		lbl.text = "No gestures found.\nExport from gesture_editor.html."
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gesture_list.add_child(lbl)
		return

	for entry in _gesture_defs:
		var gname: String = entry.get("name", "")
		if gname == "":
			continue
		var has_l: bool = (entry.get("left_keyframes",  []) as Array).size() > 0
		var has_r: bool = (entry.get("right_keyframes", []) as Array).size() > 0

		var btn := Button.new()
		if has_l and has_r:
			btn.text = "%s  [bimanual]" % gname
		elif has_l:
			btn.text = "%s  [left hand]" % gname
		else:
			btn.text = "%s  [right hand]" % gname
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 14)
		btn.custom_minimum_size.y = 36
		btn.pressed.connect(_on_gesture_button.bind(gname))
		gesture_list.add_child(btn)


# ──────────────────────────────────────────────────────────────────────────────
# Playback
# ──────────────────────────────────────────────────────────────────────────────
func _on_gesture_button(gesture_name: String) -> void:
	_current_gesture = gesture_name
	_play_current()


func _play_current() -> void:
	if _current_gesture == "" or not avatar:
		return
	if avatar.gesture_animator:
		avatar.gesture_animator.playback_speed = speed_slider.value

	avatar.play_animation(_current_gesture)

	var entry := _find_def(_current_gesture)
	var has_l: bool = entry and (entry.get("left_keyframes",  []) as Array).size() > 0
	var has_r: bool = entry and (entry.get("right_keyframes", []) as Array).size() > 0
	var mode_str := "bimanual" if (has_l and has_r) else ("left" if has_l else "right")

	var plane_str := "SIDE" if (_get_plane() == 1) else "FRONT"
	_update_info("Playing: %s\nMode: %s  |  Plane: %s" % [_current_gesture, mode_str, plane_str])


func _on_avatar_animation_finished() -> void:
	if _looping and _current_gesture != "":
		await get_tree().create_timer(0.3).timeout
		_play_current()
	else:
		_update_info("Done: %s\nSelect another or enable Loop." % _current_gesture)


func _on_speed_changed(value: float) -> void:
	speed_label.text = "%.1fx" % value
	if avatar and avatar.gesture_animator:
		avatar.gesture_animator.playback_speed = value


# ──────────────────────────────────────────────────────────────────────────────
# Plane controls
# ──────────────────────────────────────────────────────────────────────────────
func _on_plane_front() -> void:
	_set_plane(0)
	_play_current()


func _on_plane_side() -> void:
	_set_plane(1)
	_play_current()


func _set_plane(plane_int: int) -> void:
	if avatar and avatar.gesture_animator:
		avatar.gesture_animator.gesture_plane = plane_int
		print("[GesturePreview] gesture_plane set to %d  (0=FRONT 1=SIDE)" % plane_int)
	else:
		push_error("[GesturePreview] Cannot set plane — gesture_animator is null")
	_refresh_plane_buttons()


func _get_plane() -> int:
	if avatar and avatar.gesture_animator:
		return avatar.gesture_animator.gesture_plane
	return 0


func _refresh_plane_buttons() -> void:
	if not _plane_front_btn or not _plane_side_btn:
		return
	var is_front: bool = _get_plane() == 0
	_plane_front_btn.modulate = Color(1, 1, 1, 1)  if is_front     else Color(0.6, 0.6, 0.6, 1)
	_plane_side_btn.modulate  = Color(1, 1, 1, 1)  if not is_front else Color(0.6, 0.6, 0.6, 1)


func _on_side_offset_changed(value: float) -> void:
	if _side_offset_label:
		_side_offset_label.text = str(int(value))
	if avatar and avatar.gesture_animator:
		avatar.gesture_animator.gesture_side_offset = value


func _on_palm_toggled(pressed: bool) -> void:
	if avatar and avatar.gesture_animator:
		avatar.gesture_animator.palm_faces_player = pressed


# ──────────────────────────────────────────────────────────────────────────────
# Keyboard shortcuts
# ──────────────────────────────────────────────────────────────────────────────
func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed:
		return
	if event is InputEventKey:
		match event.keycode:
			KEY_F:
				_set_plane(0)
				_play_current()
			KEY_S:
				_set_plane(1)
				_play_current()
			KEY_P:
				if _palm_check:
					_palm_check.button_pressed = not _palm_check.button_pressed
			KEY_SPACE, KEY_ENTER:
				_play_current()


# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────
func _update_info(text: String) -> void:
	if info_label:
		info_label.text = text


func _find_def(gesture_name: String) -> Dictionary:
	for d in _gesture_defs:
		if d.get("name", "") == gesture_name:
			return d
	return {}
