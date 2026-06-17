extends MeshInstance3D
class_name DisplayMonitor

@onready var round_label: Label = $Display/SubViewport/UI/MarginContainer/VBoxContainer/HBoxContainer/RoundLabel
@onready var message_label: RichTextLabel = $Display/SubViewport/UI/MarginContainer/VBoxContainer/MessageLabel
@onready var progress_bar: ProgressBar = $Display/SubViewport/UI/MarginContainer/VBoxContainer/ProgressBar
@onready var timer: Timer = $Timer

var timer_going : bool = false
var current_timer_duration := 0.0

func _process(_delta: float) -> void:
	if not timer.is_stopped():
		progress_bar.value = timer.time_left / timer.wait_time * 100

func display_message(message: String) -> void:
	message_label.text = message

func set_round(round_num: int) -> void:
	round_label.text = "ROUND: %s" % round_num

func reset() -> void:
	set_round(1)
	reset_timer()
	display_message("")

func set_timer(duration: float) -> void:
	timer.start(duration)

func reset_timer() -> void:
	timer.stop()
	progress_bar.value = 0
