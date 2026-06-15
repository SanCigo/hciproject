extends Node

## ════════════════════════════════════════════════════════════════════════════
## In-Godot Gesture Editor
## ════════════════════════════════════════════════════════════════════════════
## Open Scenes/gesture_editor.tscn and press F6.
##
## Waypoints are placed IN WORLD SPACE on the actual avatar. The skeleton-space
## conversion is exact (skeleton.to_local), so what you see is exactly what
## gesture_animator will do at runtime. No coordinate guesswork.
##
## Controls:
##   Right-drag     — orbit camera
##   Scroll         — zoom
##   Shift+LMB      — add waypoint on the active drawing plane
##   LMB on sphere  — select waypoint (turns gold)
##   Drag selected  — move waypoint live; arm updates every frame
##   Delete         — remove selected waypoint
##   Space          — play / pause animation preview
##   Escape         — deselect

const SAVE_PATH  := "res://gestures/gesture_editor_data.json"
const AVATAR_SCN := "res://Scenes/avatar.tscn"

const C_LEFT  := Color(0.28, 0.55, 1.00)  # blue  – left hand
const C_RIGHT := Color(1.00, 0.45, 0.10)  # orange – right hand
const C_SEL   := Color(1.00, 0.95, 0.15)  # gold  – selected

const SPHERE_R := 0.045  # visual radius (m)
const HIT_R    := 0.08   # click-detection radius (m)

# ── Scene nodes ───────────────────────────────────────────────────────────────
var _cam:    Camera3D     = null
var _world:  Node3D       = null
var _avatar: Node         = null
var _skel:   Skeleton3D   = null
var _ga:     Node         = null   ## GestureAnimator reference
var _pvis:   MeshInstance3D = null ## drawing-plane indicator quad

# ── UI ────────────────────────────────────────────────────────────────────────
var _name_in:  LineEdit       = null
var _gl:       VBoxContainer  = null  # gesture list
var _kfl:      VBoxContainer  = null  # keyframe list
var _status:   Label          = null
var _play_btn: Button         = null
var _hbtns:    Dictionary     = {}    # hand str → Button
var _pbtns:    Dictionary     = {}    # plane str → Button

# ── Gesture data ──────────────────────────────────────────────────────────────
## Array[ { "name": String, "left": Array[Vector3], "right": Array[Vector3] } ]
## Positions are in SKELETON-LOCAL SPACE (same units as get_bone_global_pose).
var _gestures: Array  = []
var _cur:      int    = -1
var _hand:     String = "right"   # "left" | "right" | "both"
var _plane:    String = "xy"      # "xy" (front) | "xz" (floor) | "yz" (side)

# ── Gizmos ────────────────────────────────────────────────────────────────────
var _ln: Array = []  ## MeshInstance3D per left waypoint
var _rn: Array = []  ## MeshInstance3D per right waypoint
var _sel_hand: String = ""
var _sel_idx:  int    = -1

# ── Camera orbit ──────────────────────────────────────────────────────────────
var _tgt:   Vector3 = Vector3(0.0, 1.2, 0.0)
var _yaw:   float   = 0.0
var _pitch: float   = -12.0
var _dist:  float   = 3.0
var _orb:   bool    = false
var _olast: Vector2

# ── Waypoint drag ─────────────────────────────────────────────────────────────
var _dragging: bool  = false
var _dplane:   Plane

# ── Playback ──────────────────────────────────────────────────────────────────
var _playing: bool  = false
var _pt:      float = 0.0
var _spd:     float = 1.0
var _dur:     float = 2.5  # mirror gesture_animator default


# ════════════════════════════════════════════════════════════════════════════
# Lifecycle
# ════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_build_scene()
	_build_ui()
	_load_json()
	_refresh_gest_list()
	_refresh_plane_vis()

	# Wait for avatar._ready() to dynamically add GestureAnimator.
	await get_tree().process_frame
	await get_tree().process_frame
	_find_refs()
	_update_cam()
	_set_status("Shift+Click to place waypoints   ·   Right-drag to orbit")

	# Run AFTER GestureAnimator (priority 100) so our preview_positions call wins.
	process_priority = 150


