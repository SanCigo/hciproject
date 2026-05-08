extends Node

signal utterance_recorded(data: Dictionary)

const SPEECH_THRESHOLD := 0.02
const SILENCE_TIMEOUT_SEC := 0.4
const MIN_UTTERANCE_SEC := 0.3
const PRE_ROLL_SEC := 0.1

enum VADState { SILENT, SPEAKING }

var state: VADState = VADState.SILENT
var audio_player: AudioStreamPlayer
var capture_effect: AudioEffectCapture
var active := false

var pre_roll_buffer: Array[PackedVector2Array] = []
var utterance_frames: PackedVector2Array = []
var silence_timer := 0.0
var utterance_count := 0
var speech_start_datetime := ""


func _ready():
	_setup_microphone()


func _setup_microphone():
	AudioServer.add_bus()
	var bus_idx: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_idx, "MicCapture")
	AudioServer.set_bus_send(bus_idx, "Master")
	AudioServer.set_bus_mute(bus_idx, true)

	capture_effect = AudioEffectCapture.new()
	AudioServer.add_bus_effect(bus_idx, capture_effect)

	audio_player = AudioStreamPlayer.new()
	audio_player.stream = AudioStreamMicrophone.new()
	audio_player.bus = "MicCapture"
	add_child(audio_player)

	print("[VAD] Microphone ready.")


func start_listening():
	if active:
		return
	active = true
	state = VADState.SILENT
	pre_roll_buffer.clear()
	utterance_frames.clear()
	silence_timer = 0.0
	capture_effect.clear_buffer()
	audio_player.play()
	print("[VAD] Listening...")


func stop_listening():
	if not active:
		return
	active = false
	audio_player.stop()
	utterance_frames.clear()
	pre_roll_buffer.clear()
	state = VADState.SILENT
	print("[VAD] Stopped.")


func _process(_delta):
	if not active:
		return

	var available := capture_effect.get_frames_available()
	if available <= 0:
		return

	var frames := capture_effect.get_buffer(available)
	var frame_duration_sec: float = frames.size() / AudioServer.get_mix_rate()

	match state:
		VADState.SILENT:
			_process_silent(frames, frame_duration_sec)
		VADState.SPEAKING:
			_process_speaking(frames, frame_duration_sec)


func _process_silent(frames: PackedVector2Array, frame_duration_sec: float):
	pre_roll_buffer.append(frames)
	var pre_roll_max_chunks := int(PRE_ROLL_SEC / frame_duration_sec) + 1
	while pre_roll_buffer.size() > pre_roll_max_chunks:
		pre_roll_buffer.pop_front()

	if _get_amplitude(frames) >= SPEECH_THRESHOLD:
		state = VADState.SPEAKING
		silence_timer = 0.0
		utterance_frames.clear()

		# Record the datetime at the moment speech starts
		speech_start_datetime = _get_datetime_string()

		for chunk in pre_roll_buffer:
			utterance_frames.append_array(chunk)
		utterance_frames.append_array(frames)

		print("[VAD] Speech detected at: ", speech_start_datetime)


func _process_speaking(frames: PackedVector2Array, frame_duration_sec: float):
	utterance_frames.append_array(frames)

	if _get_amplitude(frames) < SPEECH_THRESHOLD:
		silence_timer += frame_duration_sec
		if silence_timer >= SILENCE_TIMEOUT_SEC:
			_finish_utterance()
	else:
		silence_timer = 0.0


func _finish_utterance():
	state = VADState.SILENT
	pre_roll_buffer.clear()

	var utterance_sec: float = utterance_frames.size() / AudioServer.get_mix_rate()
	print("[VAD] Utterance ended. Duration: %.2fs" % utterance_sec)

	if utterance_sec < MIN_UTTERANCE_SEC:
		print("[VAD] Too short, ignoring.")
		utterance_frames.clear()
		return

	utterance_count += 1
	var wav_path: String = "user://utterance_%d.wav" % utterance_count
	_save_wav(utterance_frames, wav_path)

	var data := {
		"id": utterance_count,
		"datetime": speech_start_datetime,
		"wav_path": wav_path,
		"transcription": ""     # Filled in by SpeechRecognition
	}

	print("[VAD] Utterance #%d recorded at %s" % [data.id, data.datetime])
	utterance_recorded.emit(data)
	utterance_frames.clear()


func _get_amplitude(frames: PackedVector2Array) -> float:
	var peak := 0.0
	for frame in frames:
		var amp: float = max(abs(frame.x), abs(frame.y))
		if amp > peak:
			peak = amp
	return peak


func _get_datetime_string() -> String:
	var dt := Time.get_datetime_dict_from_system()
	var ms := Time.get_ticks_msec() % 1000
	return "%04d-%02d-%02d %02d:%02d:%02d.%03d" % [
		dt.year, dt.month, dt.day,
		dt.hour, dt.minute, dt.second,
		ms
	]


func _save_wav(frames: PackedVector2Array, wav_path: String):
	var mono_bytes := PackedByteArray()
	for frame in frames:
		var mono_sample: float = (frame.x + frame.y) / 2.0
		var int_sample: int = int(clamp(mono_sample * 32767.0, -32768, 32767))
		mono_bytes.append(int_sample & 0xFF)
		mono_bytes.append((int_sample >> 8) & 0xFF)

	var file := FileAccess.open(wav_path, FileAccess.WRITE)
	var sample_rate: int = int(AudioServer.get_mix_rate())
	var data_size: int = mono_bytes.size()
	var byte_rate: int = sample_rate * 2

	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + data_size)
	file.store_buffer("WAVE".to_ascii_buffer())
	file.store_buffer("fmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(1)
	file.store_16(1)
	file.store_32(sample_rate)
	file.store_32(byte_rate)
	file.store_16(2)
	file.store_16(16)
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(data_size)
	file.store_buffer(mono_bytes)
	file.close()

	print("[VAD] WAV saved: ", wav_path)
