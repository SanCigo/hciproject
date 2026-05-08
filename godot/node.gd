
extends Node

var effect: AudioEffectCapture

func _ready():
	AudioServer.input_device = "Microphone Array (2- Realtek(R) Audio)"
	await get_tree().create_timer(0.5).timeout
	
	var idx = AudioServer.get_bus_index("Record")
	effect = AudioServer.get_bus_effect(idx, 0)
	
	var mic = AudioStreamPlayer.new()
	mic.stream = AudioStreamMicrophone.new()
	mic.bus = "Record"
	add_child(mic)
	mic.play()
	
	await get_tree().create_timer(1.0).timeout
	
	# Now start recording
	#var capture = get_node("CaptureStreamToText")
	#capture.recording = true

func _process(_delta):
	pass