func _process(delta: float) -> void:
	if _playing:
		_pt += delta * _spd
		var t := clampf(_pt / _dur, 0.0, 1.0)
		_preview_at(t)
		if t >= 1.0:
			_stop_play()
	else:
		# Keep arms frozen at current waypoint even as idle animation runs.
		if _ga:
			var ll := _cur_left()
			var rl := _cur_right()
			var lp: Variant = ll[ll.size() - 1] if ll.size() > 0 else null
			var rp: Variant = rl[rl.size() - 1] if rl.size() > 0 else null
			if _sel_hand == "left"  and _sel_idx >= 0: lp = _get_wp("left",  _sel_idx)
			if _sel_hand == "right" and _sel_idx >= 0: rp = _get_wp("right", _sel_idx)
			_ga.preview_positions(lp, rp)


# ════════════════════════════════════════════════════════════════════════════
# Input
# ════════════════════════════════════════════════════════════════════════════

func _unhandled_input(event: InputEvent) -> void:
	# Camera zoom
	if event is InputEventMouseButton:
		var mbe := event as InputEventMouseButton
		match mbe.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_dist = maxf(_dist - 0.25, 0.4);  _update_cam()
			MOUSE_BUTTON_WHEEL_DOWN:
				_dist = minf(_dist + 0.25, 12.0); _update_cam()
			MOUSE_BUTTON_RIGHT:
				_orb = mbe.pressed
				if _orb: _olast = mbe.position
			MOUSE_BUTTON_LEFT:
				if mbe.pressed:
					_lmb_down(mbe.position, mbe.shift_pressed)
				else:
					_dragging = false

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orb:
			_yaw   -= mm.relative.x * 0.4
			_pitch  = clampf(_pitch - mm.relative.y * 0.3, -80.0, 80.0)
			_update_cam()
		elif _dragging:
			_do_drag(mm.position)

	elif event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			match ke.keycode:
				KEY_DELETE: _delete_selected()
				KEY_SPACE:  _toggle_play()
				KEY_ESCAPE: _deselect()


# ════════════════════════════════════════════════════════════════════════════
# Mouse interaction
# ════════════════════════════════════════════════════════════════════════════

func _lmb_down(mpos: Vector2, shift: bool) -> void:
	if _cur < 0:
		_set_status("Create or select a gesture first.")
		return

	# Try to pick an existing waypoint sphere.
	var hit := _pick(mpos)
	if not hit.is_empty():
		_select(hit["hand"], hit["idx"])
		# Drag plane: faces camera, passes through the sphere world position.
		var wp_world := _s2w(_get_wp(hit["hand"], hit["idx"]))
		_dplane  = Plane((_cam.global_position - wp_world).normalized(), wp_world)
		_dragging = true
		return

	# Shift+LMB → add a new waypoint at the ray–plane intersection.
	if shift:
		var wpos: Variant = _ray_hit(mpos, _draw_plane())
		if wpos == null:
			return
		_add_wp(_w2s(wpos))


func _do_drag(mpos: Vector2) -> void:
	if _sel_hand.is_empty():
		return
	var wpos: Variant = _ray_hit(mpos, _dplane)
	if wpos == null:
		return
	var sp := _w2s(wpos)
	_set_wp(_sel_hand, _sel_idx, sp)
	_move_sphere(_sel_hand, _sel_idx)
	_refresh_kf_list()


# ════════════════════════════════════════════════════════════════════════════
# Picking / ray helpers
# ════════════════════════════════════════════════════════════════════════════

