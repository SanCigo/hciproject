extends Node

signal speech_evaluated(result: bool)

@onready var vad: Node = $VAD
@onready var transcriber: Node = $Transcriber

var expected_speech := 0	# Name of required speech
							#set by "speech_required" signal from GameManager
var listening := false		# Tracks if the node is processing input
var pending_transcriptions := 0

func _ready() -> void:
	vad.utterance_recorded.connect(_on_utterance_recorded)
	transcriber.transcription_ready.connect(_on_transcription_ready)

func is_busy() -> bool:
	return vad.state == 1 or pending_transcriptions > 0

func _evaluate_speech(expected: int) -> void:
	expected_speech = expected
	vad.start_listening()
	listening = true
	print("[Speech to Text] Recognition starts")
	print("[SpeechRecognition] Listening for: ", expected_speech)

func evaluate(transcription: String, keyword: int) -> bool:
	var trans_lower = transcription.to_lower()
	
	var padded_trans = " "
	var has_letters = false
	for i in range(trans_lower.length()):
		var c = trans_lower[i]
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			padded_trans += c
			has_letters = true
		else:
			padded_trans += " "
	padded_trans += " "
	
	if not has_letters:
		return false
		
	var is_correct = false
	var found_wrong = false
	
	for k_id in GameData.keywords_dict:
		for word in GameData.keywords_dict[k_id]:
			if padded_trans.contains(" " + word.to_lower() + " "):
				if k_id == keyword:
					is_correct = true
				else:
					found_wrong = true
	
	if is_correct and not found_wrong:
		expected_speech = 0
		speech_evaluated.emit(true)
		return true
	elif found_wrong:
		print("[SpeechRecognition] Evaluated false (wrong keyword). Transcription: '%s' | expected: %d" % [transcription, keyword])
		expected_speech = 0
		speech_evaluated.emit(false)
		return false
	else:
		print("[SpeechRecognition] Ignored transcription: '%s' (no command detected)" % transcription)
		return false
func stop_listening():
	expected_speech = 0
	vad.stop_listening()
	listening = false

func _on_utterance_recorded(data: Dictionary):
	print("[Test] Utterance #%d captured, sending to Whisper..." % data.id)
	pending_transcriptions += 1
	transcriber.transcribe(data)

func _on_transcription_ready(data: Dictionary):
	pending_transcriptions = maxi(0, pending_transcriptions - 1)
	print("[Test] #%d | %s | '%s'" % [data.id, data.datetime, data.transcription])
	print("[Speech to Text] Recognized text: '%s'" % data.transcription)
	if expected_speech != 0:
		evaluate(data.transcription, expected_speech)
