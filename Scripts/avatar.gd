extends Node3D
class_name Avatar

signal animation_finished()

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var tts_player: Node = $TTSPlayer
@onready var gesture_animator: Node = $GestureAnimator


func _ready() -> void:
	if not tts_player:
		var tts_script = load("res://Scripts/tts_player.gd")
		if tts_script:
			tts_player = Node.new()
			tts_player.set_script(tts_script)
			tts_player.name = "TTSPlayer"
			add_child(tts_player)
			print("[Avatar] Dynamically added TTSPlayer node.")
		else:
			push_warning("[Avatar] Could not load tts_player.gd script.")
	
	animation_player.play("idle")

	# Dynamically add GestureAnimator if not present in the scene tree.
	if not gesture_animator:
		var anim_script = load("res://Scripts/gesture_animator.gd")
		if anim_script:
			gesture_animator = Node.new()
			gesture_animator.set_script(anim_script)
			gesture_animator.name = "GestureAnimator"
			add_child(gesture_animator)
			print("[Avatar] Dynamically added GestureAnimator node.")
		else:
			push_warning("[Avatar] Could not load gesture_animator.gd script.")

	# Connect the gesture animator's finished signal.
	if gesture_animator and gesture_animator.has_signal("animation_finished"):
		gesture_animator.animation_finished.connect(_on_gesture_animation_finished)

	# Start the idle animation so the avatar isn't in a T-pose.
	if animation_player and animation_player.has_animation("idle"):
		animation_player.play("idle")


func say_word(word: String) -> void:
	if tts_player:
		tts_player.speak(word)
	else:
		push_warning("[Avatar] TTSPlayer node not found.")


func play_animation(gesture_name: String) -> void:
	# Use the procedural gesture animator (driven by point-cloud data)
	# instead of pre-baked AnimationPlayer clips, except for specific overrides.
	if gesture_name == "ciao" and animation_player and animation_player.has_animation("wave"):
		animation_player.play("wave")
		return

	if gesture_animator:
		gesture_animator.play_gesture(gesture_name)
	else:
		push_warning("[Avatar] GestureAnimator not available, cannot play '%s'." % gesture_name)
		animation_finished.emit()


func _on_gesture_animation_finished() -> void:
	# Ensure idle keeps playing (the gesture animator already reset the bones).
	if not animation_player.is_playing() or animation_player.current_animation != "idle":
		animation_player.play("idle")
	animation_finished.emit()


func _on_animation_player_animation_finished(_anim_name: StringName) -> void:
	animation_player.play("idle")
	animation_finished.emit()