## Ray–sphere test. Returns {hand, idx} of nearest hit, or {} if none.
func _pick(mpos: Vector2) -> Dictionary:
	if not _cam:
		return {}
	var ro := _cam.project_ray_origin(mpos)
	var rd := _cam.project_ray_normal(mpos)
	var best := INF
	var res  := {}
	for hand in ["left", "right"]:
		var nodes := _ln if hand == "left" else _rn
		for i in range(nodes.size()):
			var mi := nodes[i] as MeshInstance3D
			if not mi:
				continue
			var c  := mi.global_position
			var oc := ro - c
			var b  := oc.dot(rd)
			var disc := b * b - (oc.length_squared() - HIT_R * HIT_R)
			if disc < 0.0:
				continue
			var t := -b - sqrt(disc)
			if t < 0.0: t = -b + sqrt(disc)
			if t < 0.0 or t >= best:
				continue
			best = t
			res  = {"hand": hand, "idx": i}
	return res


## Ray-plane intersection. Returns Vector3 or null.
func _ray_hit(mpos: Vector2, plane: Plane) -> Variant:
	if not _cam:
		return null
	return plane.intersects_ray(
		_cam.project_ray_origin(mpos),
		_cam.project_ray_normal(mpos))


## Returns the active drawing plane in world space.
func _draw_plane() -> Plane:
	# All planes are centred at avatar shoulder height.
	var c := Vector3(0.0, 1.4, 0.0)
	match _plane:
		"xy": return Plane(Vector3(0, 0, 1), c)   # vertical, faces camera
		"xz": return Plane(Vector3(0, 1, 0), c)   # horizontal at shoulder height
		_:    return Plane(Vector3(1, 0, 0), c)   # vertical, faces right


# ════════════════════════════════════════════════════════════════════════════
# Coordinate helpers — the WYSIWYG guarantee
# ════════════════════════════════════════════════════════════════════════════

## World → skeleton local. Same space that get_bone_global_pose() uses.
func _w2s(world: Vector3) -> Vector3:
	return _skel.to_local(world) if _skel else world

## Skeleton local → world.
func _s2w(skel: Vector3) -> Vector3:
	return _skel.to_global(skel) if _skel else skel


# ════════════════════════════════════════════════════════════════════════════
# Data helpers
# ════════════════════════════════════════════════════════════════════════════

func _cur_gest() -> Dictionary:
	return _gestures[_cur] if (_cur >= 0 and _cur < _gestures.size()) else {}

func _cur_left()  -> Array: return _cur_gest().get("left",  []) as Array
func _cur_right() -> Array: return _cur_gest().get("right", []) as Array

func _get_wp(hand: String, idx: int) -> Vector3:
	var a := _cur_left() if hand == "left" else _cur_right()
	return a[idx] as Vector3 if (idx >= 0 and idx < a.size()) else Vector3.ZERO

func _set_wp(hand: String, idx: int, pos: Vector3) -> void:
	var g := _cur_gest()
	if g.is_empty(): return
	var key := "left" if hand == "left" else "right"
	if idx >= 0 and idx < (g[key] as Array).size():
		(g[key] as Array)[idx] = pos

func _add_wp(skel_pos: Vector3) -> void:
	var g := _cur_gest()
	if g.is_empty(): return
	var hands: Array = []
	if _hand != "right": hands.append("left")
	if _hand != "left":  hands.append("right")
	for h in hands:
		var key := "left" if h == "left" else "right"
		(g[key] as Array).append(skel_pos)
		var nodes := _ln if h == "left" else _rn
		nodes.append(_make_sphere(h == "left"))
		_move_sphere(h, nodes.size() - 1)
	_deselect()
	_refresh_kf_list()

func _delete_selected() -> void:
	if _sel_hand.is_empty() or _sel_idx < 0: return
	var g := _cur_gest()
	if g.is_empty(): return
	var key   := "left" if _sel_hand == "left" else "right"
	var arr   := g[key] as Array
	var nodes := _ln    if _sel_hand == "left" else _rn
	if _sel_idx >= arr.size(): return
	arr.remove_at(_sel_idx)
	if _sel_idx < nodes.size():
		(nodes[_sel_idx] as MeshInstance3D).queue_free()
		nodes.remove_at(_sel_idx)
	_deselect()
	_rebuild_spheres()
	_refresh_kf_list()


