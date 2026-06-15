extends Node

## Procedural arm animator that drives the avatar's arm bones through gesture
## paths loaded from two sources (priority order):
##
##  1. gesture_editor_data.json — hand-authored keyframes from gesture_editor.html.
##     Coordinates are in skeleton space (cm), so what you draw is exactly where
##     the arm moves. No scale/offset applied.
##
##  2. p_c_data.json + gesture_config.json — legacy point-cloud data (used as
##     fallback when a gesture is not found in the editor data).
##
## Attach as a child of the Avatar node. Call play_gesture(gesture_name) to
## animate the arm(s). Single-hand gestures move only the configured arm;
## bimanual gestures move both.
##
## The arm stays in full extension — only the upper-arm bone is rotated so the
## arm chain points toward the interpolated hand-target position each frame.

signal animation_finished()

const GESTURE_DATA_PATH   := "res://gestures/p_c_data.json"
const GESTURE_CONFIG_PATH := "res://gestures/gesture_config.json"
const EDITOR_DATA_PATH    := "res://gestures/gesture_editor_data.json"

## Duration (in seconds) for one full gesture playback.
@export var gesture_duration: float = 2.5
## Playback speed multiplier.
@export var playback_speed: float = 1.0

## Scale applied to normalised point-cloud coordinates (in cm, skeleton space).
## The raw point data lives in roughly [−0.6, +0.6]; this converts to cm offsets.
@export var gesture_scale: float = 50.0

## Offset added to the mapped points (in skeleton space, cm).
## Positions the gesture in front of the avatar at roughly chest/head height.
## X = 0 (centred), Y ≈ shoulder height from Hips, Z ≈ forward.
@export var gesture_center: Vector3 = Vector3(0.0, 150.0, -40.0)

## Which plane the gesture is performed on.
## FRONT (default): the gesture plays in front of the body.
##   raw-X → skel-X (left/right lateral variation)
##   raw-Y → skel-Y (up/down)
##   raw-Z → skel-Z (forward/back depth)
## SIDE: the hand is pinned to the side of the body at gesture_side_offset and
##   the gesture's primary oscillation axis (raw-X) drives depth (skel-Z) instead,
##   so the motion runs parallel to the body rather than in front of it.
##   raw-X → skel-Z (forward/back depth from the side)
##   raw-Y → skel-Y (up/down)
##   raw-Z → tiny skel-X tweak around the fixed side offset
enum GesturePlane { FRONT, SIDE }
@export var gesture_plane: GesturePlane = GesturePlane.FRONT

## Lateral distance (cm, skeleton space) from body centre used in SIDE mode.
## The hand is placed at ±gesture_side_offset on the X axis (sign = hand side),
## and the gesture's motion plays forward/back from that fixed position.
@export var gesture_side_offset: float = 80.0

## When true the wrist is rotated each frame so the palm faces the player
## (forward / -Z in world space).  Turn off if the rest-pose palm is already correct.
@export var palm_faces_player: bool = true

## Scale applied to editor-authored keyframe coordinates.
## The HTML editor draws in Three.js world units (avatar ~1.87 units tall).
## The Godot skeleton uses cm (avatar ~187 cm tall), so the factor is 100.
## Adjust if your skeleton is imported at a different unit scale.
@export var editor_to_skeleton_scale: float = 100.0

## Offset added to every editor-keyframe target position, in skeleton space (cm).
## X = 0 (centred), Y = height from hips (≈ shoulder height), Z = forward offset
## (negative = in front of avatar, because skeleton -Z is forward for Mixamo rigs).
## Tune Y and Z in the Godot Inspector until the gesture sits where you expect.
@export var editor_gesture_offset: Vector3 = Vector3(0.0, 0.0, 0.0)

# ── Loaded data ───────────────────────────────────────────────────────────────
var _templates: Dictionary = {}       # template_name → Array[Vector3]  (raw points)
var _gesture_defs: Dictionary = {}    # gesture_name  → config Dictionary

## Editor-authored keyframe gestures (loaded from gesture_editor_data.json).
## Each entry: gesture_name → { "left_keyframes": [...], "right_keyframes": [...] }
## Each keyframe: { "t": float, "x": float, "y": float, "z": float }
var _editor_gestures: Dictionary = {}

# ── Animation state ───────────────────────────────────────────────────────────
var _animating: bool = false
var _elapsed: float = 0.0
var _points_left: Array = []        # mapped points in skeleton space (cm)
var _points_right: Array = []
var _animate_left: bool = false
var _animate_right: bool = false

