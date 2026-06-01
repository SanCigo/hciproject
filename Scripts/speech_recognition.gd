extends Node

signal speech_evaluated(result: bool)

@onready var vad: Node = $VAD
@onready var transcriber: Node = $Transcriber

var expected_speech := 0	# Name of required speech
							#set by "speech_required" signal from GameManager
var listening := false		# Tracks if the node is processing input

func _ready() -> void:
	vad.utterance_recorded.connect(_on_utterance_recorded)
	transcriber.transcription_ready.connect(_on_transcription_ready)

func _evaluate_speech(expected: int) -> void:
	expected_speech = expected
	vad.start_listening()
	listening = true
	print("[SpeechRecognition] Listening for: ", expected_speech)

func evaluate(transcription: String, keyword: int) -> bool:
	for word in GameData.keywords_dict[keyword]:
		if transcription.to_lower().contains(word):
			stop_listening()
			#print("the correct word has been said!\nstopped listening.")
			speech_evaluated.emit(true)
			return true
	return false

func stop_listening():
	expected_speech = 0
	vad.stop_listening()
	listening = false

func _on_utterance_recorded(data: Dictionary):
	print("[Test] Utterance #%d captured, sending to Whisper..." % data.id)
	transcriber.transcribe(data)

func _on_transcription_ready(data: Dictionary):
	print("[Test] #%d | %s | '%s'" % [data.id, data.datetime, data.transcription])
	if expected_speech != 0:
		evaluate(data.transcription, expected_speech)