# ════════════════════════════════════════════════════════════════════════════
# Selection
# ════════════════════════════════════════════════════════════════════════════

func _select(hand: String, idx: int) -> void:
	_deselect()
	_sel_hand = hand; _sel_idx = idx
	_tint(hand, idx, C_SEL)
	var p := _get_wp(hand, idx)
	_set_status("%s[%d]  skel=(%.1f, %.1f, %.1f)" % [hand, idx, p.x, p.y, p.z])

func _deselect() -> void:
	if not _sel_hand.is_empty() and _sel_idx >= 0:
		_tint(_sel_hand, _sel_idx, C_LEFT if _sel_hand == "left" else C_RIGHT)
	_sel_hand = ""; _sel_idx = -1

func _tint(hand: String, idx: int, col: Color) -> void:
	var nodes := _ln if hand == "left" else _rn
	if idx < 0 or idx >= nodes.size(): return
	var mi := nodes[idx] as MeshInstance3D
	if mi: (mi.get_surface_override_material(0) as StandardMaterial3D).albedo_color = col


# ════════════════════════════════════════════════════════════════════════════
# Arm preview
# ════════════════════════════════════════════════════════════════════════════

func _preview_at(t: float) -> void:
	if not _ga: return
	var ll := _cur_left(); var rl := _cur_right()
	var lp: Variant = _lerp_pts(ll, t) if ll.size() > 0 else null
	var rp: Variant = _lerp_pts(rl, t) if rl.size() > 0 else null
	_ga.preview_positions(lp, rp)

func _lerp_pts(pts: Array, t: float) -> Vector3:
	if pts.size() == 1: return pts[0] as Vector3
	var f  := t * float(pts.size() - 1)
	var lo := int(floor(f))
	var hi := mini(lo + 1, pts.size() - 1)
	return (pts[lo] as Vector3).lerp(pts[hi] as Vector3, f - float(lo))


# ════════════════════════════════════════════════════════════════════════════
# Playback
# ════════════════════════════════════════════════════════════════════════════

func _toggle_play() -> void:
	if _playing: _stop_play()
	else:
		_playing = true; _pt = 0.0
		if _play_btn: _play_btn.text = "⏹ Stop"

func _stop_play() -> void:
	_playing = false; _pt = 0.0
	if _play_btn: _play_btn.text = "▶ Play"


# ════════════════════════════════════════════════════════════════════════════
# Gizmo management
# ════════════════════════════════════════════════════════════════════════════

func _make_sphere(is_left: bool) -> MeshInstance3D:
	var mi  := MeshInstance3D.new()
	var sm  := SphereMesh.new()
	sm.radius = SPHERE_R; sm.height = SPHERE_R * 2.0
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = C_LEFT if is_left else C_RIGHT
	mat.roughness = 0.3; mat.metallic = 0.4
	mi.set_surface_override_material(0, mat)
	_world.add_child(mi)
	return mi

func _move_sphere(hand: String, idx: int) -> void:
	var nodes := _ln if hand == "left" else _rn
	if idx < 0 or idx >= nodes.size(): return
	var mi := nodes[idx] as MeshInstance3D
	if mi: mi.global_position = _s2w(_get_wp(hand, idx))

func _rebuild_spheres() -> void:
	for n in _ln: if n: (n as MeshInstance3D).queue_free()
	for n in _rn: if n: (n as MeshInstance3D).queue_free()
	_ln.clear(); _rn.clear()
	var g := _cur_gest()
	if g.is_empty(): return
	for i in range((_cur_left() as Array).size()):
		_ln.append(_make_sphere(true));  _move_sphere("left",  i)
	for i in range((_cur_right() as Array).size()):
		_rn.append(_make_sphere(false)); _move_sphere("right", i)