## When true, _keyframes_left/_keyframes_right hold {"t": float, "pos": Vector3}
## dicts from the editor data and are used for time-accurate interpolation.
var _use_editor_keyframes: bool = false
var _keyframes_left: Array = []     # [{"t": float, "pos": Vector3}, ...]
var _keyframes_right: Array = []    # [{"t": float, "pos": Vector3}, ...]

# ── Skeleton references (resolved at _ready) ─────────────────────────────────
var _skeleton: Skeleton3D = null
var _left_arm_idx: int = -1
var _left_forearm_idx: int = -1
var _left_hand_idx: int = -1
var _right_arm_idx: int = -1
var _right_forearm_idx: int = -1
var _right_hand_idx: int = -1

# Rest-pose directions for each arm (skeleton space, normalised).
# Pre-computed once so we don't recalculate every frame.
var _left_rest_dir: Vector3 = Vector3.ZERO
var _right_rest_dir: Vector3 = Vector3.ZERO


# ══════════════════════════════════════════════════════════════════════════════
# Lifecycle
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_load_editor_gestures()   # priority source: hand-authored keyframes
	_load_templates()
	_load_gesture_config()
	# Delay skeleton lookup by one frame so the scene tree is fully built.
	call_deferred("_find_skeleton")
	# Run after the AnimationPlayer so our bone overrides stick for the frame.
	process_priority = 100


func _process(delta: float) -> void:
	if not _animating:
		return

	_elapsed += delta * playback_speed
	var t: float = clampf(_elapsed / gesture_duration, 0.0, 1.0)

	if _use_editor_keyframes:
		# Use time-accurate interpolation: each keyframe has an authored t value.
		if _animate_left and _keyframes_left.size() > 0:
			var target := _interpolate_keyframes(_keyframes_left, t)
			_aim_arm(_left_arm_idx, _left_forearm_idx, target)
		if _animate_right and _keyframes_right.size() > 0:
			var target := _interpolate_keyframes(_keyframes_right, t)
			_aim_arm(_right_arm_idx, _right_forearm_idx, target)
	else:
		# Legacy path: evenly-spaced point-cloud data.
		if _animate_left and _points_left.size() > 0:
			var target := _interpolate_points(_points_left, t)
			_aim_arm(_left_arm_idx, _left_forearm_idx, target)
		if _animate_right and _points_right.size() > 0:
			var target := _interpolate_points(_points_right, t)
			_aim_arm(_right_arm_idx, _right_forearm_idx, target)

	if t >= 1.0:
		_animating = false
		_reset_bones()
		animation_finished.emit()


# ══════════════════════════════════════════════════════════════════════════════
# Public API
# ══════════════════════════════════════════════════════════════════════════════

## Switch the gesture plane and restart the current animation (if any).
func set_gesture_plane(plane: GesturePlane) -> void:
	gesture_plane = plane


## Start animating the arm(s) for the given gesture name.
## Editor-authored keyframes take priority over the legacy point-cloud data.
func play_gesture(gesture_name: String) -> void:
	if not _skeleton:
		push_warning("[GestureAnimator] Skeleton not found — cannot animate.")
		animation_finished.emit()
		return

	_animate_left  = false
	_animate_right = false
	_points_left.clear()
	_points_right.clear()
	_use_editor_keyframes = false
	_keyframes_left.clear()
	_keyframes_right.clear()

	# ── Priority 1: hand-authored editor keyframes ──────────────────────────
	if _editor_gestures.has(gesture_name):
		var ed: Dictionary = _editor_gestures[gesture_name]
		var lkf: Array = ed.get("left_keyframes",  [])
		var rkf: Array = ed.get("right_keyframes", [])
		var sc:  float = float(ed.get("scale", editor_to_skeleton_scale))

		if lkf.size() > 0:
			_animate_left = true
			_keyframes_left = _keyframes_to_timed_vectors(lkf, sc)
		if rkf.size() > 0:
			_animate_right = true
			_keyframes_right = _keyframes_to_timed_vectors(rkf, sc)

		if (not _animate_left) and (not _animate_right):
			push_warning("[GestureAnimator] Editor entry for '%s' has no points." % gesture_name)
			animation_finished.emit()
			return

		_use_editor_keyframes = true
		_elapsed = 0.0
		_animating = true
		print("[GestureAnimator] Playing '%s' (editor keyframes, t-accurate)  L=%s R=%s  kfs_L=%d kfs_R=%d" % [
			gesture_name, _animate_left, _animate_right,
			_keyframes_left.size(), _keyframes_right.size()])
		return

	# ── Priority 2: legacy point-cloud data ─────────────────────────────────
	var def: Dictionary = _gesture_defs.get(gesture_name, {})
	if def.is_empty():
		push_warning("[GestureAnimator] No config for gesture '%s'." % gesture_name)
		animation_finished.emit()
		return

	var mode: String = def.get("mode", "single")
	if mode == "single":
		_setup_single(def)
	elif mode == "multi":
		_setup_multi(def)

	if (not _animate_left) and (not _animate_right):
		push_warning("[GestureAnimator] Nothing to animate for '%s'." % gesture_name)
		animation_finished.emit()
		return

	_elapsed = 0.0
	_animating = true
	print("[GestureAnimator] Playing '%s' (point-cloud)  mode=%s  L=%s R=%s  pts_L=%d pts_R=%d" % [
		gesture_name, mode, _animate_left, _animate_right,
		_points_left.size(), _points_right.size()])