# ════════════════════════════════════════════════════════════════════════════
# Drawing-plane visual
# ════════════════════════════════════════════════════════════════════════════

func _refresh_plane_vis() -> void:
	if not _pvis: return
	_pvis.position = Vector3(0, 1.4, 0)
	match _plane:
		"xy": _pvis.rotation = Vector3(0, 0, 0)
		"xz": _pvis.rotation = Vector3(-PI * 0.5, 0, 0)
		"yz": _pvis.rotation = Vector3(0, PI * 0.5, 0)
	for p in _pbtns:
		(_pbtns[p] as Button).button_pressed = (p == _plane)


# ════════════════════════════════════════════════════════════════════════════
# UI refresh
# ════════════════════════════════════════════════════════════════════════════

func _refresh_gest_list() -> void:
	if not _gl: return
	for c in _gl.get_children(): c.queue_free()
	for i in range(_gestures.size()):
		var b := Button.new()
		b.text = _gestures[i].get("name", "gesture_%d" % i)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = (i == _cur)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_gest_select.bind(i))
		_gl.add_child(b)

func _refresh_kf_list() -> void:
	if not _kfl: return
	for c in _kfl.get_children(): c.queue_free()
	var g := _cur_gest()
	if g.is_empty(): return
	for hand in ["left", "right"]:
		var arr := (g["left"] if hand == "left" else g["right"]) as Array
		if arr.is_empty(): continue
		var hl := Label.new()
		hl.text = ("◉ L  (%d pts)" if hand == "left" else "◉ R  (%d pts)") % arr.size()
		hl.add_theme_color_override("font_color", C_LEFT if hand == "left" else C_RIGHT)
		_kfl.add_child(hl)
		for i in range(arr.size()):
			var p := arr[i] as Vector3
			var row := HBoxContainer.new()
			var sb := Button.new()
			sb.text = "[%d]" % i
			sb.custom_minimum_size.x = 38
			sb.pressed.connect(func(): _select(hand, i))
			row.add_child(sb)
			var lbl := Label.new()
			lbl.text = "(%.0f,%.0f,%.0f)" % [p.x, p.y, p.z]
			lbl.add_theme_font_size_override("font_size", 11)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)
			var db := Button.new()
			db.text = "✕"; db.custom_minimum_size.x = 28
			var _h: String = hand; var _i: int = i
			db.pressed.connect(func(): _select(_h, _i); _delete_selected())
			row.add_child(db)
			_kfl.add_child(row)


# ════════════════════════════════════════════════════════════════════════════
# Event handlers
# ════════════════════════════════════════════════════════════════════════════

func _on_add_gesture() -> void:
	if not _name_in: return
	var n := _name_in.text.strip_edges()
	if n.is_empty(): n = "gesture_%d" % _gestures.size()
	_gestures.append({"name": n, "left": [], "right": []})
	_cur = _gestures.size() - 1
	_refresh_gest_list(); _rebuild_spheres(); _refresh_kf_list()
	_set_status("'%s' created — Shift+Click to place waypoints." % n)

func _on_gest_select(idx: int) -> void:
	_cur = idx
	_refresh_gest_list(); _rebuild_spheres(); _refresh_kf_list(); _deselect()
	_set_status("Gesture: " + _gestures[idx].get("name", "?"))

func _on_hand_btn(hand: String) -> void:
	_hand = hand
	for h in _hbtns: (_hbtns[h] as Button).button_pressed = (h == hand)

func _on_plane_btn(plane: String) -> void:
	_plane = plane
	_refresh_plane_vis()

func _on_delete_gesture() -> void:
	if _cur < 0 or _cur >= _gestures.size(): return
	_gestures.remove_at(_cur)
	_cur = mini(_cur, _gestures.size() - 1)
	_rebuild_spheres(); _refresh_gest_list(); _refresh_kf_list(); _deselect()