## Stop the current animation immediately and reset bones.
func stop() -> void:
	if _animating:
		_animating = false
		_reset_bones()


## Force the arms to aim at the given skeleton-space positions (for editor preview).
## Provide null to leave the arm uncontrolled (it will return to idle).
func preview_positions(left_pos: Variant, right_pos: Variant) -> void:
	if not _skeleton: return
	_reset_bones()
	if left_pos != null:
		_aim_arm(_left_arm_idx, _left_forearm_idx, left_pos as Vector3)
	if right_pos != null:
		_aim_arm(_right_arm_idx, _right_forearm_idx, right_pos as Vector3)


## True while an animation is playing.
func is_playing() -> bool:
	return _animating


# ══════════════════════════════════════════════════════════════════════════════
# Setup helpers
# ══════════════════════════════════════════════════════════════════════════════

func _setup_single(def: Dictionary) -> void:
	var hand: String = def.get("hand", "right")
	var tpl_name: String = def.get("template_name", "")
	var pts := _get_template_points(tpl_name)
	if pts.is_empty():
		return
	var mapped := _map_points(pts, hand)
	if hand == "left":
		_animate_left = true
		_points_left = mapped
	else:
		_animate_right = true
		_points_right = mapped


func _setup_multi(def: Dictionary) -> void:
	var left_tpl: String  = def.get("left_template", "")
	var right_tpl: String = def.get("right_template", "")
	var mirror: bool        = def.get("mirror", false)
	var mirror_axis: String = def.get("mirror_axis", "x")
	var mirrored_hand: String = def.get("mirrored_hand", "")

	var left_pts  := _get_template_points(left_tpl)
	var right_pts := _get_template_points(right_tpl)
	if left_pts.is_empty() or right_pts.is_empty():
		return

	if mirror:
		if mirrored_hand == "left":
			left_pts = _mirror_points(left_pts, mirror_axis)
		elif mirrored_hand == "right":
			right_pts = _mirror_points(right_pts, mirror_axis)

	_animate_left  = true
	_animate_right = true
	_points_left  = _map_points(left_pts, "left")
	_points_right = _map_points(right_pts, "right")


# ══════════════════════════════════════════════════════════════════════════════
# Point-cloud helpers
# ══════════════════════════════════════════════════════════════════════════════

## Retrieve a template's raw points by name.  Returns empty array if not found.
func _get_template_points(tpl_name: String) -> Array:
	if not _templates.has(tpl_name):
		push_warning("[GestureAnimator] Template '%s' not found." % tpl_name)
		return []
	# Return a duplicate so we don't mutate the original.
	return _templates[tpl_name].duplicate()


## Mirror point coordinates along the given axis.
func _mirror_points(points: Array, axis: String) -> Array:
	var result: Array = []
	for p: Vector3 in points:
		match axis:
			"x": result.append(Vector3(-p.x,  p.y,  p.z))
			"y": result.append(Vector3( p.x, -p.y,  p.z))
			"z": result.append(Vector3( p.x,  p.y, -p.z))
			_:   result.append(p)
	return result