func _on_clear(hand: String) -> void:
	var g := _cur_gest()
	if g.is_empty(): return
	if hand != "right": (g["left"]  as Array).clear()
	if hand != "left":  (g["right"] as Array).clear()
	_rebuild_spheres(); _refresh_kf_list(); _deselect()


# ════════════════════════════════════════════════════════════════════════════
# JSON persistence
# ════════════════════════════════════════════════════════════════════════════

func _load_json() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f: return
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		push_error("[GestureEditor] JSON parse error: " + json.get_error_message())
		f.close(); return
	f.close()
	var data = json.get_data()
	if not data is Array: return
	_gestures.clear()
	for entry in (data as Array):
		var g := {"name": entry.get("name", "unnamed"), "left": [], "right": []}
		# scale=1.0 means in-Godot editor format (skeleton space, no conversion).
		# scale=100.0 (or missing) means old browser-editor format (×100 applied on load).
		var sc := float(entry.get("scale", 100.0))
		for kf in (entry.get("left_keyframes",  []) as Array):
			(g["left"]  as Array).append(Vector3(float(kf.get("x",0))*sc, float(kf.get("y",0))*sc, float(kf.get("z",0))*sc))
		for kf in (entry.get("right_keyframes", []) as Array):
			(g["right"] as Array).append(Vector3(float(kf.get("x",0))*sc, float(kf.get("y",0))*sc, float(kf.get("z",0))*sc))
		_gestures.append(g)
	print("[GestureEditor] Loaded %d gesture(s)." % _gestures.size())

func _save_json() -> void:
	var arr := []
	for g in _gestures:
		var ll := g["left"] as Array;  var rl := g["right"] as Array
		var e  := {"name": g.get("name","unnamed"), "scale": 1.0,
				   "left_keyframes": [], "right_keyframes": []}
		var nl := ll.size(); var nr := rl.size()
		for i in range(nl):
			var p := ll[i] as Vector3
			var t := 0.0 if nl <= 1 else float(i) / float(nl - 1)
			(e["left_keyframes"]  as Array).append({"t": t, "x": p.x, "y": p.y, "z": p.z})
		for i in range(nr):
			var p := rl[i] as Vector3
			var t := 0.0 if nr <= 1 else float(i) / float(nr - 1)
			(e["right_keyframes"] as Array).append({"t": t, "x": p.x, "y": p.y, "z": p.z})
		arr.append(e)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not f:
		_set_status("ERROR: Cannot write " + SAVE_PATH); return
	f.store_string(JSON.stringify(arr, "  ")); f.close()
	_set_status("Saved %d gesture(s) ✓" % _gestures.size())
	print("[GestureEditor] Saved to " + SAVE_PATH)


# ════════════════════════════════════════════════════════════════════════════
# Scene building
# ════════════════════════════════════════════════════════════════════════════

func _build_scene() -> void:
	_world = Node3D.new(); _world.name = "World"; add_child(_world)

	# Camera
	_cam = Camera3D.new(); _cam.name = "Camera3D"; _cam.fov = 50.0
	_world.add_child(_cam)

	# Key light
	var sun := DirectionalLight3D.new()
	sun.transform = Transform3D(Basis.from_euler(Vector3(-0.65, 0.55, 0.0)), Vector3(0,3,0))
	sun.shadow_enabled = true; _world.add_child(sun)

	# Fill light
	var fill := DirectionalLight3D.new()
	fill.transform = Transform3D(Basis.from_euler(Vector3(0.25, -2.1, 0.0)), Vector3.ZERO)
	fill.light_energy = 0.4; _world.add_child(fill)

	# Floor
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(8, 8); fm.mesh = pm
	var fmat := StandardMaterial3D.new(); fmat.albedo_color = Color(0.13, 0.13, 0.16)
	fm.set_surface_override_material(0, fmat); _world.add_child(fm)

	# Avatar
	var ps := load(AVATAR_SCN) as PackedScene
	if ps:
		_avatar = ps.instantiate(); _avatar.name = "Avatar"; _world.add_child(_avatar)
	else:
		push_error("[GestureEditor] Cannot load avatar: " + AVATAR_SCN)

	# Drawing-plane indicator (transparent quad)
	_pvis = MeshInstance3D.new(); _pvis.name = "PlaneIndicator"
	var qm := QuadMesh.new(); qm.size = Vector2(2.4, 2.4); _pvis.mesh = qm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.35, 0.65, 1.0, 0.09)
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	_pvis.set_surface_override_material(0, pmat); _world.add_child(_pvis)