## Map normalised point-cloud points → skeleton-space positions (cm).
##
## The raw points are centred around the origin in roughly [−0.6, +0.6].
## We scale them and offset so the gesture plays at the right location.
##
## FRONT mode (default):
##   raw-X → skel-X (lateral, left/right)   raw-Z → skel-Z (depth, forward/back)
##   gesture_center positions the whole gesture in front of the avatar.
##
## SIDE mode:
##   The hand is pinned laterally to ±gesture_side_offset (X axis, sign = hand).
##   raw-X (the gesture's main oscillation axis) → skel-Z (forward/back depth),
##   so a wave gesture plays out alongside the body, not in front of it.
##   raw-Z (almost always tiny) → small skel-X tweak around the pinned position.
##   gesture_center.y still controls height; gesture_center.x/z are ignored.
func _map_points(raw_points: Array, hand: String) -> Array:
	var result: Array = []
	var x_sign: float = 1.0 if hand == "left" else -1.0
	for p: Vector3 in raw_points:
		var mapped: Vector3
		if gesture_plane == GesturePlane.FRONT:
			# Default: gesture plays in front of the avatar.
			mapped = Vector3(
				gesture_center.x + p.x * gesture_scale * x_sign,
				gesture_center.y + p.y * gesture_scale,
				gesture_center.z + p.z * gesture_scale
			)
		else:
			# SIDE: pin the hand to the side of the body; the oscillation
			# (raw-X) becomes forward/back depth so the motion is parallel to the body.
			var pin_x: float = gesture_side_offset * x_sign
			mapped = Vector3(
				pin_x + p.z * gesture_scale * x_sign,  # fixed side + minor Z tweak
				gesture_center.y + p.y * gesture_scale, # height unchanged
				p.x * gesture_scale                     # raw-X oscillation → depth
			)
		result.append(mapped)
	return result


## Linearly interpolate through an array of points at parameter t ∈ [0, 1].
## Used by the legacy point-cloud path (evenly spaced points).
func _interpolate_points(points: Array, t: float) -> Vector3:
	if points.size() == 0:
		return Vector3.ZERO
	if points.size() == 1:
		return points[0]
	var idx_f: float = t * float(points.size() - 1)
	var lo: int = int(floor(idx_f))
	var hi: int = mini(lo + 1, points.size() - 1)
	var frac: float = idx_f - float(lo)
	return (points[lo] as Vector3).lerp(points[hi] as Vector3, frac)


## Interpolate through editor keyframes [{"t": float, "pos": Vector3}] using
## the authored t-values so timing matches exactly what was drawn in the editor.
func _interpolate_keyframes(kfs: Array, t: float) -> Vector3:
	if kfs.size() == 0:
		return Vector3.ZERO
	if kfs.size() == 1:
		return kfs[0]["pos"]
	# Clamp t to the range of authored keyframes.
	var t0: float = float(kfs[0]["t"])
	var tn: float = float(kfs[kfs.size() - 1]["t"])
	var tc: float = clampf(t, t0, tn)
	# Binary-search for the segment containing tc.
	var lo: int = 0
	var hi: int = kfs.size() - 1
	while lo < hi - 1:
		var mid: int = (lo + hi) / 2
		if float(kfs[mid]["t"]) <= tc:
			lo = mid
		else:
			hi = mid
	# Interpolate between kfs[lo] and kfs[hi].
	var t_lo: float = float(kfs[lo]["t"])
	var t_hi: float = float(kfs[hi]["t"])
	var span: float = t_hi - t_lo
	var frac: float = 0.0 if span < 1e-8 else (tc - t_lo) / span
	return (kfs[lo]["pos"] as Vector3).lerp(kfs[hi]["pos"] as Vector3, frac)


# ══════════════════════════════════════════════════════════════════════════════
# Bone aiming
# ══════════════════════════════════════════════════════════════════════════════