# ════════════════════════════════════════════════════════════════════════════
# UI building
# ════════════════════════════════════════════════════════════════════════════

func _build_ui() -> void:
	var cl := CanvasLayer.new(); cl.name = "UI"; add_child(cl)

	# ── Left sidebar ──────────────────────────────────────────────────────────
	var lp := PanelContainer.new()
	lp.anchor_left = 0.0; lp.anchor_right = 0.0
	lp.anchor_top = 0.0; lp.anchor_bottom = 1.0
	lp.offset_left = 0; lp.offset_top = 0
	lp.offset_right = 180; lp.offset_bottom = -30
	cl.add_child(lp)

	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 5)
	lp.add_child(lv)

	_mk_title(lv, "✦ Gesture Editor")
	lv.add_child(HSeparator.new())

	# Gesture name + Add
	var r1 := HBoxContainer.new(); lv.add_child(r1)
	_name_in = LineEdit.new()
	_name_in.placeholder_text = "gesture name…"
	_name_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_in.text_submitted.connect(func(_t): _on_add_gesture())
	r1.add_child(_name_in)
	var ab := Button.new(); ab.text = "+ New"; ab.pressed.connect(_on_add_gesture)
	r1.add_child(ab)

	_mk_lbl(lv, "Gestures:")
	var sc1 := ScrollContainer.new()
	sc1.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc1.custom_minimum_size.y = 90
	lv.add_child(sc1)
	_gl = VBoxContainer.new(); _gl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc1.add_child(_gl)

	var dg := Button.new(); dg.text = "🗑 Delete Gesture"; dg.pressed.connect(_on_delete_gesture)
	lv.add_child(dg)
	lv.add_child(HSeparator.new())

	# Hand mode
	_mk_lbl(lv, "Active Hand:")
	var hr := HBoxContainer.new(); lv.add_child(hr)
	var hgrp := ButtonGroup.new()
	for h in ["left", "right", "both"]:
		var b := Button.new()
		b.text = h.capitalize(); b.toggle_mode = true; b.button_group = hgrp
		b.button_pressed = (h == _hand)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggled.connect(func(on, hh=h): if on: _on_hand_btn(hh))
		hr.add_child(b); _hbtns[h] = b
	lv.add_child(HSeparator.new())

	# Playback
	_mk_lbl(lv, "Playback:")
	_play_btn = Button.new(); _play_btn.text = "▶ Play"
	_play_btn.pressed.connect(_toggle_play); lv.add_child(_play_btn)
	var spr := HBoxContainer.new(); lv.add_child(spr)
	_mk_lbl(spr, "Speed:")
	var ss := HSlider.new()
	ss.min_value = 0.1; ss.max_value = 4.0; ss.step = 0.1; ss.value = 1.0
	ss.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ss.value_changed.connect(func(v): _spd = v); spr.add_child(ss)
	lv.add_child(HSeparator.new())

	# Save
	var sv := Button.new(); sv.text = "⬇ Save JSON"; sv.pressed.connect(_save_json)
	lv.add_child(sv)

	# ── Right sidebar ─────────────────────────────────────────────────────────
	var rp := PanelContainer.new()
	rp.anchor_left = 1.0; rp.anchor_right = 1.0
	rp.anchor_top = 0.0; rp.anchor_bottom = 1.0
	rp.offset_left = -180; rp.offset_top = 0
	rp.offset_right = 0; rp.offset_bottom = -30
	cl.add_child(rp)

	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 5)
	rp.add_child(rv)

	_mk_title(rv, "Drawing Plane")
	rv.add_child(HSeparator.new())

	var pgrp := ButtonGroup.new()
	for pd: Array in [["xy", "Front (XY)"], ["xz", "Floor (XZ)"], ["yz", "Side (YZ)"]]:
		var b := Button.new()
		b.text = pd[1]; b.toggle_mode = true; b.button_group = pgrp
		b.button_pressed = (pd[0] == _plane)
		b.toggled.connect(func(on, pp=pd[0]): if on: _on_plane_btn(pp))
		rv.add_child(b); _pbtns[pd[0]] = b

	rv.add_child(HSeparator.new())
	_mk_lbl(rv, "Waypoints (current gesture):")
	var sc2 := ScrollContainer.new()
	sc2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(sc2)
	_kfl = VBoxContainer.new(); _kfl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc2.add_child(_kfl)

	rv.add_child(HSeparator.new())
	_mk_lbl(rv, "Clear waypoints:")
	var cr := HBoxContainer.new(); rv.add_child(cr)
	for h in ["Left", "Right", "Both"]:
		var b := Button.new(); b.text = h
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_clear.bind(h.to_lower())); cr.add_child(b)

	# ── Status bar ────────────────────────────────────────────────────────────
	var sb := PanelContainer.new()
	sb.anchor_left = 0.0; sb.anchor_right = 1.0
	sb.anchor_top = 1.0; sb.anchor_bottom = 1.0
	sb.offset_left = 180; sb.offset_top = -30
	sb.offset_right = -180; sb.offset_bottom = 0
	cl.add_child(sb)
	_status = Label.new()
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sb.add_child(_status)