## Rotate the upper-arm bone so the fully-extended arm points toward
## `target_skeleton` (a position in skeleton space, cm), then optionally
## orient the wrist so the palm faces the player.
func _aim_arm(arm_idx: int, forearm_idx: int, target_skeleton: Vector3) -> void:
	if arm_idx < 0 or forearm_idx < 0 or not _skeleton:
		return

	# Current shoulder position in skeleton space (from the animated global pose,
	# so it follows the idle sway, breathing, etc.).
	var arm_global_pose := _skeleton.get_bone_global_pose(arm_idx)
	var shoulder_pos := arm_global_pose.origin

	# Target direction from shoulder.
	var target_dir := (target_skeleton - shoulder_pos)
	if target_dir.length_squared() < 0.001:
		return
	target_dir = target_dir.normalized()

	# Rest direction of this arm (precomputed in _find_skeleton).
	var rest_dir: Vector3
	if arm_idx == _left_arm_idx:
		rest_dir = _left_rest_dir
	else:
		rest_dir = _right_rest_dir

	# Rotation from rest direction → target direction (in skeleton space).
	var dot_val := clampf(rest_dir.dot(target_dir), -1.0, 1.0)
	if dot_val > 0.9999:
		return   # Already pointing the right way.

	var cross_vec := rest_dir.cross(target_dir)
	if cross_vec.length_squared() < 1e-8:
		# Antiparallel — pick an arbitrary perpendicular axis.
		cross_vec = rest_dir.cross(Vector3.UP)
		if cross_vec.length_squared() < 1e-8:
			cross_vec = rest_dir.cross(Vector3.RIGHT)
	cross_vec = cross_vec.normalized()

	var angle := acos(dot_val)
	var delta_rot := Quaternion(cross_vec, angle)

	# Apply the rotation to the bone's global-rest basis, then convert to local
	# space so set_bone_pose_rotation() does the right thing.
	var rest_global_basis := _skeleton.get_bone_global_rest(arm_idx).basis
	var desired_global_basis := Basis(delta_rot) * rest_global_basis

	# Parent's current global pose basis (includes idle animation on spine, etc.).
	var parent_idx := _skeleton.get_bone_parent(arm_idx)
	var parent_basis: Basis
	if parent_idx >= 0:
		parent_basis = _skeleton.get_bone_global_pose(parent_idx).basis
	else:
		parent_basis = Basis.IDENTITY

	var local_basis := parent_basis.inverse() * desired_global_basis
	_skeleton.set_bone_pose_rotation(arm_idx, local_basis.get_rotation_quaternion())

	# ── Palm orientation ────────────────────────────────────────────────────────
	# Rotate the wrist bone so the palm faces forward (-Z world, toward the
	# player / camera).  We leave the forearm untouched so only the wrist twists.
	if palm_faces_player:
		var hand_idx := _left_hand_idx if arm_idx == _left_arm_idx else _right_hand_idx
		if hand_idx >= 0:
			_orient_palm_forward(hand_idx)


## Rotate a wrist/hand bone so the palm faces the player (forward / -Z world).
## We compute the desired global orientation (palm-down rest → palm-forward)
## then express it in bone-local space.
func _orient_palm_forward(hand_idx: int) -> void:
	# The desired global palm normal is -Z (facing the player).
	# We build a basis whose Y axis (palm normal in Mixamo rigs) points toward -Z.
	var palm_target_global := Basis(
		Vector3(1, 0, 0),   # X stays left/right
		Vector3(0, 0, -1),  # Y (palm normal) → toward player
		Vector3(0, 1, 0)    # Z → up
	)

	var parent_idx := _skeleton.get_bone_parent(hand_idx)
	var parent_global_basis: Basis
	if parent_idx >= 0:
		parent_global_basis = _skeleton.get_bone_global_pose(parent_idx).basis
	else:
		parent_global_basis = Basis.IDENTITY

	var local_basis := parent_global_basis.inverse() * palm_target_global
	_skeleton.set_bone_pose_rotation(hand_idx, local_basis.get_rotation_quaternion())


## Reset arm bones to their rest-pose rotations so the idle animation takes over.
func _reset_bones() -> void:
	if not _skeleton:
		return
	for idx in [_left_arm_idx, _right_arm_idx, _left_hand_idx, _right_hand_idx]:
		if idx >= 0:
			var rest_quat := _skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()
			_skeleton.set_bone_pose_rotation(idx, rest_quat)


# ══════════════════════════════════════════════════════════════════════════════
# Skeleton discovery
# ══════════════════════════════════════════════════════════════════════════════

func _find_skeleton() -> void:
	var parent := get_parent()
	if parent:
		_skeleton = _find_child_of_type(parent, "Skeleton3D") as Skeleton3D
	if not _skeleton:
		push_warning("[GestureAnimator] Could not find Skeleton3D under parent.")
		return

	_left_arm_idx      = _skeleton.find_bone("mixamorig_LeftArm")
	_left_forearm_idx  = _skeleton.find_bone("mixamorig_LeftForeArm")
	_left_hand_idx     = _skeleton.find_bone("mixamorig_LeftHand")
	_right_arm_idx     = _skeleton.find_bone("mixamorig_RightArm")
	_right_forearm_idx = _skeleton.find_bone("mixamorig_RightForeArm")
	_right_hand_idx    = _skeleton.find_bone("mixamorig_RightHand")

	# Pre-compute rest directions (shoulder → forearm in skeleton space).
	if _left_arm_idx >= 0 and _left_forearm_idx >= 0:
		var la := _skeleton.get_bone_global_rest(_left_arm_idx).origin
		var lf := _skeleton.get_bone_global_rest(_left_forearm_idx).origin
		_left_rest_dir = (lf - la).normalized()

	if _right_arm_idx >= 0 and _right_forearm_idx >= 0:
		var ra := _skeleton.get_bone_global_rest(_right_arm_idx).origin
		var rf := _skeleton.get_bone_global_rest(_right_forearm_idx).origin
		_right_rest_dir = (rf - ra).normalized()

	print("[GestureAnimator] Skeleton found — L_arm=%d L_forearm=%d L_hand=%d  R_arm=%d R_forearm=%d R_hand=%d" % [
		_left_arm_idx, _left_forearm_idx, _left_hand_idx,
		_right_arm_idx, _right_forearm_idx, _right_hand_idx])
	print("[GestureAnimator] Rest dirs: L=%s  R=%s" % [_left_rest_dir, _right_rest_dir])
	# Diagnostic: print shoulder positions so you can verify skeleton space units.
	if _left_arm_idx >= 0:
		print("[GestureAnimator] Left  shoulder pos (skel space): %s" % _skeleton.get_bone_global_rest(_left_arm_idx).origin)
	if _right_arm_idx >= 0:
		print("[GestureAnimator] Right shoulder pos (skel space): %s" % _skeleton.get_bone_global_rest(_right_arm_idx).origin)


func _find_child_of_type(node: Node, type_name: String) -> Node:
	if node is Skeleton3D and type_name == "Skeleton3D":
		return node
	for child in node.get_children():
		var found := _find_child_of_type(child, type_name)
		if found:
			return found
	return null


# ══════════════════════════════════════════════════════════════════════════════
# Data loading
# ══════════════════════════════════════════════════════════════════════════════

## Convert an array of editor keyframe dicts [{t,x,y,z}] to Vector3 skeleton-space positions.
##
## Axis conventions (Mixamo rig in Godot):
##   Skeleton X  = lateral  (positive = avatar's anatomical left)
##   Skeleton Y  = height   (positive = up)
##   Skeleton Z  = depth    (NEGATIVE = in front of avatar; positive = behind)
##
## Editor axes (Three.js, camera looking toward +Z):
##   Editor X  = lateral    → Skeleton X  (same sign)
##   Editor Y  = height     → Skeleton Y  (same sign)
##   Editor Z  = toward cam → Skeleton -Z (negated: editor +Z in front = skeleton -Z)
##
## editor_gesture_offset is added after scaling so the gesture floats in front
## of the avatar (Z < 0) at a sensible height even when drawn at Y ≈ 0 in the editor.
## NOTE: This legacy version strips t-values. Use _keyframes_to_timed_vectors for
## editor gestures so authored timing is preserved.
func _keyframes_to_vectors(kfs: Array, sc: float) -> Array:
	var result: Array[Vector3] = []
	# Sort by t so out-of-order edits still play correctly.
	var sorted := kfs.duplicate()
	sorted.sort_custom(func(a, b): return a.get("t", 0.0) < b.get("t", 0.0))
	for kf in sorted:
		if sc == 1.0:
			# Authored in-Godot: coordinates are exactly skeleton space.
			result.append(Vector3(
				float(kf.get("x", 0.0)),
				float(kf.get("y", 0.0)),
				float(kf.get("z", 0.0))
			))
		else:
			# Authored in web editor: apply scale, flip Z, add offset.
			var x: float = float(kf.get("x", 0.0)) * sc
			var y: float = float(kf.get("y", 0.0)) * sc
			var z: float = -float(kf.get("z", 0.0)) * sc
			result.append(Vector3(
				x + editor_gesture_offset.x,
				y + editor_gesture_offset.y,
				z + editor_gesture_offset.z
			))
	if result.size() > 0:
		print("[GestureAnimator] Editor KFs converted — first=%s  last=%s  (scale=%.0f, offset=%s)" % [
			result[0], result[result.size()-1], sc, editor_gesture_offset if sc != 1.0 else Vector3.ZERO])
	return result