func _mk_title(parent: Control, text: String) -> void:
	var l := Label.new(); l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 15)
	parent.add_child(l)

func _mk_lbl(parent: Control, text: String) -> Label:
	var l := Label.new(); l.text = text; parent.add_child(l); return l


# ════════════════════════════════════════════════════════════════════════════
# Camera
# ════════════════════════════════════════════════════════════════════════════

func _update_cam() -> void:
	if not _cam: return
	var pr := deg_to_rad(_pitch); var yr := deg_to_rad(_yaw)
	var off := Vector3(
		_dist * cos(pr) * sin(yr),
		_dist * sin(pr),
		_dist * cos(pr) * cos(yr))
	_cam.global_position = _tgt + off
	_cam.look_at(_tgt, Vector3.UP)


# ════════════════════════════════════════════════════════════════════════════
# Skeleton / animator discovery
# ════════════════════════════════════════════════════════════════════════════

func _find_refs() -> void:
	if not _avatar: return
	_skel = _find_type(_avatar, "Skeleton3D") as Skeleton3D
	if _skel:
		print("[GestureEditor] Skeleton: %s" % _skel.get_path())
	else:
		push_error("[GestureEditor] Skeleton3D not found in avatar!")

	# GestureAnimator is dynamically added by avatar._ready()
	for child in _avatar.get_children():
		if child.name == "GestureAnimator":
			_ga = child; break
		if child.get_script():
			var sp: String = child.get_script().resource_path
			if sp.ends_with("gesture_animator.gd"):
				_ga = child; break
	if _ga:
		print("[GestureEditor] GestureAnimator ready.")
	else:
		push_warning("[GestureEditor] GestureAnimator not found — arm preview disabled.")

func _find_type(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name: return node
	for c in node.get_children():
		var found := _find_type(c, type_name)
		if found: return found
	return null

func _set_status(msg: String) -> void:
	if _status: _status.text = msg