## Convert editor keyframe dicts [{t,x,y,z}] to timed Vector3 entries:
## [{"t": float, "pos": Vector3}] sorted by t.
## Preserves the authored timing so _interpolate_keyframes works correctly.
func _keyframes_to_timed_vectors(kfs: Array, sc: float) -> Array:
	var result: Array = []
	var sorted := kfs.duplicate()
	sorted.sort_custom(func(a, b): return a.get("t", 0.0) < b.get("t", 0.0))
	for kf in sorted:
		var pos: Vector3
		if sc == 1.0:
			# Authored in-Godot: coordinates are exactly skeleton space.
			pos = Vector3(
				float(kf.get("x", 0.0)),
				float(kf.get("y", 0.0)),
				float(kf.get("z", 0.0))
			)
		else:
			# Authored in web editor: apply scale, flip Z, add offset.
			var x: float = float(kf.get("x", 0.0)) * sc
			var y: float = float(kf.get("y", 0.0)) * sc
			var z: float = -float(kf.get("z", 0.0)) * sc
			pos = Vector3(
				x + editor_gesture_offset.x,
				y + editor_gesture_offset.y,
				z + editor_gesture_offset.z
			)
		result.append({"t": float(kf.get("t", 0.0)), "pos": pos})
	if result.size() > 0:
		print("[GestureAnimator] Timed KFs — count=%d  t[0]=%.3f  t[last]=%.3f  (scale=%.0f)" % [
			result.size(), result[0]["t"], result[result.size()-1]["t"], sc])
	return result


## Load hand-authored gesture keyframes from gesture_editor_data.json.
func _load_editor_gestures() -> void:
	_editor_gestures.clear()
	if not FileAccess.file_exists(EDITOR_DATA_PATH):
		# File may not exist yet (editor hasn't exported anything)
		return
	var file := FileAccess.open(EDITOR_DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("[GestureAnimator] Could not open: " + EDITOR_DATA_PATH)
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("[GestureAnimator] Editor data JSON parse error: " + json.get_error_message())
		file.close()
		return
	file.close()
	var data = json.get_data()
	if not data is Array:
		push_error("[GestureAnimator] gesture_editor_data.json: unexpected root type.")
		return
	for entry in data:
		var gname: String = entry.get("name", "")
		if gname != "":
			_editor_gestures[gname] = entry
	print("[GestureAnimator] Loaded %d editor gesture(s) from gesture_editor_data.json." % _editor_gestures.size())


func _load_templates() -> void:
	_templates.clear()
	if not FileAccess.file_exists(GESTURE_DATA_PATH):
		push_error("[GestureAnimator] Template file not found: " + GESTURE_DATA_PATH)
		return
	var file := FileAccess.open(GESTURE_DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("[GestureAnimator] Failed to open: " + GESTURE_DATA_PATH)
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("[GestureAnimator] JSON parse error: " + json.get_error_message())
		file.close()
		return
	file.close()
	var data = json.get_data()
	if not data is Array:
		push_error("[GestureAnimator] Unexpected JSON root type.")
		return
	for entry in data:
		var gesture_name: String = entry.get("name", "")
		var raw_pts = entry.get("points", [])
		var pts: Array[Vector3] = []
		for p in raw_pts:
			pts.append(Vector3(p["x"], p["y"], p["z"]))
		_templates[gesture_name] = pts
	print("[GestureAnimator] Loaded %d templates." % _templates.size())


func _load_gesture_config() -> void:
	_gesture_defs.clear()
	if not FileAccess.file_exists(GESTURE_CONFIG_PATH):
		push_error("[GestureAnimator] Config not found: " + GESTURE_CONFIG_PATH)
		return
	var file := FileAccess.open(GESTURE_CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("[GestureAnimator] Failed to open config: " + GESTURE_CONFIG_PATH)
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("[GestureAnimator] Config parse error: " + json.get_error_message())
		file.close()
		return
	file.close()
	var data = json.get_data()
	if not data is Array:
		push_error("[GestureAnimator] Unexpected config root type.")
		return
	for entry in data:
		var gesture_name: String = entry.get("name", "")
		if gesture_name != "":
			_gesture_defs[gesture_name] = entry
	print("[GestureAnimator] Loaded %d gesture definitions." % _gesture_defs.size())
